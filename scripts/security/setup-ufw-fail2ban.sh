#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo PROJECT_ROOT=/opt/lexilingo bash scripts/security/setup-ufw-fail2ban.sh

PROJECT_ROOT="${PROJECT_ROOT:-/opt/lexilingo}"
FAIL2BAN_FILTER_SRC="${PROJECT_ROOT}/deploy/fail2ban/filter.d/nginx-429-abuse.conf"
FAIL2BAN_JAIL_SRC="${PROJECT_ROOT}/deploy/fail2ban/jail.d/lexilingo-nginx.local"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

apt-get update
apt-get install -y ufw fail2ban

# UFW baseline: deny incoming, allow outgoing, open only 22/80/443
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

if [[ ! -f "${FAIL2BAN_FILTER_SRC}" ]]; then
  echo "Missing fail2ban filter source: ${FAIL2BAN_FILTER_SRC}"
  exit 1
fi
if [[ ! -f "${FAIL2BAN_JAIL_SRC}" ]]; then
  echo "Missing fail2ban jail source: ${FAIL2BAN_JAIL_SRC}"
  exit 1
fi

install -m 0644 "${FAIL2BAN_FILTER_SRC}" /etc/fail2ban/filter.d/nginx-429-abuse.conf
install -m 0644 "${FAIL2BAN_JAIL_SRC}" /etc/fail2ban/jail.d/lexilingo-nginx.local

systemctl enable fail2ban
systemctl restart fail2ban

echo "=== UFW status ==="
ufw status verbose

echo "=== Fail2ban status ==="
fail2ban-client status
echo "=== Fail2ban nginx-429-abuse ==="
fail2ban-client status nginx-429-abuse || true
