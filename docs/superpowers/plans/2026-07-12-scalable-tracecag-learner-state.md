# Scalable TRACE-CAG Learner State Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move personalized learner state onto a sparse, durable, horizontally scalable data path while keeping TRACE-CAG chat responsive and preserving a shared, cacheable knowledge graph.

**Architecture:** KuzuDB remains the read-mostly shared concept-topology store; PostgreSQL becomes the sole durable source of truth for per-user concept state and idempotent learning events; Redis remains disposable bounded working memory. TRACE-CAG retrieves a bounded shared subgraph, batch-loads only the matching learner overlay, ranks candidates in memory, returns chat without waiting for durable state mutation, and applies observations through an idempotent bounded worker path with explicit fallback and rollout flags.

**Tech Stack:** FastAPI, Python 3.11+, SQLAlchemy async, Alembic, PostgreSQL 16, Redis 7, MongoDB 7, KuzuDB, pytest, httpx, Docker Compose.

---

## Scope, invariants, and success criteria

### In scope

- One canonical sparse `(user_id, concept_id)` learner-state model.
- Idempotent observation ingestion and deterministic mastery updates.
- Batch learner-state reads for TRACE-CAG candidate concepts only.
- Shared subgraph caching independent of user identity.
- Non-blocking online chat writes with bounded backpressure and retry semantics.
- Safe migration away from KuzuDB `User`/`Mastery` writes.
- Database indexes, retention guidance, observability, load tests, rollout, and rollback.

### Out of scope until measured thresholds justify them

- Kafka or another external event broker.
- Physical PostgreSQL sharding.
- Replacing KuzuDB with a distributed graph database.
- A data warehouse implementation; this plan defines the archive boundary only.
- Pre-creating state for every user/concept pair.

### Non-negotiable invariants

1. There is never more than one canonical learner-state row per `(user_id, concept_id)`.
2. The same observation `event_id` is applied at most once.
3. Chat remains available when learner state or Redis is unavailable; it falls back to CEFR priors and reports degraded telemetry.
4. Online retrieval cost is bounded by candidate count, not by a user's lifetime concept count.
5. Redis contains no irreplaceable state.
6. New KuzuDB user/mastery writes can be disabled without changing concept traversal.
7. No migration step requires downtime or an irreversible cutover.

### Initial service-level objectives

- TRACE-CAG non-streaming p95 excluding model generation: `< 250 ms`; p99 `< 500 ms`.
- Learner overlay batch read p95: `< 40 ms` for 60 concept IDs.
- Observation enqueue p95: `< 10 ms`; queue saturation must not block chat longer than 20 ms.
- Error rate caused by learner-state dependency: `< 0.1%`.
- Duplicate observation application: `0` in concurrency tests.
- Redis cache memory remains bounded by TTL/maximum cardinality policies.

## Target data flow

```text
Client request
  -> TRACE-CAG input/profile load (Redis, bounded timeout)
  -> seed detection
  -> shared subgraph cache (Redis) or KuzuDB traversal
  -> candidate concept IDs (bounded Top-K)
  -> learner-state batch read (PostgreSQL through backend internal API)
  -> in-memory overlay + ranking
  -> generate/stream response
  -> bounded observation dispatcher
       -> idempotent backend ingestion
       -> atomic learner-state UPSERT
       -> increment state_version/profile_epoch
       -> cache invalidation
```

## File map

### Backend service: durable learner state

- Create `backend-service/app/models/learner_state.py`: learner-state and idempotent observation models.
- Modify `backend-service/app/models/__init__.py`: register new models for Alembic metadata.
- Create `backend-service/alembic/versions/add_learner_concept_state.py`: additive tables and indexes.
- Create `backend-service/app/schemas/learner_state.py`: internal batch-read and observation contracts.
- Create `backend-service/app/services/learner_state.py`: deterministic update algorithm and repository operations.
- Create `backend-service/app/routes/learner_state.py`: authenticated internal endpoints.
- Modify `backend-service/app/main.py`: mount internal routes without exposing arbitrary cross-user reads publicly.
- Modify `backend-service/app/core/config.py` and `.env.example`: rollout flags, internal auth, and bounded limits.
- Create `backend-service/scripts/backfill_kuzu_mastery.py`: resumable, idempotent backfill.

### AI service: bounded online integration

- Create `ai-service/api/clients/learner_state_client.py`: pooled, timeout-bounded batch client with circuit breaker.
- Create `ai-service/api/services/learner_overlay.py`: CEFR prior, overlay merge, forgetting risk, and ranking features.
- Create `ai-service/api/services/learner_observation_dispatcher.py`: bounded queue, batching, retry, and shutdown drain.
- Modify `ai-service/api/services/trace_cag/state.py`: typed overlay/degraded metadata.
- Modify `ai-service/api/services/trace_cag/nodes_v2.py`: batch-load overlay after bounded KG expansion.
- Modify `ai-service/api/services/trace_cag/retrieve.py`: rank with overlay without loading all user mastery.
- Modify `ai-service/api/services/background_jobs_v3.py`: dispatch observations instead of KuzuDB mastery writes.
- Modify `ai-service/api/services/kg_service_v3.py`: feature-gate and deprecate `User`/`Mastery` mutation.
- Modify `ai-service/api/core/config.py` and `.env.example`: endpoints, timeouts, queue bounds, and rollout modes.
- Modify `ai-service/api/main.py`: dispatcher lifecycle startup/shutdown.

