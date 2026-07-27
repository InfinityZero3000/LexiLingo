#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SERVICE="${ROOT}/deploy/systemd/lexilingo-certbot-renew.service"
SMOKE="${ROOT}/scripts/smoke-prod.sh"
INSTALLER="${ROOT}/scripts/ssl/install-certbot-timer.sh"

grep -Fq -- '--webroot -w /opt/lexilingo/gateway/nginx/acme-challenge' "${SERVICE}"
grep -Fq -- '--deploy-hook /usr/local/sbin/lexilingo-reload-gateway-after-renew' "${SERVICE}"
grep -Fq 'install -o root -g root -m 0755 "${HOOK_SRC}" /usr/local/sbin/lexilingo-reload-gateway-after-renew' "${INSTALLER}"

for preflight in \
  '/api/v1/auth/google POST' \
  '/api/v1/auth/refresh POST' \
  '/api/v1/auth/me GET'; do
  grep -Fq "${preflight}" "${SMOKE}"
done
grep -Fq 'access-control-allow-credentials: true' "${SMOKE}"
grep -Fq 'authorization.*content-type|content-type.*authorization' "${SMOKE}"
grep -Fq "Origin: https://attacker.example" "${SMOKE}"
grep -Fq 'if printf '\''%s'\'' "${headers}" | grep -Fqi '\''access-control-allow-origin:'\''' "${SMOKE}"

echo 'Admin login SSL/CORS regression checks passed.'
