#!/usr/bin/env bash
set -euo pipefail

# Restore the newest backup into a disposable container and assert real user
# data came back. An unrestored backup is a hypothesis; this makes it a fact.
# Never touches production — the throwaway container has its own volume and is
# removed on exit.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

SCRIPT_NAME="verify-backup"
# shellcheck source=scripts/lib-backup-common.sh
source "${PROJECT_ROOT}/scripts/lib-backup-common.sh"

BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
PG_IMAGE="${PG_IMAGE:-postgres:16-alpine}"
CONTAINER="lexilingo-verify-$$"
PG_BACKUP="${1:-}"

# Tables that must exist and be non-empty for the backup to be worth keeping.
REQUIRED_TABLES=(users courses lessons)

cleanup() {
  sudo docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ -z "${PG_BACKUP}" ]]; then
  PG_BACKUP="$(find "${BACKUP_DIR}" -maxdepth 1 -name 'postgres_*.sql.gz' | sort | tail -1)"
fi
[[ -n "${PG_BACKUP}" ]] || die "no postgres backup found in ${BACKUP_DIR}"

log "Verifying $(basename "${PG_BACKUP}")"
assert_gzip_intact "${PG_BACKUP}" "postgres backup"
verify_against_manifest "${PG_BACKUP}"

log "Starting disposable ${PG_IMAGE} container"
sudo docker run -d --name "${CONTAINER}" \
  -e POSTGRES_PASSWORD=verify -e POSTGRES_USER=verify -e POSTGRES_DB=verify \
  "${PG_IMAGE}" >/dev/null

for _ in $(seq 1 60); do
  if sudo docker exec "${CONTAINER}" pg_isready -U verify >/dev/null 2>&1; then break; fi
  sleep 1
done
sudo docker exec "${CONTAINER}" pg_isready -U verify >/dev/null 2>&1 \
  || die "disposable postgres never became ready"

log "Restoring into the disposable container"
gunzip -c "${PG_BACKUP}" \
  | sudo docker exec -i "${CONTAINER}" psql -v ON_ERROR_STOP=1 -U verify -d verify >/dev/null \
  || die "restore failed — THIS BACKUP IS NOT USABLE"

failures=0
for table in "${REQUIRED_TABLES[@]}"; do
  count="$(sudo docker exec "${CONTAINER}" psql -tAU verify -d verify \
    -c "SELECT count(*) FROM ${table};" 2>/dev/null || echo "ERR")"
  if [[ "${count}" == "ERR" ]]; then
    log "FAIL  ${table}: table missing from backup"
    failures=$((failures + 1))
  elif (( count == 0 )); then
    log "FAIL  ${table}: restored but empty"
    failures=$((failures + 1))
  else
    log "ok    ${table}: ${count} rows"
  fi
done

(( failures == 0 )) || die "${failures} check(s) failed — backup is NOT trustworthy"

log "VERIFIED: $(basename "${PG_BACKUP}") restores cleanly with user data intact"