### Tests and operations

- Create `backend-service/tests/services/test_learner_state.py`.
- Create `backend-service/tests/integration/test_learner_state_routes.py`.
- Create `backend-service/tests/test_learner_state_migration.py`.
- Create `ai-service/tests/test_learner_state_client.py`.
- Create `ai-service/tests/test_learner_overlay.py`.
- Create `ai-service/tests/test_learner_observation_dispatcher.py`.
- Modify `ai-service/tests/trace_cag/test_pipeline_integration.py`.
- Create `ai-service/tests/load/locustfile_tracecag_learner_state.py`.
- Create `docs/operations/learner-state-rollout.md`.
- Modify `docs/ARCHITECTURE.md` after rollout behavior is verified.

---

## Chunk 1: Durable sparse learner state

### Task 1: Add canonical learner-state and observation schema

**Files:**
- Create: `backend-service/app/models/learner_state.py`
- Modify: `backend-service/app/models/__init__.py`
- Create: `backend-service/alembic/versions/add_learner_concept_state.py`
- Test: `backend-service/tests/test_learner_state_migration.py`

- [ ] **Step 1: Inspect the current Alembic heads and model conventions**

Run:

```bash
cd backend-service
alembic heads
```

Expected: one head, or document/merge multiple existing heads before assigning `down_revision`. Do not guess a revision ID.

- [ ] **Step 2: Write the failing migration/model test**

Test that metadata contains both tables, the composite uniqueness constraint, and the required indexes:

```python
def test_learner_state_schema_is_sparse_and_idempotent():
    state = Base.metadata.tables["learner_concept_states"]
    events = Base.metadata.tables["learner_observation_events"]
    assert {"user_id", "concept_id", "mastery_probability", "state_version"} <= set(state.c)
    assert any(set(c.columns.keys()) == {"user_id", "concept_id"} for c in state.constraints)
    assert events.c.event_id.unique is True
```

- [ ] **Step 3: Run the focused test and confirm failure**

Run: `pytest tests/test_learner_state_migration.py -q`

Expected: FAIL because the models/tables do not exist.

- [ ] **Step 4: Implement focused SQLAlchemy models**

Use UUID user IDs consistent with the existing `users.id`; keep `concept_id` as bounded `String(255)` because it refers to shared Kuzu concept IDs rather than a PostgreSQL foreign key.

```python
class LearnerConceptState(Base):
    __tablename__ = "learner_concept_states"
    id = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id = mapped_column(GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    concept_id = mapped_column(String(255), nullable=False)
    mastery_probability = mapped_column(Float, nullable=False, default=0.5)
    stability_days = mapped_column(Float, nullable=False, default=1.0)
    difficulty = mapped_column(Float, nullable=False, default=0.5)
    attempt_count = mapped_column(Integer, nullable=False, default=0)
    correct_count = mapped_column(Integer, nullable=False, default=0)
    error_count = mapped_column(Integer, nullable=False, default=0)
    last_interacted_at = mapped_column(TZDateTime, nullable=True)
    next_review_at = mapped_column(TZDateTime, nullable=True)
    state_version = mapped_column(Integer, nullable=False, default=1)
    algorithm_version = mapped_column(String(32), nullable=False, default="bkt-fsrs-v1")
    created_at = mapped_column(TZDateTime, nullable=False, default=utc_now)
    updated_at = mapped_column(TZDateTime, nullable=False, default=utc_now, onupdate=utc_now)
```

`LearnerObservationEvent` must contain `event_id`, `user_id`, `session_id`, `concept_id`, `outcome`, `confidence`, `observed_at`, `payload`, `applied_at`, and `created_at`. Make `event_id` globally unique.

- [ ] **Step 5: Add additive Alembic migration**

Create:

```sql
UNIQUE (user_id, concept_id)
INDEX ix_learner_state_user_due (user_id, next_review_at)
INDEX ix_learner_state_user_mastery (user_id, mastery_probability)
INDEX ix_learner_state_user_updated (user_id, updated_at)
UNIQUE INDEX ux_learner_observation_event_id (event_id)
INDEX ix_learner_observation_created (created_at)
```

Do not add a foreign key from `concept_id` to vocabulary tables; KuzuDB concept identity is independent.

- [ ] **Step 6: Verify upgrade and downgrade on an empty test database**

Run:

```bash
alembic upgrade head
alembic downgrade -1
alembic upgrade head
pytest tests/test_learner_state_migration.py -q
```

Expected: all commands succeed and the focused test passes.

- [ ] **Step 7: Commit the additive schema**

```bash
git add backend-service/app/models/learner_state.py backend-service/app/models/__init__.py backend-service/alembic/versions backend-service/tests/test_learner_state_migration.py
git commit -m "feat(learning): add sparse learner concept state schema"
```

### Task 2: Implement deterministic, confidence-aware state updates

**Files:**
- Create: `backend-service/app/services/learner_state.py`
- Create: `backend-service/app/schemas/learner_state.py`
- Test: `backend-service/tests/services/test_learner_state.py`

- [ ] **Step 1: Write pure-algorithm failing tests**

Cover clamping, confidence, elapsed-time decay, correct/error direction, stability, and deterministic output:

