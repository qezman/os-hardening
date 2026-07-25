# Step-by-Step Walkthrough - Building This Project From Scratch

This is a chronological build guide: follow it top to bottom to reproduce this project from an empty AWS account. For the *why* behind each decision, see [`TECHNICAL.md`](TECHNICAL.md).

## Prerequisites

- An AWS account
- Terraform ≥ 1.10, AWS CLI v2, installed locally
- A Linux-native shell (WSL2 on Windows works; avoid running from a Windows-mounted path like `/mnt/c/...` - file permission commands like `chmod` don't reliably persist there)

Confirm your tools:
```bash
terraform -version
aws --version
```

## Step 1 - Create a scoped IAM user for this project

Don't reuse a broad or unrelated IAM identity. Using your account's root or an existing admin identity (console access, not CLI keys), create a dedicated user:

1. IAM → Users → Create user → name it e.g. `project-automation`
2. Attach `AmazonVPCFullAccess`, `AmazonEC2FullAccess`, `AmazonS3FullAccess` directly
3. Security credentials tab → Create access key → "Command Line Interface (CLI)"
4. Locally: `aws configure --profile <project-profile>`, paste in the key

You'll also need a **custom IAM policy** scoped to let this user manage its own project-specific IAM role and instance profile later (least-privilege - this user should not have blanket `IAMFullAccess`). Write a policy scoped to `role/<project>-*` and `instance-profile/<project>-*` resource patterns, covering create/get/delete/tag actions, plus a tightly-scoped `iam:PassRole` limited to `ec2.amazonaws.com` via a condition key. Create and attach it the same way, via the console.

Verify:
```bash
aws sts get-caller-identity --profile <project-profile>
```

## Step 2 - Bootstrap Terraform's remote state (manual, one-time)

Terraform can't create the backend it depends on, so this is done directly via CLI, once:

```bash
aws s3api create-bucket --bucket <unique-state-bucket-name> --region us-east-1 --profile <project-profile>
aws s3api put-bucket-versioning --bucket <unique-state-bucket-name> --versioning-configuration Status=Enabled --profile <project-profile>

aws dynamodb create-table \
  --table-name <project>-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --profile <project-profile>
```

(The DynamoDB step will need `dynamodb:CreateTable` added to your scoped policy from Step 1 - add it when the `AccessDenied` error names it, not preemptively.)

## Step 3 - Scaffold Terraform

Structure:
```
terraform/
  backend.tf       # points at the bucket + table from Step 2
  providers.tf      # aws provider, pinned to your named profile
  variables.tf       # region, trusted_ip_cidr (no default - supplied via tfvars), project_name
  main.tf             # wires modules together
  outputs.tf
  terraform.tfvars    # gitignored - your actual trusted_ip_cidr value
  modules/
    network/
    security-group/
    compliance-bucket/
    ec2-fleet/
```

Get your current public IP for `trusted_ip_cidr`:
```bash
curl ifconfig.me
```

## Step 4 - Build the `network` module

Resources: `aws_vpc`, `aws_subnet` (public, `map_public_ip_on_launch = true`), `aws_internet_gateway`, `aws_route_table` (with a `0.0.0.0/0` route to the IGW), `aws_route_table_association`. Output `vpc_id` and `public_subnet_id` - the next module needs them.

## Step 5 - Build the `security-group` module

One security group, ingress on **both** port 22 and port 2222 (you'll close 22 later, once SSH is fully migrated - see Step 8), scoped to `var.trusted_ip_cidr` only. Egress open (`0.0.0.0/0`) so instances can reach package repos and S3. Takes `vpc_id` as a required input (no default) - this is the first cross-module wiring: an output from `network` becomes an input here.

## Step 6 - Build the `compliance-bucket` module

An S3 bucket (versioned, all public access blocked) plus an IAM role that only EC2 can assume, with an inline policy granting `s3:PutObject` scoped to that one bucket's object path - not the bucket itself. Wrap the role in an `aws_iam_instance_profile`, since that's what actually attaches to an EC2 instance. Output the bucket name and instance profile name.

## Step 7 - Build the `ec2-fleet` module

Define your instance mix as a typed map (name → `{ ami, os_type }`), and create the fleet with a single `for_each`-driven `aws_instance` resource rather than one block per instance. Get current AMI IDs via SSM public parameters rather than hardcoding them:

```bash
aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id --region us-east-1 --profile <project-profile> --query 'Parameters[0].Value' --output text
aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --region us-east-1 --profile <project-profile> --query 'Parameters[0].Value' --output text
```

Also generate an SSH key pair inside Terraform itself (`tls_private_key` → `aws_key_pair` → `local_file` with `file_permission = "0400"`), and attach an `aws_eip` per instance (same `for_each` map, `instance = aws_instance.fleet[each.key].id`) so public IPs survive stop/start cycles.

## Step 8 - Wire the root module and apply

```hcl
module "network" { source = "./modules/network" }
module "security_group" { source = "./modules/security-group"; vpc_id = module.network.vpc_id; trusted_ip_cidr = var.trusted_ip_cidr }
module "compliance_bucket" { source = "./modules/compliance-bucket" }
module "ec2_fleet" {
  source = "./modules/ec2-fleet"
  subnet_id = module.network.public_subnet_id
  security_group_id = module.security_group.security_group_id
  iam_instance_profile_name = module.compliance_bucket.iam_instance_profile_name
}
```

```bash
terraform init
terraform plan
terraform apply
```

Confirm access:
```bash
chmod 400 <generated-key>.pem
ssh -i <key>.pem ubuntu@<ip>       # Ubuntu instances
ssh -i <key>.pem ec2-user@<ip>     # Amazon Linux instances
```

## Step 9 - Write the distro-detection helper

`scripts/lib/distro.sh` - a single function reading `/etc/os-release` and returning `ubuntu` or `amazon-linux`. Every OS-specific branch in the hardening script depends on this being right, so test it on a real instance of each type before building anything on top of it.

## Step 10 - Write `harden.sh`, one hardening action at a time

Build and test each piece **individually**, on a real instance, before adding the next:

1. **SSH lockdown** - `PermitRootLogin no`, `PasswordAuthentication no`, idempotent check-then-modify against `sshd_config`, restart `sshd`.
2. **Port migration (two stages)** - add `Port 2222` *alongside* `Port 22`, restart, and manually verify a fresh connection on 2222 works before ever removing 22. Keep "remove port 22" as its own separate function, called manually - never auto-chained after adding it.
3. **Host firewall** - branch on distro: UFW for Ubuntu, firewalld for Amazon Linux. Both: default-deny inbound, allow only 2222. On Amazon Linux specifically, also explicitly remove firewalld's default `ssh` service rule (port 22), since adding a 2222 port rule doesn't implicitly remove it.
4. **Automatic patching** - `unattended-upgrades` (Ubuntu, usually pre-installed - verify and enable rather than assume) / `dnf-automatic` (Amazon Linux - install, and flip `apply_updates` from `no` to `yes` in its config, since the default only checks, never applies).

Test each function on one instance of each OS before rolling out to the rest. Use `set -euo pipefail` at the top of the script, and `sudo` on every `grep`/`sed` touching `sshd_config` (Amazon Linux's stricter file permissions will silently fail reads without it - a real, easy-to-miss bug).

## Step 11 - Roll hardening out to the full fleet

For each instance:
```bash
scp -i <key>.pem -r scripts <user>@<ip>:~/
ssh -i <key>.pem <user>@<ip>
cd scripts && ./harden.sh
```
Verify port 2222 from a **second**, fresh terminal before closing the first. Then, manually:
```bash
source harden.sh
remove_legacy_ssh_port
```
Verify 2222 still works after that too.

## Step 12 - Write and run the compliance report script

`scripts/generate_report.sh` - a separate, read-only script. Each check independently re-verifies a hardening outcome against live system state (don't trust the hardening script's own prior output). Build the markdown via a heredoc, then upload with the AWS CLI (install it first if missing - not preinstalled on the Ubuntu AMI):

```bash
aws s3 cp "$REPORT_FILE" "s3://<bucket>/${HOSTNAME}/${TIMESTAMP}.md"
```

Run it on every instance once hardening is confirmed complete.

## Step 13 - Close the loop on port 22

Once **every** instance is confirmed reachable on 2222 only, remove the port-22 ingress rule from the security group in Terraform - the final network-layer closure, applied fleet-wide in one `apply`.

## Step 14 - Verify, screenshot, document

Confirm the whole story end to end: `terraform plan`/`apply` output, the instance list, one full hardening run per OS, port verification, the report's S3 upload, and the report's actual contents. These become the evidence in your technical documentation.

## Step 15 - Tear down

```bash
terraform destroy
```
Leave the state bucket, lock table, and IAM user in place if you intend to rebuild - everything else (fleet, SG, compliance bucket, IAM role) is disposable and Terraform-managed.
