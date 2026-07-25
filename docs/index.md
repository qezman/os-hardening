# Technical Walkthrough - Automated OS Hardening & Security Audit

This document is the full build log: what was provisioned, how each hardening step works, what broke along the way, and why specific design decisions were made. Screenshots referenced below should be placed in `docs/assets/` using the filenames suggested.

## 1. Architecture

```
![Architecture Diagram](./architecture.png)
```

A single VPC and public subnet host a 5-instance fleet (3 Ubuntu 22.04, 2 Amazon Linux 2023). Inbound access is restricted to one trusted IP on a single hardened SSH port, enforced independently at three layers: the AWS security group, each instance's host firewall, and the SSH daemon's own port binding. Instances authenticate to S3 via an IAM instance profile - no static AWS credentials exist anywhere in the codebase or on any host.

Elastic IPs are attached to each instance so its address survives a stop/start cycle, avoiding the churn of AWS's default ephemeral public IPs.

## 2. Infrastructure provisioning

Terraform is organized into four modules - `network`, `security-group`, `compliance-bucket`, `ec2-fleet` - wired together in a thin root `main.tf`. State is remote (S3, versioned) with DynamoDB-based locking to prevent concurrent-apply corruption.

Terraform plan output

The fleet is defined once, as a typed map, and created via `for_each` rather than five hardcoded resource blocks:

```hcl
resource "aws_instance" "fleet" {
  for_each = var.instances
  ami      = each.value.ami
  ...
}
```

Using `for_each` (keyed by name) instead of `count` (indexed by position) matters operationally: removing one entry from the map destroys exactly that instance, rather than shifting every subsequent index and forcing unrelated instances to be recreated.

`[02-instance-list](./assets/02-instance-list.png)`
`[02-instance-list-cli](./assets/02-instance-list-cli.png)`

## 3. IAM design

The automation user (`project2-automation`) runs under a hand-scoped policy, not `AdministratorAccess` - every permission was added only when a real `AccessDenied` error demanded it, then scoped as tightly as the error allowed. The full policy lives in `[iam-setup/project2-iam-policy.json](../iam-setup/project2-iam-policy.json)`.

Notable design points:

- All IAM resource management is scoped to `project2-*` named resources only - this automation user cannot touch any other role, policy, or instance profile in the account.
- `iam:PassRole` carries an explicit `iam:PassedToService: ec2.amazonaws.com` condition, so the scoped roles can only be handed to EC2, not to any other AWS service.
- The EC2 instance role itself is even narrower: `s3:PutObject`, scoped to a single bucket's object path - nothing else.

This iterative approach surfaced a real, recurring AWS provider behavior worth documenting: the `aws_iam_role` resource performs read-checks (`ListRolePolicies`, `ListAttachedRolePolicies`, `ListInstanceProfilesForRole`) on both create and destroy to detect drift, meaning a role-management policy needs list permissions even if the automation never intends to list anything itself. In a team environment, this policy would instead be derived from CloudTrail activity in a sandbox account rather than discovered live against real infrastructure.

## 4. SSH hardening

`scripts/harden.sh` runs the same logical sequence on every instance, branching only where the underlying OS tooling differs.

### Root login and password authentication

Disabled via idempotent check-then-modify logic against `sshd_config` - each setting is corrected in place if present, appended only if absent, so re-running the script never produces duplicate directives.

### Port migration - two-stage, verified

The riskiest step in the whole script: moving SSH off port 22. Rather than switching directly (which risks total lockout if anything is misconfigured), the migration happens in two deliberate stages:

1. `harden_ssh_port` adds port 2222 **alongside** port 22 - both active simultaneously.
2. Only after a human manually confirms a fresh connection succeeds on 2222 is `remove_legacy_ssh_port` called - a separate function, never auto-invoked - to remove port 22.

`[03-ubuntu-harden-run](./assets/03-ubuntu-harden-run.png)`
`[03a-ubuntu-harden-run](./assets/03a-ubuntu-harden-run.png)`
`[05-ubuntu-remove-port](./assets/05-ubuntu-remove-port)`


