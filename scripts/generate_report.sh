#!/bin/bash
# Generates a markdown compliance report reflecting the current
# hardening state of this instance, then uploads it to S3.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/distro.sh"

DISTRO=$(detect_distro)
HOSTNAME_TAG=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
REPORT_FILE="/tmp/compliance-${HOSTNAME_TAG}-${TIMESTAMP}.md"
S3_BUCKET="project2-os-hardening-reports-560205084952"

# Running tally of results, plus the growing markdown body each check
# appends a line to
CHECKS_PASSED=0
CHECKS_FAILED=0
REPORT_BODY=""

# Shared helper so every check formats its result identically
add_check_result() {
  local check_name="$1"
  local status="$2"

  if [ "$status" == "PASS" ]; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    REPORT_BODY+="- **${check_name}**: PASS\n"
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    REPORT_BODY+="- **${check_name}**: FAIL\n"
  fi
}

# Each check below mirrors a specific harden.sh action
check_root_login() {
  if sudo grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    add_check_result "Root SSH login disabled" "PASS"
  else
    add_check_result "Root SSH login disabled" "FAIL"
  fi
}

check_password_auth() {
  if sudo grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
    add_check_result "Password authentication disabled" "PASS"
  else
    add_check_result "Password authentication disabled" "FAIL"
  fi
}

check_ssh_port() {
  # Pass only if 2222 is present AND 22 has been removed 
  # matches the end state after remove_legacy_ssh_port has run
  if sudo grep -q "^Port 2222$" /etc/ssh/sshd_config && ! sudo grep -q "^Port 22$" /etc/ssh/sshd_config; then
    add_check_result "SSH migrated to hardened port 2222 only" "PASS"
  else
    add_check_result "SSH migrated to hardened port 2222 only" "FAIL"
  fi
}

check_firewall() {
  # Different tool per distro
  if [ "$DISTRO" == "ubuntu" ]; then
    if sudo ufw status | grep -q "Status: active"; then
      add_check_result "Host firewall (UFW) active" "PASS"
    else
      add_check_result "Host firewall (UFW) active" "FAIL"
    fi
  elif [ "$DISTRO" == "amazon-linux" ]; then
    if sudo systemctl is-active --quiet firewalld; then
      add_check_result "Host firewall (firewalld) active" "PASS"
    else
      add_check_result "Host firewall (firewalld) active" "FAIL"
    fi
  fi
}

check_patching() {
  # Ubuntu: check the service is enabled 
  # Amazon Linux: check the systemd timer is active
  if [ "$DISTRO" == "ubuntu" ]; then
    if systemctl is-enabled --quiet unattended-upgrades; then
      add_check_result "Automatic security patching enabled" "PASS"
    else
      add_check_result "Automatic security patching enabled" "FAIL"
    fi
  elif [ "$DISTRO" == "amazon-linux" ]; then
    if systemctl is-active --quiet dnf-automatic.timer; then
      add_check_result "Automatic security patching enabled" "PASS"
    else
      add_check_result "Automatic security patching enabled" "FAIL"
    fi
  fi
}

run_all_checks() {
  echo "--- Running compliance checks ---"
  check_root_login
  check_password_auth
  check_ssh_port
  check_firewall
  check_patching
}

# Heredoc (cat > file <<EOF ... EOF) writes the whole markdown block in
# one shot
build_report() {
  cat > "$REPORT_FILE" <<EOF
# Compliance Report

**Host:** ${HOSTNAME_TAG}
**OS:** ${DISTRO}
**Generated:** ${TIMESTAMP}

## Summary

- Checks passed: ${CHECKS_PASSED}
- Checks failed: ${CHECKS_FAILED}

## Details

$(echo -e "$REPORT_BODY")
EOF

  echo "Report written to $REPORT_FILE"
}

ensure_aws_cli() {
  if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found, installing..."
    if [ "$DISTRO" == "ubuntu" ]; then
      sudo apt-get update -qq
      sudo apt-get install -y awscli
    elif [ "$DISTRO" == "amazon-linux" ]; then
      sudo dnf install -y awscli
    fi
  fi
}

# Relies on the IAM instance profile attached in Terraform
# (compliance-bucket module)
upload_report() {
  echo "--- Uploading report to S3 ---"
  aws s3 cp "$REPORT_FILE" "s3://${S3_BUCKET}/${HOSTNAME_TAG}/${TIMESTAMP}.md"
  echo "--- Upload complete ---"
}

run_all_checks
build_report
ensure_aws_cli
upload_report