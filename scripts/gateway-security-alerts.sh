#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-gateway/nginx/logs/security.log}"
WINDOW_MINUTES="${WINDOW_MINUTES:-5}"
MAX_4XX="${MAX_4XX:-150}"
MAX_5XX="${MAX_5XX:-40}"
MAX_AUTH_429="${MAX_AUTH_429:-30}"

if [[ ! -f "${LOG_FILE}" ]]; then
  echo "[gateway-alerts] log file not found: ${LOG_FILE}"
  exit 2
fi

# NOTE: We assume time_iso8601 in log_format and rely on recent tail slice for low overhead.
# This keeps script simple and safe for cron use.
RECENT_LINES="$(tail -n 5000 "${LOG_FILE}")"

count_4xx=$(printf '%s\n' "${RECENT_LINES}" | grep -Ec '"status":4[0-9]{2}' || true)
count_5xx=$(printf '%s\n' "${RECENT_LINES}" | grep -Ec '"status":5[0-9]{2}' || true)
count_auth_429=$(printf '%s\n' "${RECENT_LINES}" | grep -Ec '"status":429.*"uri":"/api/v1/auth/' || true)

echo "[gateway-alerts] window=${WINDOW_MINUTES}m 4xx=${count_4xx} 5xx=${count_5xx} auth429=${count_auth_429}"

breach=0
if (( count_4xx > MAX_4XX )); then
  echo "[ALERT] 4xx spike detected: ${count_4xx} > ${MAX_4XX}"
  breach=1
fi

if (( count_5xx > MAX_5XX )); then
  echo "[ALERT] 5xx spike detected: ${count_5xx} > ${MAX_5XX}"
  breach=1
fi

if (( count_auth_429 > MAX_AUTH_429 )); then
  echo "[ALERT] auth rate-limit burst detected: ${count_auth_429} > ${MAX_AUTH_429}"
  breach=1
fi

if (( breach == 1 )); then
  exit 1
fi

echo "[gateway-alerts] thresholds ok"
