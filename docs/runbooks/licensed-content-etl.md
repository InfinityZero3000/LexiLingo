# Licensed Content ETL — Operator Runbook

This runbook covers installation, activation, rollback, and day-to-day operations
for the Licensed Content ETL that supplies CEFR A1–C2 source snapshots to the
Content Agent.

---

## 1. Installation

### 1.1 Install dependencies

```bash
cd ai-service
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -c "import defusedxml, typer; from api.services.content_etl.cli import app"
```

### 1.2 Configure environment

Copy `.env.example` to `.env` and fill in the required values:

```bash
cp .env.example .env
```

Key variables for the ETL:

```
CONTENT_ETL_ENABLED=false          # Keep false until refs are pinned
CONTENT_ETL_STORAGE_ROOT=/data/content-etl
CONTENT_ETL_HTTP_TIMEOUT_SECONDS=60
CONTENT_ETL_MAX_DOWNLOAD_BYTES=1073741824   # 1 GB max per source
CONTENT_ETL_MAX_QUARANTINE_RATIO=0.02       # Abort if >2% rows quarantined
CONTENT_ETL_USER_AGENT=LexiLingo-ETL/1.0
CONTENT_ETL_OEWN_VERSION=2025
CONTENT_ETL_OEWN_SHA256=<expected-lowercase-sha256>
CONTENT_ETL_CMU_REF=<40-character-commit-sha>
CONTENT_ETL_CMU_SHA256=<expected-lowercase-sha256>
CONTENT_ETL_CEFR_J_REF=<40-character-commit-sha>
CONTENT_ETL_CEFR_J_PATH=cefrj-vocabulary-profile-1.5.csv
CONTENT_ETL_CEFR_J_SHA256=<expected-lowercase-sha256>
CONTENT_ETL_WIKIDATA_SNAPSHOT=     # Reserved; no automated adapter yet
CONTENT_ETL_TATOEBA_RELEASE=       # Optional; leave empty to disable
CONTENT_ETL_LIBRISPEECH_RELEASE=   # Optional; leave empty to disable
CONTENT_ETL_COMMON_VOICE_RELEASE=  # Optional; leave empty to disable
```

Obtain checksums through an audited operator process from the exact pinned
artifact. Never copy a checksum from a failed ETL run and treat that as
approval.

### 1.3 Sync core lexical sources

Run the configuration-only dry run first:

```bash
python -m api.services.content_etl.cli sync \
  --sources oewn,cmudict,cefr_j
```

Then write the immutable snapshots:

```bash
python -m api.services.content_etl.cli sync \
  --sources oewn,cmudict,cefr_j \
  --write
```

A successful write downloads the exact artifact, verifies its configured
checksum, validates every normalized record, publishes the manifest, and
atomically activates that version.

Wikidata, Tatoeba, LibriSpeech, and Common Voice are not accepted by the
automated sync command until a pinned adapter and license filter are
implemented. Do not replace this with generic web crawling.

### 1.4 List registered source policies

```bash
python -m api.services.content_etl.cli list
```

This lists registered source IDs, default enablement, and approved license IDs.
It does not prove that a snapshot is active.

To inspect an exact active snapshot, read the pointer and validate its manifest:

```bash
cat /data/content-etl/active/oewn.json
python -m api.services.content_etl.cli validate --source oewn --version 2025
```

The admin source catalog should expose the same `snapshot_id`,
`source_version`, `raw_checksum`, license, attribution, and record count.

### 1.5 Run database migration

```bash
cd ../backend-service
source venv/bin/activate
alembic upgrade head
```

### 1.6 Verify admin dashboard build

```bash
cd ../admin-service
pnpm install --frozen-lockfile
pnpm build:check
```

---

## 2. Production Activation Checklist

Complete every step in order. Do not set `CONTENT_AGENT_ENABLED=true` until
all gates pass.

1. **Pin all enabled source refs and checksums** — Set the OEWN version, CMU
   and CEFR-J commit SHAs, and all three expected SHA-256 values. Production
   validation rejects empty checksums and moving labels (`main`, `master`,
   `latest`).

2. **Back up PostgreSQL and the ETL storage root** — Take a point-in-time
   PostgreSQL snapshot and back up `/data/content-etl` before any new sync:
   ```bash
   pg_dump $DATABASE_URL > backup-$(date +%Y%m%d).sql
   tar -czf content-etl-$(date +%Y%m%d).tar.gz /data/content-etl
   ```

3. **Sync and inspect manifests** — Run the sync with `--write` and check
   each source manifest under `/data/content-etl/manifests/`. Confirm:
   - `status: approved`
   - `raw_sha256` matches the expected checksum
   - `counts.quarantined` is below the 2% threshold

