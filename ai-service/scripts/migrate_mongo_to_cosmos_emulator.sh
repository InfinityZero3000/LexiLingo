#!/usr/bin/env bash
set -euo pipefail

# MongoDB -> Azure Cosmos DB Emulator (Mongo API) migration helper.
# Usage:
#   ./scripts/migrate_mongo_to_cosmos_emulator.sh
#   OLD_MONGO_URI='mongodb://localhost:27017' COSMOS_MONGO_URI='mongodb://localhost:<KEY>@localhost:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&tlsAllowInvalidCertificates=true' ./scripts/migrate_mongo_to_cosmos_emulator.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OLD_MONGO_URI="${OLD_MONGO_URI:-mongodb://localhost:27017}"
OLD_DB_NAME="${OLD_DB_NAME:-lexilingo_dev}"
COSMOS_MONGO_URI="${COSMOS_MONGO_URI:-${MONGODB_URI:-}}"
TARGET_DB_NAME="${TARGET_DB_NAME:-$OLD_DB_NAME}"

if [[ -z "$COSMOS_MONGO_URI" ]]; then
  echo "ERROR: COSMOS_MONGO_URI is empty. Provide Cosmos Emulator Mongo URI."
  exit 1
fi

if ! command -v mongodump >/dev/null 2>&1; then
  echo "ERROR: mongodump not found. Install MongoDB Database Tools first."
  exit 1
fi

if ! command -v mongorestore >/dev/null 2>&1; then
  echo "ERROR: mongorestore not found. Install MongoDB Database Tools first."
  exit 1
fi

# Ensure TLS self-signed cert handling is present for emulator URI.
if [[ "$COSMOS_MONGO_URI" != *"tlsAllowInvalidCertificates=true"* ]]; then
  if [[ "$COSMOS_MONGO_URI" == *"?"* ]]; then
    COSMOS_MONGO_URI="${COSMOS_MONGO_URI}&tlsAllowInvalidCertificates=true"
  else
    COSMOS_MONGO_URI="${COSMOS_MONGO_URI}?tlsAllowInvalidCertificates=true"
  fi
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="data/backups/mongo_pre_cosmos_${TS}"

mkdir -p "$BACKUP_DIR"

echo "[1/3] Backup Mongo source database: $OLD_DB_NAME"
mongodump \
  --uri "$OLD_MONGO_URI" \
  --db "$OLD_DB_NAME" \
  --out "$BACKUP_DIR"

echo "[2/3] Restore to Cosmos Emulator target database: $TARGET_DB_NAME"
mongorestore \
  --uri "$COSMOS_MONGO_URI" \
  --nsFrom "${OLD_DB_NAME}.*" \
  --nsTo "${TARGET_DB_NAME}.*" \
  --drop \
  "$BACKUP_DIR/$OLD_DB_NAME"

echo "[3/3] Migration completed"
echo "Backup folder: $BACKUP_DIR"
echo "Target DB: $TARGET_DB_NAME"
