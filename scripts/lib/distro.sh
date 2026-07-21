#!/bin/bash
# Detects the host's OS family so harden.sh can branch between
# apt/ufw (Ubuntu) and dnf/firewalld (Amazon Linux) command sets.

detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      ubuntu)
        echo "ubuntu"
        ;;
      amzn)
        echo "amazon-linux"
        ;;
      *)
        echo "unknown"
        ;;
    esac
  else
    echo "unknown"
  fi
}