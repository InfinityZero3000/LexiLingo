#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

DOCKER_COMPOSE_CMD="sudo docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.production.yml"
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MONGO_DB="$(grep -E '^MONGODB_DATABASE=' .env.production | tail -n 1 | cut -d '=' -f 2-)"
MONGO_DB="${MONGO_DB:-lexilingo}"

mkdir -p "${BACKUP_DIR}"

PG_FILE="${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"
MONGO_FILE="${BACKUP_DIR}/mongodb_${TIMESTAMP}.archive.gz"
MANIFEST_FILE="${BACKUP_DIR}/manifest_${TIMESTAMP}.txt"

echo "[backup-prod] Creating PostgreSQL backup -> ${PG_FILE}"
${DOCKER_COMPOSE_CMD} exec -T postgres sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' | gzip -c > "${PG_FILE}"

echo "[backup-prod] Creating MongoDB backup (${MONGO_DB}) -> ${MONGO_FILE}"
${DOCKER_COMPOSE_CMD} exec -T -e MONGO_DB="${MONGO_DB}" mongodb sh -lc 'mongodump --archive --gzip --db "$MONGO_DB"' > "${MONGO_FILE}"

sha256sum "${PG_FILE}" "${MONGO_FILE}" > "${MANIFEST_FILE}"

echo "[backup-prod] Backup manifest -> ${MANIFEST_FILE}"

find "${BACKUP_DIR}" -type f -mtime +"${RETENTION_DAYS}" \( -name 'postgres_*.sql.gz' -o -name 'mongodb_*.archive.gz' -o -name 'manifest_*.txt' \) -delete

echo "[backup-prod] Done"