```python
def test_low_confidence_evidence_moves_mastery_less():
    low = evolve_state(prior(), outcome="incorrect", confidence=0.2, now=NOW)
    high = evolve_state(prior(), outcome="incorrect", confidence=0.9, now=NOW)
    assert abs(low.mastery_probability - 0.5) < abs(high.mastery_probability - 0.5)

def test_mastery_is_always_bounded():
    assert 0.01 <= evolve_state(extreme(), "correct", 1.0, NOW).mastery_probability <= 0.99
```

- [ ] **Step 2: Run tests and confirm failure**

Run: `pytest tests/services/test_learner_state.py -q`

Expected: FAIL because `evolve_state` is missing.

- [ ] **Step 3: Implement a documented BKT/FSRS-inspired v1 update**

Use a pure function first. The intended equations are:

```python
elapsed_days = max(0.0, (now - last_interacted_at).total_seconds() / 86400)
retention = exp(-elapsed_days / max(stability_days, 0.25))
decayed = clamp(0.01, 0.99, prior_mastery * retention)
evidence = confidence * (1.0 - 0.35 * difficulty)
target = 1.0 if outcome == "correct" else 0.0
posterior = clamp(0.01, 0.99, decayed + evidence * LEARNING_RATE * (target - decayed))
```

Update stability upward after correct evidence and downward after an error; compute `next_review_at` from target retention without importing a second scheduling dependency. Store `algorithm_version="bkt-fsrs-v1"`. Constants must live together and have boundary tests.

- [ ] **Step 4: Implement atomic idempotent application**

In one transaction:

1. Insert observation with `event_id`; on conflict, return `duplicate=True` without changing state.
2. Lock existing `(user_id, concept_id)` row with `SELECT ... FOR UPDATE`, or create it using PostgreSQL `INSERT ... ON CONFLICT DO NOTHING` then lock.
3. Apply the pure update.
4. Increment `state_version` exactly once.
5. Set `applied_at` and commit.

SQLite tests may use a repository fallback, but PostgreSQL integration tests must exercise real conflict behavior.

- [ ] **Step 5: Add bounded batch read**

```python
async def get_states_for_concepts(session, user_id, concept_ids, limit=100):
    ids = list(dict.fromkeys(concept_ids))
    if len(ids) > limit:
        raise TooManyConceptsError(limit)
    # one SELECT WHERE user_id=:uid AND concept_id IN (...)
```

Return only persisted rows. The AI service supplies CEFR priors for missing concepts, preserving sparse storage.

- [ ] **Step 6: Add concurrency and query-count tests**

Verify 20 concurrent calls with the same `event_id` produce one event and one state increment. Verify a 60-concept batch performs one state query, not N queries.

- [ ] **Step 7: Run focused tests**

Run: `pytest tests/services/test_learner_state.py -q`

Expected: PASS.

- [ ] **Step 8: Commit service and schemas**

```bash
git add backend-service/app/services/learner_state.py backend-service/app/schemas/learner_state.py backend-service/tests/services/test_learner_state.py
git commit -m "feat(learning): add idempotent mastery state engine"
```

### Task 3: Expose a protected internal learner-state API

**Files:**
- Create: `backend-service/app/routes/learner_state.py`
- Modify: `backend-service/app/core/config.py`
- Modify: `backend-service/.env.example`
- Modify: `backend-service/app/main.py`
- Test: `backend-service/tests/integration/test_learner_state_routes.py`

- [ ] **Step 1: Write failing authorization and contract tests**

Cover missing/invalid internal token, batch limit, unknown concepts, duplicate observation, malformed UUID, confidence outside `[0,1]`, and cross-user access rejection.

- [ ] **Step 2: Confirm tests fail**

Run: `pytest tests/integration/test_learner_state_routes.py -q`

Expected: FAIL with route not found.

- [ ] **Step 3: Add internal-only contracts**

```text
POST /api/v1/internal/learner-state/batch-get
POST /api/v1/internal/learner-state/observations:batch
```

Batch-get request contains one `user_id` and at most `LEARNER_STATE_MAX_BATCH_CONCEPTS` concept IDs. Observation batches default to at most 100 events. Authenticate using a dedicated internal service token compared with `secrets.compare_digest`; never accept caller-provided administrative user identity without service authentication.

- [ ] **Step 4: Add safe configuration**

```text
LEARNER_STATE_ENABLED=false
LEARNER_STATE_INTERNAL_TOKEN=<required in production when enabled>
LEARNER_STATE_MAX_BATCH_CONCEPTS=100
LEARNER_STATE_MAX_OBSERVATION_BATCH=100
```

Production startup must fail if the feature is enabled without a token. Never log the token or full learner payload.

- [ ] **Step 5: Implement routes as thin service adapters**

Map domain errors to `400/409/422/503`, return duplicate status as a successful idempotent result, and avoid returning observation payloads.

- [ ] **Step 6: Run security and route tests**

Run:

