#!/usr/bin/env bash
set -euo pipefail

# Certbot deploy hook: reload Nginx gateway after successful cert renewal.
# Usage (manual test):
#   sudo COMPOSE_PROJECT_ROOT=/opt/lexilingo bash scripts/ssl/reload-gateway-after-renew.sh

COMPOSE_PROJECT_ROOT="${COMPOSE_PROJECT_ROOT:-/opt/lexilingo}"
COMPOSE_FILE="${COMPOSE_PROJECT_ROOT}/docker-compose.yml"
ENV_FILE="${COMPOSE_PROJECT_ROOT}/.env.production"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Compose file not found: ${COMPOSE_FILE}"
  exit 1
fi

cd "${COMPOSE_PROJECT_ROOT}"
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" exec -T gateway nginx -t
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" exec -T gateway nginx -s reload

echo "Gateway reloaded after SSL renewal."
