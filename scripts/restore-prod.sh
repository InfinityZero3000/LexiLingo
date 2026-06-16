#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

DOCKER_COMPOSE_CMD="sudo docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml"
POSTGRES_BACKUP=""
MONGO_BACKUP=""
FORCE=false

usage() {
  cat <<'EOF'
Usage: ./scripts/restore-prod.sh [options]

Options:
  --postgres-backup <file>   Restore PostgreSQL from .sql.gz backup
  --mongo-backup <file>      Restore MongoDB from .archive.gz backup
  --force                    Skip destructive action confirmation
  -h, --help                 Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --postgres-backup)
      POSTGRES_BACKUP="$2"
      shift 2
      ;;
    --mongo-backup)
      MONGO_BACKUP="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${POSTGRES_BACKUP}" && -z "${MONGO_BACKUP}" ]]; then
  echo "At least one backup file must be provided."
  usage
  exit 1
fi

if [[ -n "${POSTGRES_BACKUP}" && ! -f "${POSTGRES_BACKUP}" ]]; then
  echo "PostgreSQL backup not found: ${POSTGRES_BACKUP}"
  exit 1
fi

if [[ -n "${MONGO_BACKUP}" && ! -f "${MONGO_BACKUP}" ]]; then
  echo "MongoDB backup not found: ${MONGO_BACKUP}"
  exit 1
fi

if [[ "${FORCE}" != true ]]; then
  echo "WARNING: This will overwrite live production data."
  read -r -p "Type 'RESTORE NOW' to continue: " confirm
  if [[ "${confirm}" != "RESTORE NOW" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

if [[ -n "${POSTGRES_BACKUP}" ]]; then
  echo "[restore-prod] Restoring PostgreSQL from ${POSTGRES_BACKUP}"
  ${DOCKER_COMPOSE_CMD} exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"'
  gunzip -c "${POSTGRES_BACKUP}" | ${DOCKER_COMPOSE_CMD} exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
fi

if [[ -n "${MONGO_BACKUP}" ]]; then
  echo "[restore-prod] Restoring MongoDB from ${MONGO_BACKUP}"
  cat "${MONGO_BACKUP}" | ${DOCKER_COMPOSE_CMD} exec -T mongodb sh -lc 'mongorestore --archive --gzip --drop'
fi

echo "[restore-prod] Restore completed"