```bash
pytest tests/integration/test_learner_state_routes.py tests/test_security_hardening.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit protected API**

```bash
git add backend-service/app/routes/learner_state.py backend-service/app/main.py backend-service/app/core/config.py backend-service/.env.example backend-service/tests/integration/test_learner_state_routes.py
git commit -m "feat(api): expose protected learner state ingestion"
```

---

## Chunk 2: TRACE-CAG online integration

### Task 4: Add a resilient learner-state client and overlay algorithm

**Files:**
- Create: `ai-service/api/clients/learner_state_client.py`
- Create: `ai-service/api/services/learner_overlay.py`
- Modify: `ai-service/api/core/config.py`
- Modify: `ai-service/.env.example`
- Test: `ai-service/tests/test_learner_state_client.py`
- Test: `ai-service/tests/test_learner_overlay.py`

- [ ] **Step 1: Write failing client tests**

Test one HTTP request per batch, 40 ms default timeout, no retry for validation/auth errors, one jittered retry only for safe batch reads, circuit opening after repeated transport failures, and no user data in logs.

- [ ] **Step 2: Write failing overlay tests**

Test missing rows receive CEFR/difficulty priors without persistence, ordering combines retrieval relevance and learning need, and candidate count is capped.

- [ ] **Step 3: Confirm tests fail**

Run: `pytest tests/test_learner_state_client.py tests/test_learner_overlay.py -q`

Expected: FAIL because modules are missing.

- [ ] **Step 4: Implement the pooled client**

Reuse a single `httpx.AsyncClient`. Configuration:

```text
LEARNER_STATE_MODE=off        # off | shadow | read | primary
LEARNER_STATE_API_URL=http://backend-service:8000/api/v1/internal
LEARNER_STATE_INTERNAL_TOKEN=
LEARNER_STATE_READ_TIMEOUT_MS=40
LEARNER_STATE_CONNECT_TIMEOUT_MS=20
LEARNER_STATE_CIRCUIT_FAILURES=5
LEARNER_STATE_CIRCUIT_RESET_SECONDS=30
```

Return a typed degraded result rather than throwing into the chat pipeline on timeout/open circuit.

- [ ] **Step 5: Implement bounded overlay scoring**

For each candidate, calculate:

```python
learning_need = 1.0 - effective_mastery
forgetting_risk = 1.0 - exp(-elapsed_days / max(stability_days, 0.25))
prerequisite_penalty = 1.0 - prerequisite_readiness
score = (
    0.50 * retrieval_relevance
    + 0.25 * learning_need
    + 0.15 * forgetting_risk
    + 0.10 * recent_error_signal
    - 0.20 * prerequisite_penalty
)
```

Weights are configuration constants with tests; do not introduce an online ML dependency. Clamp all features to `[0,1]` and apply stable tie-breaking by original retrieval order and concept ID.

- [ ] **Step 6: Run focused tests**

Run: `pytest tests/test_learner_state_client.py tests/test_learner_overlay.py -q`

Expected: PASS.

- [ ] **Step 7: Commit client and overlay**

```bash
git add ai-service/api/clients/learner_state_client.py ai-service/api/services/learner_overlay.py ai-service/api/core/config.py ai-service/.env.example ai-service/tests/test_learner_state_client.py ai-service/tests/test_learner_overlay.py
git commit -m "feat(tracecag): add bounded learner state overlay"
```

### Task 5: Integrate sparse overlay into TRACE-CAG retrieval

**Implementation status (2026-07-13):** Core implementation and focused regression
suite complete; final code review approved. `test_pipeline_integration.py` collects
successfully but its first live pipeline test still hangs beyond 30 seconds, so the
full-suite gate remains open and is carried into Task 6.

**Files:**
- Modify: `ai-service/api/services/trace_cag/state.py`
- Modify: `ai-service/api/services/trace_cag/nodes_v2.py`
- Modify: `ai-service/api/services/trace_cag/retrieve.py`
- Modify: `ai-service/api/services/trace_cag/cache_utils.py`
- Test: `ai-service/tests/trace_cag/test_pipeline_integration.py`
- Test: `ai-service/tests/trace_cag/test_cache_gate_l1.py`

- [ ] **Step 1: Write failing pipeline tests**

Test:

- only expanded candidate IDs are batch-read;
- no full-user mastery read occurs;
- state timeout still yields a response with `learner_state_degraded=true`;
- two users sharing seeds reuse the same topology cache but receive different rankings;
- a changed `state_version/profile_epoch` prevents unsafe personalized response reuse.

- [ ] **Step 2: Confirm tests fail**

Run:

```bash
pytest tests/trace_cag/test_pipeline_integration.py tests/trace_cag/test_cache_gate_l1.py -q
```

Expected: at least the new assertions fail.

- [ ] **Step 3: Extend typed pipeline state minimally**

Add `learner_concept_states`, `learner_state_version`, `learner_state_degraded`, and `learner_state_latency_ms`. Do not place unbounded history in state.

- [ ] **Step 4: Batch-fetch after KG expansion**

Deduplicate candidate IDs and cap at 60 before calling the state service. Execute independent retrieval inputs concurrently only when it does not extend the critical path beyond the configured deadline.

- [ ] **Step 5: Merge overlay during ranking**

Keep topology cache user-agnostic. Never write personalized mastery into `kg:subgraph:*`. Rank from shared candidate data plus request-local overlay.

- [ ] **Step 6: Version personalized cache entries**

Include compact `state_version/profile_epoch`, CEFR level, intent, and concept scope in the PCC compatibility gate. Do not include raw user ID in a shared topology cache. Personalized answers must either be user-scoped or proven PCC-compatible.

- [ ] **Step 7: Run TRACE-CAG regression suite**

Run:

```bash
pytest tests/trace_cag/test_pipeline_integration.py tests/trace_cag/test_cache_gate_l1.py tests/trace_cag/test_generate_node.py -q
```

Expected: PASS with no network access.

- [ ] **Step 8: Commit online read integration**

```bash
git add ai-service/api/services/trace_cag ai-service/tests/trace_cag
git commit -m "feat(tracecag): personalize bounded candidate subgraphs"
```

### Task 6: Move learner observations off the chat critical path

**Implementation status (2026-07-13):** In progress. Follow the authoritative
durable Mongo spool + PostgreSQL outbox corrections below instead of the original
in-process-only dispatcher design.

**Updated status:** Implementation, focused tests, security review and code review
complete. Real PostgreSQL multi-worker execution remains part of Task 9's environment gate.

**Files:**
- Create: `ai-service/api/services/learner_observation_dispatcher.py`
- Modify: `ai-service/api/services/background_jobs_v3.py`
- Modify: `ai-service/api/services/kg_service_v3.py`
- Modify: `ai-service/api/main.py`
- Test: `ai-service/tests/test_learner_observation_dispatcher.py`
- Modify: `ai-service/tests/trace_cag/test_pipeline_integration.py`

- [ ] **Step 1: Write failing dispatcher tests**

Cover deterministic event IDs, queue capacity, batch flush by size/time, retry with bounded exponential backoff, shutdown drain, duplicate safety, and saturation behavior.

- [ ] **Step 2: Confirm tests fail**

Run: `pytest tests/test_learner_observation_dispatcher.py -q`

Expected: FAIL because dispatcher does not exist.

- [ ] **Step 3: Implement deterministic observation identity**

```python
event_id = sha256(
    f"{user_id}|{session_id}|{turn_id}|{concept_id}|{observation_kind}".encode()
).hexdigest()
```

Require stable `turn_id`; do not use the current timestamp as identity.

- [ ] **Step 4: Implement a bounded in-process dispatcher**

Defaults:

```text
LEARNER_OBSERVATION_QUEUE_SIZE=5000
LEARNER_OBSERVATION_BATCH_SIZE=100
LEARNER_OBSERVATION_FLUSH_MS=100
LEARNER_OBSERVATION_MAX_RETRIES=3
```

On saturation, wait no longer than 20 ms, increment a dropped/deferred metric, persist the interaction through the existing Mongo audit path when available, and never block the response indefinitely. This is an interim production-safe boundary; introduce a durable broker only when dropped observations exceed the rollout threshold.

- [ ] **Step 5: Register application lifecycle hooks**

Start one dispatcher per process and drain it with a bounded shutdown deadline. Ensure reload/test startup does not create duplicate workers.

- [ ] **Step 6: Stop KuzuDB mastery writes behind a feature flag**

Add `KUZU_USER_MASTERY_WRITES_ENABLED=true` initially. In shadow/read rollout, compare PostgreSQL and Kuzu results. After acceptance, set false; retain read-only compatibility for one release before removing the schema.

- [ ] **Step 7: Run dispatcher and pipeline tests**

Run:

```bash
pytest tests/test_learner_observation_dispatcher.py tests/trace_cag/test_pipeline_integration.py -q
```

Expected: PASS; a simulated slow backend does not delay chat beyond the bounded enqueue deadline.

- [ ] **Step 8: Commit non-blocking writes**

```bash
git add ai-service/api/services/learner_observation_dispatcher.py ai-service/api/services/background_jobs_v3.py ai-service/api/services/kg_service_v3.py ai-service/api/main.py ai-service/tests
git commit -m "feat(tracecag): dispatch learner observations asynchronously"
```

---

## Chunk 3: Migration, operations, and scale validation

### Task 7: Build resumable Kuzu mastery backfill and consistency audit

**Implementation status (2026-07-13):** Complete under the authoritative safe
snapshot correction: versioned export/manifest, resumable import/checkpoint,
quarantine, deterministic migration events, epoch updates, consistency audit and
offline reverse-sync tooling are implemented and focused tests pass.

**Files:**
- Create: `backend-service/scripts/backfill_kuzu_mastery.py`
- Create: `backend-service/tests/test_backfill_kuzu_mastery.py`
- Create: `docs/operations/learner-state-rollout.md`

- [ ] **Step 1: Write failing transformation/idempotency tests**

Use fixture Kuzu rows and verify stable event IDs, restart checkpoints, dry-run behavior, invalid row quarantine, and rerun idempotency.

- [ ] **Step 2: Confirm tests fail**

Run: `pytest tests/test_backfill_kuzu_mastery.py -q`

Expected: FAIL because script is missing.

- [ ] **Step 3: Implement a resumable backfill**

Requirements:

- `--dry-run` is default unless `--apply` is supplied.
- Read in bounded pages; never load all users/mastery edges into memory.
- UPSERT `(user_id, concept_id)` without overwriting a newer PostgreSQL state.
- Persist a checkpoint after each committed page.
- Emit counts only: scanned, inserted, skipped-newer, invalid, failed.
- Generate deterministic synthetic migration event IDs.

- [ ] **Step 4: Add a sampling consistency command**

Compare sampled Kuzu scores to PostgreSQL mastery with configured tolerance. Report aggregates and hashed identifiers, not raw user IDs.

- [ ] **Step 5: Document rollout stages and rollback**

```text
0. off: schema deployed, no traffic
1. shadow: read PostgreSQL and compare, Kuzu remains authoritative
2. read: PostgreSQL overlay affects ranking, Kuzu writes continue
3. primary: PostgreSQL authoritative, Kuzu writes disabled
4. cleanup: remove Kuzu User/Mastery after one stable release
```

Rollback at stages 1–3 is changing `LEARNER_STATE_MODE` to the previous mode; never drop tables during rollback.

- [ ] **Step 6: Run tests and dry-run backfill**

Run:

```bash
pytest tests/test_backfill_kuzu_mastery.py -q
python scripts/backfill_kuzu_mastery.py --dry-run --page-size 500
```

Expected: PASS; dry-run reports counts and performs zero writes.

- [ ] **Step 7: Commit migration tooling**

```bash
git add backend-service/scripts/backfill_kuzu_mastery.py backend-service/tests/test_backfill_kuzu_mastery.py docs/operations/learner-state-rollout.md
git commit -m "chore(learning): add resumable mastery backfill"
```

### Task 8: Add observability, retention, and database safeguards

**Implementation status (2026-07-13):** Complete in code and focused verification.
Operational metric baselines remain intentionally unmeasured until Task 9 load execution.

**Files:**
- Modify: `backend-service/app/services/learner_state.py`
- Modify: `ai-service/api/clients/learner_state_client.py`
- Modify: `ai-service/api/services/learner_observation_dispatcher.py`
- Modify: `ai-service/scripts/init_db.py`
- Modify: `docs/operations/learner-state-rollout.md`
- Test: relevant focused test modules from Tasks 2, 4, and 6

- [ ] **Step 1: Add failing metric/logging tests**

Verify structured telemetry contains latency, mode, candidate count, cache/degraded result, queue depth, duplicate count, and update result but excludes input text, tokens, and raw user IDs.

- [ ] **Step 2: Add operational metrics**

At minimum:

```text
learner_state_batch_read_seconds
learner_state_batch_size
learner_state_degraded_total{reason}
learner_observation_queue_depth
learner_observation_dropped_total
learner_observation_duplicate_total
learner_state_update_conflict_total
tracecag_shared_subgraph_cache_hit_total
tracecag_personalized_cache_decision_total{decision}
```

- [ ] **Step 3: Protect PostgreSQL workload**

Set statement timeout for internal learner-state operations, cap batch sizes, use one batch query, and verify pool settings match expected AI replica concurrency. Do not increase pool sizes blindly; document the connection budget:

```text
total connections = backend replicas * pool_size + overflow + admin reserve
```

- [ ] **Step 4: Correct Mongo TTL/index initialization**

Ensure duplicate indexes are not created for the same timestamp field and TTL fields are actual BSON datetimes. Define which raw events expire at 30/90 days and which aggregate snapshots remain. Add an archive hook specification before shortening any existing retention.

- [ ] **Step 5: Define partition thresholds instead of premature partitioning**

Partition `learner_observation_events` monthly when either table size exceeds 50 GB or sustained writes exceed the measured autovacuum/index-maintenance envelope. Consider hash partitioning `learner_concept_states` by `user_id` only after a single primary cannot meet the batch-read SLO with indexes and read replicas.

- [ ] **Step 6: Run focused tests**

Run:

```bash
cd backend-service && pytest tests/services/test_learner_state.py -q
cd ../ai-service && pytest tests/test_learner_state_client.py tests/test_learner_observation_dispatcher.py -q
```

Expected: PASS and telemetry tests confirm no PII leakage.

- [ ] **Step 7: Commit safeguards**

```bash
git add backend-service/app/services/learner_state.py ai-service/api/clients/learner_state_client.py ai-service/api/services/learner_observation_dispatcher.py ai-service/scripts/init_db.py docs/operations/learner-state-rollout.md
git commit -m "chore(observability): instrument learner state data flow"
```

### Task 9: Validate concurrency, latency, degradation, and rollback

**Implementation status (2026-07-13):** Test/load artifacts, hermetic regression
suite, runbook and validation report are complete. Live PostgreSQL two-worker
concurrency and lease replay pass. The authenticated Locust probe fixed two
harness defects (JWT/user mismatch and missing session), but staged load and the
rollback drill remain blocked by invalid/quota-exhausted upstream model
credentials. A local Qwen fallback was also measured, but failed the one-user
latency/isolation gate, so larger runs would not be representative. Fresh database
bootstrap and learner-state migration round-trip pass on PostgreSQL 16. The chat
API now has a 30-second primary plus 15-second retry deadline, eliminating the
unbounded request found by the live probe. Production promotion remains blocked
only on production-equivalent staged load/rollback evidence; see the validation
report for exact measurements.

**Files:**
- Create: `ai-service/tests/load/locustfile_tracecag_learner_state.py`
- Create: `ai-service/tests/load/README.md`
- Modify: `docker-compose.dev.yml`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/operations/learner-state-rollout.md`