The same sequence on Amazon Linux, using the firewalld branch:

`[06-linux-harden-run](./assets/06-linux-harden-run.png)`
`[07-amzn-2222-verify](./assets/07-amzn-2222-verify)`
`[08-amzn-remove-port22](./assets/08-amzn-remove-port22.png)`

## 5. Host firewall - cross-distro

`harden_firewall` branches on distro, using each OS's native tool rather than forcing one tool onto both:


|                | Ubuntu                            | Amazon Linux                    |
| -------------- | --------------------------------- | ------------------------------- |
| Tool           | UFW                               | firewalld                       |
| Install check  | `command -v ufw`                  | `command -v firewall-cmd`       |
| Default policy | `deny incoming`, `allow outgoing` | `public` zone                   |
| Allowed port   | `2222/tcp`                        | `2222/tcp` (explicit port rule) |


One Amazon-Linux-specific detail caught during testing: firewalld's `public` zone ships with a default `ssh` **service** rule (port 22) independent of any port rules added manually - `firewall-cmd --permanent --remove-service=ssh` was required to fully close port 22 at this layer, since removing it wasn't otherwise implied by adding the 2222 port rule.

## 6. Automatic security patching

- **Ubuntu**: `unattended-upgrades` ships pre-installed and pre-configured on the official AMI; the script verifies and (re-)enables it rather than assuming a fresh install is needed.
- **Amazon Linux**: `dnf-automatic` requires installation. Its default configuration only *checks* for updates without applying them (`apply_updates = no`) - a real, easy-to-miss default that the script explicitly flips to `yes`.



## 7. Compliance reporting

`scripts/generate_report.sh` is a read-only checker, separate from `harden.sh` by design - it verifies current state rather than changing anything, and can be re-run independently (e.g. on a schedule) to catch drift.

Each check mirrors a specific hardening action and re-verifies it directly against live system state, rather than trusting that the hardening script's own prior output was accurate:

```bash
check_ssh_port() {
  if sudo grep -q "^Port 2222$" /etc/ssh/sshd_config && ! sudo grep -q "^Port 22$" /etc/ssh/sshd_config; then
    add_check_result "SSH migrated to hardened port 2222 only" "PASS"
  ...
```

This check caught a real gap during testing: two instances had `harden.sh` run on them but never received the manual `remove_legacy_ssh_port` follow-up, leaving port 22 still bound in `sshd_config` alongside 2222. The report flagged it as a FAIL, prompting the fix - a concrete example of the reporting layer doing its job independently of the hardening layer.

`[09-report-run](./assets/09-report-run.png)`
`[11-report-content](./assets/11-report-content.png)`


## 8. Design decision: Elastic IPs

Instances without an Elastic IP receive a new public IP on every stop/start cycle, which made iterative testing painful - trusted-IP security group rules and locally-cached IPs both went stale on every restart. Elastic IPs were added per-instance, keyed to the same `for_each` map as the instances themselves, so each EIP's lifecycle stays bound to its instance:

```hcl
resource "aws_eip" "fleet" {
  for_each = var.instances
  instance = aws_instance.fleet[each.key].id
  domain   = "vpc"
}
```

Verified directly: an instance was stopped and restarted, and its public IP was confirmed identical before and after.

## 9. Known limitations

- SSH access is gated by a manually maintained trusted-IP allowlist (`terraform.tfvars`). In production this would be replaced by AWS Systems Manager Session Manager, removing the need for any open inbound SSH port at all.
- Elastic IPs solve stop/start churn but are still released on a full `terraform destroy` - they do not survive a complete infrastructure teardown and rebuild.
- The trusted-IP DynamoDB/S3 backend bootstrap (state bucket, lock table, IAM user) is necessarily created outside Terraform, since Terraform cannot provision the backend it depends on - a standard, unavoidable chicken-and-egg exception, not an oversight.

