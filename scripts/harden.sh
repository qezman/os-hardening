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
  if sudo grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
    sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
  else
    echo "PermitRootLogin no" | sudo tee -a "$SSHD_CONFIG" > /dev/null
  fi

  # Disable password authentication - key-based only.
  if sudo grep -q "^PasswordAuthentication" "$SSHD_CONFIG"; then
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
  if sudo grep -q "^Port 22$" "$SSHD_CONFIG"; then
    echo "Port 22 already explicit - skipping."
  else
    echo "Port 22" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    echo "Added explicit 'Port 22'."
  fi

  # Add Port 2222 alongside it - Verify 2222
  # works before cutting off the fallback port in a later, separate step.
  if sudo grep -q "^Port 2222$" "$SSHD_CONFIG"; then
    echo "Port 2222 already configured - skipping."
  else
    echo "Port 2222" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    echo "Added 'Port 2222'."
  fi

  echo "Restarting sshd..."
  sudo systemctl restart sshd

  echo "--- Hardened port added. Verify port 2222 works BEFORE removing port 22. ---"
}

remove_legacy_ssh_port() {
  echo "--- Removing legacy port 22 (2222 already verified working) ---"

  if grep -q "^Port 22$" "$SSHD_CONFIG"; then
    sudo sed -i '/^Port 22$/d' "$SSHD_CONFIG"
    echo "Removed 'Port 22' from sshd_config."
  else
    echo "Port 22 not present - nothing to remove."
  fi

  echo "Restarting sshd..."
  sudo systemctl restart sshd

  echo "--- Port 22 removed. SSH now available on 2222 only. ---"
}

harden_firewall() {
  echo "--- Configuring firewall ---"

  if [ "$DISTRO" == "ubuntu" ]; then
    echo "Using UFW (ubuntu)"

      if ! command -v ufw &> /dev/null; then
        echo "UFW not found, installing..."
        sudo apt-get update -qq
        sudo apt-get install -y ufw
      fi

      # Default deny all inbound, allow all outbound.
      sudo ufw default deny incoming
      sudo ufw default allow outgoing

      # Only allow the hardened SSH port - port 22 is already closed at
      # the sshd level and the sg
      sudo ufw allow 2222/tcp

      # --force skips the interactive "are you sure" prompt, since this
      # script needs to run non-interactively.
      sudo ufw --force enable

      echo "--- Firewall configured. Status: ---"
      sudo ufw status verbose

  
  elif [ "$DISTRO" == "amazon-linux" ]; then
      echo "Using firewalld (Amazon Linux)"

      if ! command -v firewall-cmd &> /dev/null; then
        echo "Firewalld not found, installing..."
        sudo dnf update -y
        sudo dnf install -y firewalld
      fi

      # --force skips the interactive "are you sure" prompt, since this
      # script needs to run non-interactively.
      sudo systemctl enable --now firewalld
      sleep 2
      sudo systemctl is-active --quiet firewalld || { echo "ERROR: firewalld failed to start"; exit 1; }


      # Default deny all inbound, allow all outbound.
      sudo firewall-cmd --set-default-zone=public

      # Only allow the hardened SSH port - port 22 is already closed at
      # the sshd level and the sg
      sudo firewall-cmd --permanent --add-port=2222/tcp
      sudo firewall-cmd --permanent --remove-service=ssh
      sudo firewall-cmd --reload

      echo "--- Firewall configured. Status: ---"
      sudo firewall-cmd --list-all
    fi
      
}

harden_ssh
harden_ssh_port
# remove_legacy_ssh_port # run manually only after verifying port 2222 access
harden_firewall