- [ ] **Step 1: Create a reproducible load profile**

Model at least:

- 70% repeated-topic chat (shared subgraph cache opportunity),
- 20% new-topic chat,
- 10% review/incorrect-answer bursts,
- 1,000 simulated users with distinct learner overlays,
- hot users and long-tail users,
- Redis unavailable, backend state timeout, and dispatcher saturation scenarios.

- [ ] **Step 2: Add correctness assertions to load output**

Track p50/p95/p99, error rate, degraded rate, cache hit rate, queue depth/drops, PostgreSQL connections, duplicate events, and state divergence. A fast response with incorrect cross-user personalization is a failure.

- [x] **Step 3: Run all affected automated tests**

Run:

```bash
cd backend-service
pytest tests/services/test_learner_state.py tests/integration/test_learner_state_routes.py tests/test_learner_state_migration.py tests/test_backfill_kuzu_mastery.py -q
cd ../ai-service
pytest tests/test_learner_state_client.py tests/test_learner_overlay.py tests/test_learner_observation_dispatcher.py tests/trace_cag/test_pipeline_integration.py tests/trace_cag/test_cache_gate_l1.py -q
```

Expected: PASS.

- [x] **Step 4: Run backend migration and static checks**

Run the repository's configured lint/type checks discovered from `pyproject.toml`, then:

