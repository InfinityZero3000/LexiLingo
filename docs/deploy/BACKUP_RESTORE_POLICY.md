# Backup & Restore Policy (Production)

This policy standardizes backup/restore for PostgreSQL and MongoDB in production.

## Scope

- PostgreSQL (`postgres` service)
- MongoDB (`mongodb` service)
- Backup artifacts and retention
- Restore drill procedure

## Backup schedule

- Frequency: daily at 02:30 UTC
- Retention: 14 days (default, configurable)
- Location: `/opt/lexilingo/backups`

Systemd assets:
- `deploy/systemd/lexilingo-backup.service`
- `deploy/systemd/lexilingo-backup.timer`

Enable on server:

```bash
sudo cp deploy/systemd/lexilingo-backup.service /etc/systemd/system/
sudo cp deploy/systemd/lexilingo-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lexilingo-backup.timer
sudo systemctl status lexilingo-backup.timer
```

Run backup manually:

```bash
bash ./scripts/backup-prod.sh
```

## Backup format

- PostgreSQL: `postgres_<timestamp>.sql.gz`
- MongoDB: `mongodb_<timestamp>.archive.gz`
- Checksums: `manifest_<timestamp>.txt`

## Restore procedure

Restore is destructive and requires explicit confirmation.

```bash
# PostgreSQL only
bash ./scripts/restore-prod.sh --postgres-backup /opt/lexilingo/backups/postgres_<timestamp>.sql.gz

# MongoDB only
bash ./scripts/restore-prod.sh --mongo-backup /opt/lexilingo/backups/mongodb_<timestamp>.archive.gz

# Both
bash ./scripts/restore-prod.sh \
  --postgres-backup /opt/lexilingo/backups/postgres_<timestamp>.sql.gz \
  --mongo-backup /opt/lexilingo/backups/mongodb_<timestamp>.archive.gz
```

## Restore drill policy

- Run restore drill at least monthly on a staging environment.
- Verify:
  - Core auth flows
  - News/category APIs
  - AI GraphCAG health and chat endpoints
- Record drill result and timestamp in ops notes.

## Security notes

- Backup files may contain sensitive data.
- Restrict file permissions and transfer over secure channels only.
- Consider offsite encrypted copy (S3 + SSE or equivalent).
