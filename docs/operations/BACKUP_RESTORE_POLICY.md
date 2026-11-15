# Backup & Restore Policy (Production)

This policy standardizes backup/restore for PostgreSQL and MongoDB in production.

## Scope

- PostgreSQL (`postgres` service)
- MongoDB (`mongodb` service)
- Backup artifacts and retention
- Restore drill procedure

## Backup schedule

- Frequency: every 6 hours (00:30, 06:30, 12:30, 18:30 UTC) with a short random delay
- Status: each run writes `/var/lib/lexilingo/backup-last.json`; the weekly restore test writes `verify-last.json`. Both feed the Operations Center page in the admin dashboard.
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

## Copy on the developer's Mac (off-box)

The server keeps its dumps on the same disk as the databases, so a lost VPS would take both.
`scripts/pull-backups-to-mac.sh` copies them to `~/Backups/lexilingo` on the Mac:

- `db/`: every `postgres_*`, `mongodb_*` and `manifest_*` set, each checked against its sha256 manifest
  (verified sets are listed in `db/.verified`). Kept 60 days locally, never fewer than 20 sets.
- `files/media/`: uploaded media from `backend-service/data/media`. **Not in the server dumps at all.**
- `files/ai-service-data/`: `ai-service/data`, minus live lock/WAL files.
- Never `--delete`: whatever the server loses or prunes stays on the Mac.

Install once with `scripts/pull-backups-to-mac.sh --install` (LaunchAgent `me.lexilingo.backup-pull`,
runs 20 minutes after each server backup and on login; macOS runs a missed slot on wake).
Status in `~/Backups/lexilingo/LAST_RUN`, log in `~/Library/Logs/lexilingo-backup-pull.log`;
a failure or a server backup older than 8 hours raises a macOS notification.

Restore from the Mac copy by pushing a set back first, then using the normal restore procedure:

```bash
scp ~/Backups/lexilingo/db/postgres_<stamp>.sql.gz ovh-vps:/tmp/
ssh ovh-vps 'sudo lxc file push /tmp/postgres_<stamp>.sql.gz lexilingo/opt/lexilingo/backups/'
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
  - AI TRACECAG health and chat endpoints
- Record drill result and timestamp in ops notes.

## Security notes

- Backup files may contain sensitive data.
- Restrict file permissions and transfer over secure channels only.
- Consider offsite encrypted copy (S3 + SSE or equivalent).

## Khi chạy trong container LXD

Nếu LexiLingo chạy trong một container LXD dùng chung VPS (xem `MULTI_PROJECT_VPS.md`), backup và verify chạy bên trong container như bình thường. Snapshot LXD hằng đêm là lớp bảo vệ thứ hai nhưng nằm cùng đĩa với dữ liệu, nên vẫn phải bật bản sao ngoài máy.