```bash
cd backend-service
alembic upgrade head
pytest -q
```

Expected: migration succeeds; full backend suite passes or all unrelated pre-existing failures are documented with evidence.

- [ ] **Step 5: Run staged load tests** *(one-user gate attempted and failed on
  the local inference stack; 100/1,000-user promotion runs are intentionally not
  misreported—see validation report)*

Example after starting the dev stack:

```bash
cd ai-service
locust -f tests/load/locustfile_tracecag_learner_state.py --headless -u 100 -r 10 -t 5m
locust -f tests/load/locustfile_tracecag_learner_state.py --headless -u 1000 -r 50 -t 15m
```

Expected: initial SLOs pass; zero cross-user leakage; zero duplicate updates; no unbounded queue or connection growth.

- [ ] **Step 6: Execute a rollback drill**

While load is active, change `primary -> read -> off` and confirm chat remains available, topology retrieval remains correct, and the additive PostgreSQL data remains intact.

- [ ] **Step 7: Update architecture documentation with measured results**

Replace aspirational numbers with measured p95/p99, maximum safe concurrency, database connection budget, cache hit rate, and the broker/sharding trigger thresholds.

- [x] **Step 8: Run required final reviews**

Because this touches an internal API, DB migration, config, and authentication:

- Dispatch `test-writer` after each implemented feature chunk.
- Dispatch `security-reviewer` for internal token handling, routes, migrations, and environment variables.
- Dispatch `code-reviewer` after tests pass and before any PR.
- Rebuild the code-review graph and inspect affected flows/impact radius.

