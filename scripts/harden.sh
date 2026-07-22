#!/bin/bash
# Master OS-hardening script 
# Run locally on each target instance (copied over via scp, or executed
# remotely via an SSH loop from the operator's machine).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/distro.sh"

DISTRO=$(detect_distro)
echo "Detected OS: $DISTRO"

if [ "$DISTRO" == "unknown" ]; then
  echo "ERROR: Unsupported or undetected OS. Aborting."
  exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"

harden_ssh() {
  echo "--- Hardening SSH configuration ---"

  # Disable root login over SSH entirely.
  if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
    sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
  else
    echo "PermitRootLogin no" | sudo tee -a "$SSHD_CONFIG" > /dev/null
  fi

  # Disable password authentication - key-based only.
  if grep -q "^PasswordAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
  else
    echo "PasswordAuthentication no" | sudo tee -a "$SSHD_CONFIG" > /dev/null
  fi

  echo "SSH config updated. Restarting sshd..."
  sudo systemctl restart sshd

  echo "--- SSH hardening complete ---"
}


harden_ssh_port() {
  echo "--- Adding hardened SSH port (2222) alongside port 22 ---"

  # Ensure Port 22 is explicit
  if grep -q "^Port 22$" "$SSHD_CONFIG"; then
    echo "Port 22 already explicit - skipping."
  else
    echo "Port 22" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    echo "Added explicit 'Port 22'."
  fi

  # Add Port 2222 alongside it - Verify 2222
  # works before cutting off the fallback port in a later, separate step.
  if grep -q "^Port 2222$" "$SSHD_CONFIG"; then
    echo "Port 2222 already configured - skipping."
  else
    echo "Port 2222" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    echo "Added 'Port 2222'."
  fi

  echo "Restarting sshd..."
  sudo systemctl restart sshd

  echo "--- Hardened port added. Verify port 2222 works BEFORE removing port 22. ---"
}

harden_ssh
harden_ssh_port