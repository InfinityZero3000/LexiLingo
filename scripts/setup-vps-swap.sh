#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo SWAP_SIZE_GB=4 VM_SWAPPINESS=10 VM_VFS_CACHE_PRESSURE=50 bash scripts/setup-vps-swap.sh

SWAP_SIZE_GB="${SWAP_SIZE_GB:-4}"
VM_SWAPPINESS="${VM_SWAPPINESS:-10}"
VM_VFS_CACHE_PRESSURE="${VM_VFS_CACHE_PRESSURE:-50}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

if [[ -f /swapfile ]]; then
  echo "/swapfile already exists. Skipping allocation."
else
  echo "Allocating ${SWAP_SIZE_GB}G swapfile..."
  fallocate -l "${SWAP_SIZE_GB}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1G count="${SWAP_SIZE_GB}" status=progress
  chmod 600 /swapfile
  mkswap /swapfile
fi

if ! swapon --show | grep -q '/swapfile'; then
  swapon /swapfile
fi

if ! grep -q '^/swapfile ' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

cat >/etc/sysctl.d/99-lexilingo-swap.conf <<EOF
vm.swappiness=${VM_SWAPPINESS}
vm.vfs_cache_pressure=${VM_VFS_CACHE_PRESSURE}
EOF

sysctl --system >/dev/null

echo "Swap configured successfully."
swapon --show
echo "---"
free -h
