#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo PROJECT_ROOT=/opt/lexilingo bash scripts/ssl/install-certbot-timer.sh

PROJECT_ROOT="${PROJECT_ROOT:-/opt/lexilingo}"
SERVICE_SRC="${PROJECT_ROOT}/deploy/systemd/lexilingo-certbot-renew.service"
TIMER_SRC="${PROJECT_ROOT}/deploy/systemd/lexilingo-certbot-renew.timer"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

apt-get update
apt-get install -y certbot

if [[ ! -f "${SERVICE_SRC}" || ! -f "${TIMER_SRC}" ]]; then
  echo "Systemd template files not found under ${PROJECT_ROOT}/deploy/systemd"
  exit 1
fi

install -m 0644 "${SERVICE_SRC}" /etc/systemd/system/lexilingo-certbot-renew.service
install -m 0644 "${TIMER_SRC}" /etc/systemd/system/lexilingo-certbot-renew.timer

systemctl daemon-reload
systemctl enable --now lexilingo-certbot-renew.timer

echo "=== Timer status ==="
systemctl status lexilingo-certbot-renew.timer --no-pager

echo "=== Next runs ==="
systemctl list-timers lexilingo-certbot-renew.timer --no-pager
