#!/usr/bin/env bash
set -euo pipefail

# Certbot deploy hook: reload Nginx gateway after successful cert renewal.
# Usage (manual test):
#   sudo bash scripts/ssl/reload-gateway-after-renew.sh

GATEWAY_CONTAINER="${GATEWAY_CONTAINER:-lexilingo-gateway}"

docker exec "${GATEWAY_CONTAINER}" nginx -t
docker exec "${GATEWAY_CONTAINER}" nginx -s reload

echo "Gateway reloaded after SSL renewal."