- [ ] **Step 9: Commit validation artifacts**

```bash
git add ai-service/tests/load docker-compose.dev.yml docs/ARCHITECTURE.md docs/operations/learner-state-rollout.md
git commit -m "test(tracecag): validate learner state at concurrent load"
```

---

## Production rollout gates

## Mandatory review corrections before implementation

This section is authoritative where it tightens or replaces an earlier task description.

### Durable ingestion, epoch, and concurrency

- Use a two-hop durable handoff. Before returning the final non-streaming response (or final streaming completion event), the AI service inserts each deterministic observation into MongoDB collection `learner_observation_spool` with unique `event_id`, `status=pending`, and majority-acknowledged/bounded write concern. This bounded spool commit has a separate 20 ms target budget and is the only learner-state durability work on the response boundary; PostgreSQL state application never blocks chat. A spool worker forwards events to the backend ingestion endpoint, which commits its PostgreSQL outbox before ACK. On backend ACK, mark the Mongo spool row delivered. If the bounded Mongo commit fails, return chat normally with `observation_durability_degraded=true`, emit a critical metric, and rely on the already durable `ai_interactions` record reconciler; this explicitly measured rare-loss path must remain below the rollout gate.
- Add `ai-service/api/services/learner_observation_spool.py`, lifecycle wiring in `ai-service/api/main.py`, indexes `{event_id: 1 unique}`, `{status: 1, available_at: 1}`, and a TTL on `delivered_at` only. Pending rows never expire. Use the same `event_id` across Mongo spool and PostgreSQL outbox.
- Test the cross-service boundary at: crash before forward, crash after send/before ACK, backend commit followed by lost ACK, and AI restart. Every case must replay idempotently and apply state once. Streaming must emit the answer without waiting for state application, but must attempt the bounded spool commit before sending the terminal completion marker.
- Add `learner_state_profiles(user_id PRIMARY KEY, state_epoch, updated_at)`. Increment `state_epoch` in the same transaction that applies any concept observation. TRACE-CAG uses this scalar epoch for personalized cache versioning; per-concept `state_version` is not a global cache epoch.
- Treat `learner_observation_events` as a PostgreSQL transactional outbox with `status`, `attempt_count`, `available_at`, `claimed_at`, `applied_at`, and `last_error_code`. The ingestion endpoint acknowledges only after this row commits.
- Replace the in-process-only dispatcher in Task 6 with `backend-service/app/services/learner_state_outbox.py`. Workers claim ordered rows with `FOR UPDATE SKIP LOCKED`, use expiring leases, and atomically update concept state, per-user epoch, and event status.
- Sort a claimed batch by `(user_id, concept_id, event_id)`. Create state with `INSERT ... ON CONFLICT DO NOTHING`, then lock it. Retry serialization/deadlock failures with bounded jitter. Tests must cover duplicate event IDs, distinct concurrent events for one concept, crash-before-apply, restart replay, and rolling deployment.
- Mongo spool is the authoritative AI-to-backend handoff; `ai_interactions` replay is the last-resort reconciler. A durable broker is introduced only if the documented loss/throughput thresholds are crossed.

### Exact rollout and rollback semantics

```text
off:     Kuzu read/write; PostgreSQL schema idle
shadow:  Kuzu read/write authoritative; PostgreSQL write/compare
read:    PostgreSQL read; dual-write PostgreSQL and Kuzu
primary: PostgreSQL authoritative; retain best-effort Kuzu dual-write for rollback window
cleanup: disable Kuzu writes after one stable release and rollback drill
```

