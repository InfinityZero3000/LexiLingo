#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

SCRIPT_NAME="backup-prod"
# shellcheck source=scripts/lib-backup-common.sh
source "${PROJECT_ROOT}/scripts/lib-backup-common.sh"

DOCKER_COMPOSE_CMD="sudo docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml"
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
# Never prune below this many complete backup sets, however old they are — a
# long outage must not silently age out the last good copy.
MIN_KEEP_SETS="${MIN_KEEP_SETS:-7}"
# Optional off-site push, e.g. OFFSITE_RCLONE_REMOTE=b2:lexilingo-backups
OFFSITE_RCLONE_REMOTE="${OFFSITE_RCLONE_REMOTE:-}"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MONGO_DB="$(grep -E '^MONGODB_DATABASE=' .env.production | tail -n 1 | cut -d '=' -f 2-)"
MONGO_DB="${MONGO_DB:-lexilingo}"

mkdir -p "${BACKUP_DIR}"

PG_FILE="${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"
MONGO_FILE="${BACKUP_DIR}/mongodb_${TIMESTAMP}.archive.gz"
MANIFEST_FILE="${BACKUP_DIR}/manifest_${TIMESTAMP}.txt"

# A half-written dump left on disk looks like a valid backup to every later
# reader, so remove the partial set if we abort anywhere below.
cleanup_partial() {
  local code=$?
  if (( code != 0 )); then
    log "FAILED (exit ${code}) — removing partial backup set ${TIMESTAMP}"
    rm -f "${PG_FILE}" "${MONGO_FILE}" "${MANIFEST_FILE}"
  fi
  exit "${code}"
}
trap cleanup_partial EXIT

log "Creating PostgreSQL backup -> ${PG_FILE}"
${DOCKER_COMPOSE_CMD} exec -T postgres sh -lc \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' | gzip -c > "${PG_FILE}"
assert_gzip_intact "${PG_FILE}" "postgres backup"
assert_not_shrunk "${PG_FILE}" "postgres backup"

log "Creating MongoDB backup (${MONGO_DB}) -> ${MONGO_FILE}"
${DOCKER_COMPOSE_CMD} exec -T -e MONGO_DB="${MONGO_DB}" mongodb sh -lc \
  'mongodump --archive --gzip --db "$MONGO_DB"' > "${MONGO_FILE}"
assert_gzip_intact "${MONGO_FILE}" "mongo backup"
assert_not_shrunk "${MONGO_FILE}" "mongo backup"

sha256sum "${PG_FILE}" "${MONGO_FILE}" > "${MANIFEST_FILE}"
log "Backup manifest -> ${MANIFEST_FILE}"

# ── Off-site copy ───────────────────────────────────────────────────────────
# Backups on the same disk as the database die with the disk. This is opt-in
# because it needs a configured rclone remote; when unset we say so loudly
# rather than implying the data is safe.
if [[ -n "${OFFSITE_RCLONE_REMOTE}" ]]; then
  if command -v rclone >/dev/null 2>&1; then
    log "Copying backup set off-site -> ${OFFSITE_RCLONE_REMOTE}"
    rclone copy "${PG_FILE}" "${OFFSITE_RCLONE_REMOTE}/" --no-traverse
    rclone copy "${MONGO_FILE}" "${OFFSITE_RCLONE_REMOTE}/" --no-traverse
    rclone copy "${MANIFEST_FILE}" "${OFFSITE_RCLONE_REMOTE}/" --no-traverse
    log "Off-site copy complete"
  else
    log "WARNING: OFFSITE_RCLONE_REMOTE set but rclone is not installed — backup is LOCAL ONLY"
  fi
else
  log "WARNING: no OFFSITE_RCLONE_REMOTE configured — backup is LOCAL ONLY (same disk as the database)"
fi

# ── Retention ───────────────────────────────────────────────────────────────
# Count complete sets before pruning; if we are at or below the floor, keep
# everything regardless of age.
set_count="$(find "${BACKUP_DIR}" -maxdepth 1 -name 'manifest_*.txt' | wc -l | tr -d '[:space:]')"
if (( set_count > MIN_KEEP_SETS )); then
  find "${BACKUP_DIR}" -maxdepth 1 -type f -mtime +"${RETENTION_DAYS}" \
    \( -name 'postgres_*.sql.gz' -o -name 'mongodb_*.archive.gz' -o -name 'manifest_*.txt' \) -delete
  log "Pruned backups older than ${RETENTION_DAYS} days (kept >= ${MIN_KEEP_SETS} sets)"
else
  log "Only ${set_count} backup set(s) present — retention skipped to protect the floor of ${MIN_KEEP_SETS}"
fi

log "Done"
