#!/usr/bin/env bash
set -uo pipefail

# Invoked by systemd OnFailure=. A backup that fails quietly is worse than no
# backup at all, because the schedule keeps pruning good copies while you
# believe you are covered.

FAILED_UNIT="${1:-unknown.service}"
STATE_DIR="${STATE_DIR:-/var/lib/lexilingo}"
MARKER="${STATE_DIR}/backup-failure.state"
WEBHOOK="${ALERT_WEBHOOK_URL:-}"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${STATE_DIR}"
{
  echo "failed_unit=${FAILED_UNIT}"
  echo "timestamp_utc=${STAMP}"
  echo "host=$(hostname)"
} > "${MARKER}"

# Priority 2 (crit) so it stands out in `journalctl -p crit`.
logger -p user.crit -t lexilingo-backup "BACKUP FAILURE in ${FAILED_UNIT} at ${STAMP} — production data is NOT protected"

journalctl -u "${FAILED_UNIT}" -n 30 --no-pager > "${STATE_DIR}/backup-failure.log" 2>/dev/null || true

if [[ -n "${WEBHOOK}" ]]; then
  curl -sS -m 15 -X POST -H 'Content-Type: application/json' \
    -d "{\"text\":\"🔴 LexiLingo BACKUP FAILURE: ${FAILED_UNIT} at ${STAMP} on $(hostname). Production data is not protected.\"}" \
    "${WEBHOOK}" >/dev/null 2>&1 \
    && echo "alert posted to webhook" \
    || echo "WARNING: webhook post failed"
else
  echo "WARNING: ALERT_WEBHOOK_URL unset — failure recorded to ${MARKER} only"
fi

echo "Backup failure recorded: ${MARKER}"
