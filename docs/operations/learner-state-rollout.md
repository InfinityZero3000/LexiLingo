# Learner-state production rollout

PostgreSQL is the source of truth for sparse per-user concept state. KuzuDB remains the shared concept-topology store and must never be opened concurrently by migration tooling.

## Data flow

Chat writes a deterministic observation batch to MongoDB `learner_observation_spool` before the non-streaming response or terminal SSE `done` marker. A lease worker forwards the same event IDs to the backend. PostgreSQL commits idempotent outbox rows before ACK; backend workers claim with `FOR UPDATE SKIP LOCKED` and atomically update concept state, learner epoch, and event status.

Delivered Mongo rows expire after 90 days. Pending/retry rows have no TTL. Applied PostgreSQL payloads are retained 90 days and minimal audit metadata 365 days; pending and dead-letter rows are never removed automatically.

## Modes

| Mode | Reads | Writes | Rollback |
|---|---|---|---|
| `off` | Kuzu | Kuzu | Baseline |
| `shadow` | Kuzu; compare PostgreSQL | PostgreSQL + Kuzu | Set `off` |
| `read` | PostgreSQL overlay | PostgreSQL + Kuzu | Set `shadow` |
| `primary` | PostgreSQL | PostgreSQL; best-effort Kuzu during window | Set `read` |
| `cleanup` | PostgreSQL | PostgreSQL only | Reverse-sync PostgreSQL to a Kuzu snapshot first |

Never downgrade or drop PostgreSQL tables during production rollback.

## Migration

1. Stop writes to a Kuzu copy and create a filesystem/volume snapshot.
2. Run `ai-service/scripts/export_kuzu_mastery.py` against that read-only snapshot.
3. Verify the JSONL SHA-256 against its manifest.
4. Run `backend-service/scripts/import_kuzu_mastery.py` without `--apply`; dry-run performs no database writes.
5. Run with `--apply`, a checkpoint path, bounded page size, and quarantine path.
6. Run `audit_learner_state_consistency.py`; reports contain only aggregate counts and salted hashes.

Late rollback after Kuzu dual-write ends requires `export_postgres_mastery_for_kuzu.py`, then `import_postgres_mastery_to_kuzu.py` against an offline copy of the current topology snapshot. Apply requires a checksum manifest and explicit `--confirm-offline-snapshot`; it fails if any Concept is missing or the applied count differs. Swap the snapshot only after checksum and sample audit pass.

## Promotion gates

- Shadow → read: ≥99% within tolerance, PostgreSQL batch-read p95 <40 ms, degraded reads <0.1%, no PII in telemetry.
- Read → primary: chat p95/p99 within SLO, no benchmark quality regression, normal-peak observation loss zero, injected-failure loss <0.01%, duplicate application zero, rollback drill passes.
- Primary → cleanup: one stable release with Kuzu writes disabled, no unexplained divergence, operations approval.

## Database envelope

Connection budget is `backend replicas × (pool_size + max_overflow) + admin reserve`. Do not increase pools without measuring this total. Partition observation events monthly only above 50 GB or sustained autovacuum/index pressure. Consider hash partitioning state by `user_id` only after indexed reads and replicas miss the SLO.

Introduce a durable broker only if loss exceeds 0.01% during expected outages, restarts regularly lose material state, or peak input cannot drain with 50% headroom.
