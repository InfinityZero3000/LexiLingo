# Server handoff: system completion

This note records work that must be completed on the server. The local validation
stack is intentionally isolated and does not import benchmark datasets or
runtime databases.

## Before deployment

- Create production `.env` files from the secret manager. Never copy the local
  `.env` files from the validation worktree and never commit secrets.
- Confirm Docker Compose supports `!override` and `!reset` (Compose `>= 2.24.4`).
- Use the production Compose file, not `docker-compose.validation.yml`; the
  validation override binds localhost-only ports and disables Firebase mounts.
- Back up PostgreSQL, MongoDB, Redis, and any Kuzu projection before import or
  migration.

## Database and learner-state setup

1. Start PostgreSQL, Redis, Redis-AI, MongoDB, backend, and AI services.
2. On a brand-new PostgreSQL database, run the existing bootstrap flow:
   `backend-service/scripts/create_tables.py`, then `alembic stamp head`.
   `alembic upgrade head` alone is not a valid blank-database bootstrap because
   the current migration history assumes the core tables already exist.
3. On an existing database, run `alembic upgrade head` and verify exactly one
   Alembic head with `alembic current` and `alembic heads`.
4. Import learner-state data only from an approved, checksummed export. Validate
   row counts, duplicate event IDs, pending/retry/dead-letter counts, and
   PostgreSQL-to-Kuzu reconciliation before enabling traffic.
5. Run the learner-state replay/idempotency integration tests against the server
   PostgreSQL instance. Do not treat tests skipped by connectivity or sandbox
   errors as passed.

## AI model and cache preparation

- Provision the required provider credentials and quotas through the secret
  manager; do not use provider fallback in paper/benchmark runs.
- Warm the AI STT/model cache once during a controlled maintenance window. The
  current image stores approximately 223 MB under
  `/home/appuser/.cache`; persist this path if containers are recreated often.
- Verify MongoDB and Redis-AI health before sending learner traffic.
- Confirm logs do not contain bearer tokens, refresh tokens, passwords, raw
  answer payloads, or unnecessary user identifiers.

## Required server checks

Run from the repository root after services are healthy:

```bash
./scripts/validate_local_stack.sh
```

Then perform one authenticated learner request, one controlled cache miss and
repeat it as a cache hit. Record route, reason, latency type, cache layer, and
provider usage. Do not infer a cache hit from HTTP 200 alone.

## Benchmark import and execution

- Import only the clean DriftBench-v2 24-case result set first; keep legacy 122
  cases separate.
- Validate dataset hash, config hash, git commit, seed, raw-output checksum,
  and provider/model before accepting results.
- Run the daily manifest in order: HotpotQA 64, 2Wiki 64, Query Clusters 32,
  MuSiQue 500, DriftBench-240, baselines, then threshold sensitivity.
- A failed preflight blocks the next dataset. Missing metrics remain `Pending`;
  never fill them from old or partial output.
- Keep simulated route cost separate from wall-clock latency.

## Evidence to attach to the pull request

- `docker compose config` output and service health snapshot.
- Migration current/head output.
- Import checksums and reconciliation report.
- Learner-state replay test output.
- Cache miss/hit request evidence with redacted identifiers.
- Benchmark manifest, raw-output checksums, passed summaries, and failure logs.

The local validation files are test-only infrastructure. Production data import,
secret provisioning, model-cache persistence, and paid benchmark execution are
server-operator tasks and are intentionally not performed in the development
environment.
