#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

SCRIPT_NAME="restore-prod"
# shellcheck source=scripts/lib-backup-common.sh
source "${PROJECT_ROOT}/scripts/lib-backup-common.sh"

DOCKER_COMPOSE_CMD="sudo docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml"
SAFETY_DIR="${SAFETY_DIR:-${PROJECT_ROOT}/backups/pre-restore}"
POSTGRES_BACKUP=""
MONGO_BACKUP=""
FORCE=false
SKIP_SAFETY=false

usage() {
  cat <<'EOF'
Usage: ./scripts/restore-prod.sh [options]

Options:
  --postgres-backup <file>   Restore PostgreSQL from .sql.gz backup
  --mongo-backup <file>      Restore MongoDB from .archive.gz backup
  --force                    Skip destructive action confirmation
  --skip-safety-dump         Do NOT snapshot current data first (discouraged)
  -h, --help                 Show this help message

Every restore verifies the backup and snapshots current production BEFORE
dropping anything, so a bad backup can never leave you with no data at all.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --postgres-backup) POSTGRES_BACKUP="$2"; shift 2 ;;
    --mongo-backup) MONGO_BACKUP="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --skip-safety-dump) SKIP_SAFETY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "${POSTGRES_BACKUP}" && -z "${MONGO_BACKUP}" ]]; then
  echo "At least one backup file must be provided."
  usage
  exit 1
fi

# ── Pre-flight: prove the backup is usable BEFORE touching production ────────
# The old version dropped the schema first and only then piped the archive in,
# so a truncated dump destroyed prod with nothing left to restore from.
log "Pre-flight verification (nothing is modified yet)"
if [[ -n "${POSTGRES_BACKUP}" ]]; then
  assert_gzip_intact "${POSTGRES_BACKUP}" "postgres backup"
  verify_against_manifest "${POSTGRES_BACKUP}"
  gunzip -c "${POSTGRES_BACKUP}" | head -c 4096 | grep -qiE 'PostgreSQL database dump|CREATE TABLE|SET statement_timeout' \
    || die "postgres backup does not look like a pg_dump — refusing to restore"
fi
if [[ -n "${MONGO_BACKUP}" ]]; then
  assert_gzip_intact "${MONGO_BACKUP}" "mongo backup"
  verify_against_manifest "${MONGO_BACKUP}"
fi
log "Pre-flight passed"

if [[ "${FORCE}" != true ]]; then
  echo
  echo "WARNING: This will overwrite live production data."
  [[ -n "${POSTGRES_BACKUP}" ]] && echo "  postgres <- ${POSTGRES_BACKUP}"
  [[ -n "${MONGO_BACKUP}" ]] && echo "  mongodb  <- ${MONGO_BACKUP}"
  read -r -p "Type 'RESTORE NOW' to continue: " confirm
  if [[ "${confirm}" != "RESTORE NOW" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# ── Safety snapshot: current prod, so a bad restore is itself reversible ─────
SAFETY_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SAFETY_PG="${SAFETY_DIR}/postgres_pre-restore_${SAFETY_STAMP}.sql.gz"
SAFETY_MONGO="${SAFETY_DIR}/mongodb_pre-restore_${SAFETY_STAMP}.archive.gz"

if [[ "${SKIP_SAFETY}" != true ]]; then
  mkdir -p "${SAFETY_DIR}"
  if [[ -n "${POSTGRES_BACKUP}" ]]; then
    log "Snapshotting current PostgreSQL -> ${SAFETY_PG}"
    ${DOCKER_COMPOSE_CMD} exec -T postgres sh -lc \
      'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' \
      | gzip -c > "${SAFETY_PG}"
    assert_gzip_intact "${SAFETY_PG}" "safety snapshot (postgres)"
  fi
  if [[ -n "${MONGO_BACKUP}" ]]; then
    MONGO_DB="$(grep -E '^MONGODB_DATABASE=' .env.production | tail -n 1 | cut -d '=' -f 2-)"
    MONGO_DB="${MONGO_DB:-lexilingo}"
    log "Snapshotting current MongoDB -> ${SAFETY_MONGO}"
    ${DOCKER_COMPOSE_CMD} exec -T -e MONGO_DB="${MONGO_DB}" mongodb sh -lc \
      'mongodump --archive --gzip --db "$MONGO_DB"' > "${SAFETY_MONGO}"
    assert_gzip_intact "${SAFETY_MONGO}" "safety snapshot (mongo)"
  fi
else
  log "WARNING: safety snapshot skipped — this restore is NOT reversible"
fi

rollback_hint() {
  echo
  echo "=============================================================="
  echo "RESTORE FAILED. Current production may be partially written."
  if [[ "${SKIP_SAFETY}" != true ]]; then
    echo "Roll back to the pre-restore snapshot with:"
    [[ -n "${POSTGRES_BACKUP}" ]] && echo "  ./scripts/restore-prod.sh --postgres-backup ${SAFETY_PG} --skip-safety-dump"
    [[ -n "${MONGO_BACKUP}" ]] && echo "  ./scripts/restore-prod.sh --mongo-backup ${SAFETY_MONGO} --skip-safety-dump"
  else
    echo "No safety snapshot was taken (--skip-safety-dump)."
  fi
  echo "=============================================================="
}
trap 'rollback_hint' ERR

if [[ -n "${POSTGRES_BACKUP}" ]]; then
  log "Restoring PostgreSQL from ${POSTGRES_BACKUP}"
  ${DOCKER_COMPOSE_CMD} exec -T postgres sh -lc \
    'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"'
  gunzip -c "${POSTGRES_BACKUP}" | ${DOCKER_COMPOSE_CMD} exec -T postgres sh -lc \
    'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
  log "PostgreSQL restored"
fi

if [[ -n "${MONGO_BACKUP}" ]]; then
  log "Restoring MongoDB from ${MONGO_BACKUP}"
  ${DOCKER_COMPOSE_CMD} exec -T mongodb sh -lc 'mongorestore --archive --gzip --drop' < "${MONGO_BACKUP}"
  log "MongoDB restored"
fi

trap - ERR

if [[ "${SKIP_SAFETY}" != true ]]; then
  log "Pre-restore snapshot kept at ${SAFETY_DIR} — delete once the restore is confirmed good"
fi
log "Restore completed"
