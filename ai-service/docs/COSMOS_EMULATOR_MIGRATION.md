# Azure Cosmos DB Emulator Migration (Mongo API)

This guide migrates AI-service data from local MongoDB to Azure Cosmos DB Emulator (Mongo API) with a safe backup-first flow.

## 1. Prerequisites

- Azure Cosmos DB Emulator is running and Mongo API endpoint is reachable at `localhost:10255`
- MongoDB Database Tools installed: `mongodump`, `mongorestore`

## 2. Connection String

Use a Cosmos Emulator Mongo URI in `.env` / `.env.development`:

```env
MONGODB_URI=mongodb://localhost:<EMULATOR_KEY>@localhost:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&tlsAllowInvalidCertificates=true
MONGODB_DATABASE=lexilingo_dev
MONGODB_TLS_ALLOW_INVALID_CERTIFICATES=true
```

Notes:
- `tlsAllowInvalidCertificates=true` is required to avoid TLS errors with emulator self-signed certificates.
- Keep `retrywrites=false` for Cosmos Mongo API compatibility.

## 3. Backup + Restore Migration

Run:

```bash
cd ai-service
chmod +x scripts/migrate_mongo_to_cosmos_emulator.sh
OLD_MONGO_URI='mongodb://localhost:27017' \
OLD_DB_NAME='lexilingo_dev' \
COSMOS_MONGO_URI='mongodb://localhost:<EMULATOR_KEY>@localhost:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&tlsAllowInvalidCertificates=true' \
TARGET_DB_NAME='lexilingo_dev' \
./scripts/migrate_mongo_to_cosmos_emulator.sh
```

Backup files are created at:

- `ai-service/data/backups/mongo_pre_cosmos_YYYYMMDD_HHMMSS/`

## 4. Verify

After migration, start AI service and call health endpoint:

```bash
curl http://localhost:8001/api/v1/health
```

If Mongo section reports healthy and chat/session endpoints return data, migration is complete.