After cleanup, rollback to Kuzu requires a PostgreSQL-to-Kuzu reverse sync before changing reads. A flag change alone is not safe once Kuzu is stale. Production rollback never downgrades/drops PostgreSQL tables; `alembic downgrade -1` in Task 1 is permitted only on an empty ephemeral database.

### Safe Kuzu migration boundary

Replace `backend-service/scripts/backfill_kuzu_mastery.py` with:

- `ai-service/scripts/export_kuzu_mastery.py`: export versioned JSONL and a checksum manifest from a read-only filesystem/volume snapshot owned by the AI service. Never open the live embedded Kuzu directory concurrently for migration.
- `backend-service/scripts/import_kuzu_mastery.py`: dry-run by default, bounded pages, checkpointing, deterministic migration event IDs, quarantine, and idempotent UPSERT that never overwrites newer PostgreSQL state.
- Add `ai-service/tests/test_export_kuzu_mastery.py` and `backend-service/tests/test_import_kuzu_mastery.py`.
- Add a PostgreSQL-to-Kuzu reverse-sync command used only for late rollback after dual-write ends.

### Online deadline and isolation

- Propagate one monotonic absolute learner-overlay deadline of 40 ms through connect, pool acquisition, write/read, and optional retry. Defaults: connect 10 ms, pool 5 ms; retry only if remaining budget permits.
- Add a client bulkhead/concurrency cap, cancellation handling, and a streaming first-token regression test. Dependency degradation must not wait for independent KG/model work beyond the absolute deadline.
- Shared `kg:subgraph:*` entries remain user-agnostic. Personalized responses use an HMAC-derived user cache scope plus `learner_state_profiles.state_epoch`; never place raw user IDs or mastery in shared cache entries.

### Internal service security

- Authenticate service identity with current/previous rotating secrets, constant-time comparison, and explicit audience. Prefer mTLS/service-mesh identity when available.
- Restrict the route at private ingress, cap request body and batch sizes, rate-limit by caller identity, and audit caller/operation without learner payload or raw user ID.
- The authenticated AI service is explicitly authorized to act for any chat user; therefore “cross-user rejection” is replaced by caller-identity, payload-boundary, and cache-isolation tests.

### Retention and database operations

- Retain applied observation payloads for 90 days and minimal audit metadata for 365 days unless privacy policy requires less. Implement a dry-run cleanup job deleting at most 5,000 rows per batch, never pending/dead-letter rows, with cleanup-lag metrics and an optional versioned archive hook.
- Add `(status, available_at, created_at)` for claims and `(status, applied_at)` for cleanup.
- New empty-table indexes may be created normally. Any later index on a populated production table requires a separate non-transactional `CREATE INDEX CONCURRENTLY` migration and lock assessment.
- Partition observations monthly only after 50 GB or measured autovacuum/index pressure; consider hash sharding state by `user_id` only after indexed queries, connection tuning, and replicas cannot meet SLO.

### Executable command rules

- Treat every command block as running from repository root unless it begins with `(cd service && command)`.
- Replace stateful multi-line `cd` sequences with subshells, for example `(cd backend-service && pytest ...)`.
- Put Locust in `ai-service/tests/load/requirements.txt`, not production dependencies, and document the repository's exact dev-stack start command before running load tests.
- Before implementation, split Tasks 2, 5, 6, 8, and 9 into tracked sub-tasks no larger than one failing test, one minimal implementation, one verification command, and one commit. Preserve the TDD order already specified.

Do not advance a mode unless all gates for the previous mode have held for at least one representative peak period.

### Shadow to read

- At least 99% of sampled records are within the approved mastery tolerance.
- PostgreSQL batch-read p95 is below 40 ms.
- Degraded reads are below 0.1%.
- No PII appears in metrics/logs.

### Read to primary

- Chat p95/p99 remain within SLO at expected peak concurrency.
- Ranking quality does not regress on TRACE-CAG evaluation sets.
- Observation drops remain zero under normal peak and below 0.01% during injected dependency failure.
- Duplicate application remains zero.
- Rollback drill succeeds.

### Primary to cleanup

- One full stable release has run with Kuzu mastery writes disabled.
- Backfill/audit tooling reports no unexplained divergence.
- Operations approves removal; removal is a separate reviewed migration, not part of the initial cutover.

## Broker and sharding decision rules

Adopt a durable broker only if one of these persists after queue/batch tuning:

- observation loss exceeds 0.01% during expected dependency outages;
- process restarts regularly lose material queued state;
- peak observation rate exceeds what bounded in-process batching can drain with 50% headroom.

Consider PostgreSQL partitioning/read replicas before sharding. Consider physical sharding only when indexed batch reads and vertical/read scaling cannot meet SLO, or the state table no longer fits the operational envelope of one primary. Shard by stable hash of `user_id` so all state for one learner remains colocated.

## Final definition of done

- [ ] PostgreSQL is the documented source of truth for learner concept state.
- [ ] KuzuDB concept traversal works with user mastery writes disabled.
- [ ] TRACE-CAG loads at most the configured candidate-state batch per request.
- [ ] Shared topology cache is user-agnostic; personalized cache reuse is version-gated.
- [ ] Chat degrades gracefully when Redis or learner-state APIs fail.
- [ ] Observations are deterministic, idempotent, bounded, and observable.
- [ ] Migration/backfill is resumable and rollback is flag-based.
- [ ] Unit, integration, concurrency, security, and load tests pass.
- [ ] Measured production capacity and operational triggers are documented.