4. **Inspect quarantine reports** — Review any quarantined rows:
   ```bash
   cat /data/content-etl/quarantine/<source>/<version>/errors.jsonl | head -20
   ```
   Fix the root cause or adjust thresholds before proceeding.

5. **Confirm active core snapshots** — A successful sync already activates
   the approved version. Use `activate` only for an explicit promotion or
   rollback:
   ```bash
   python -m api.services.content_etl.cli activate --source oewn --version 2025
   python -m api.services.content_etl.cli activate --source cmudict --version <ref>
   python -m api.services.content_etl.cli activate --source cefr_j --version <ref>
   ```
   `activate` rechecks the raw checksum, normalized count, manifest status,
   and refuses empty or rejected snapshots.

6. **Enable the content agent** — Set `CONTENT_AGENT_ENABLED=true` in the
   backend service environment and redeploy.

7. **Create a preview-only A1 smoke job** — In the admin dashboard, launch
   a Content Agent job with only A1 and active sources selected. The dashboard
   must show snapshot version, license, record count, and retrieval date.
   Wait for `preview_ready`.

8. **Verify the preview has zero blocking errors** — Inspect the validation
   report in the drawer. Apply only after the preview shows:
   - `blocking_errors: []`
   - Sensible vocabulary and exercise counts

9. **Keep large audio sources disabled** — Leave `CONTENT_ETL_TATOEBA_RELEASE`,
   `CONTENT_ETL_LIBRISPEECH_RELEASE`, and `CONTENT_ETL_COMMON_VOICE_RELEASE`
   empty until storage sizing and per-row license filter tests pass.

---

## 3. Rollback Procedure

### 3.1 Revert an active snapshot

If a newly activated snapshot causes issues, repoint `active/<source>.json` to
the previous approved version:

```bash
python -m api.services.content_etl.cli activate \
  --source oewn \
  --version <previous-approved-version>
```

This is atomic: the file is written to a temporary path and renamed. Existing
jobs that have already pinned a snapshot ID are unaffected — they continue
reading their pinned version.

### 3.2 Revert a sync that wrote bad normalized data

If normalized records are corrupt, do not edit or overwrite the snapshot.
Validation should fail:

```bash
python -m api.services.content_etl.cli validate --source oewn --version 2025
```

Pin a new source version or commit, obtain its expected checksum, and run a
new sync. Immutable source/version paths are never repaired in place.

### 3.3 Database apply rollback

Database apply is **transaction-based**: the entire apply either commits or
rolls back atomically. If an apply succeeds but the courses are incorrect:

- The affected courses are created with `is_published=False` (unpublished drafts).
- They can be deleted through the admin course management UI.
- Because vocabulary items are upserted idempotently, removing draft courses
  does not delete shared vocabulary already used by other courses.
- **Automatic destructive rollback is not supported.** Removing applied courses
  is an audited admin operation: navigate to the course in the admin dashboard,
  verify no learners are enrolled, then delete through the standard course delete
  flow.

### 3.4 Disable the content agent entirely

```bash
# Backend service .env
CONTENT_AGENT_ENABLED=false
```

Redeploy the backend service. In-flight jobs already running in Celery will
complete their current stage, then the queue will drain. No new jobs can be
created from the admin dashboard once the flag is false.

---

## 4. Day-to-Day Operations

### Inspect a specific snapshot

```bash
python -m api.services.content_etl.cli validate \
  --source oewn --version 2025
```

Prints the manifest, quarantine ratio, and a sample of quarantined rows.

### Re-sync after upstream release

1. Pin the new ref and expected checksum in `.env`.
2. Run the dry run, then sync with `--write`.
3. Inspect the manifest and quarantine report.
4. Run the activation checklist from step 5 onward.

### Monitor ETL disk usage

```bash
du -sh /data/content-etl/*/
```

The `tmp/` subdirectory should be empty outside of active syncs. Partial
downloads are cleaned up automatically on failure.

### Incident response

- **Checksum mismatch:** stop the sync. Verify the official release identity
  and checksum through the audited source process. Never update the configured
  checksum merely to match unexpected bytes.
- **License mismatch or expired review:** keep the source disabled, preserve
  the failed report, and require a new legal/license review before retrying.
- **Provenance or pin mismatch:** do not apply the preview. Cancel the job,
  verify the active pointer and manifest, then create a new job so it pins the
  intended snapshot.
- **Quarantine threshold exceeded:** inspect only hashes/error metadata in
  `quarantine/`; fix the adapter or source pin and publish a new version.
