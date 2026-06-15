# CEFR Content Agent Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a compliance-first CEFR content agent that administrators can run from the web dashboard or CLI to preview and apply generated A1-C2 courses.

**Architecture:** The backend persists jobs, validates uploads, dispatches Celery work, deduplicates vocabulary, and applies course artifacts transactionally. The AI service normalizes approved inputs and deterministically plans original course artifacts, with an LLM gateway kept behind a replaceable generator boundary. The admin app configures jobs, polls progress, previews artifacts, and explicitly applies draft courses.

**Tech Stack:** FastAPI, SQLAlchemy async, Alembic, PostgreSQL/SQLite test compatibility, Celery/Redis, Pydantic v2, React 19, TypeScript, Vitest.

---

> **Source-ingestion update:** Tasks and examples in this plan that reference
> VOA, BBC, British Council, Cambridge, Oxford, DOL, PREP, IELTS Workshop,
> Wiktionary/Kaikki, ConceptNet, or the legacy CEFR/Oxford crawler are
> superseded by
> `docs/superpowers/plans/2026-06-15-licensed-content-etl.md`. The licensed ETL
> plan is authoritative for source IDs, license policy, normalized contract v2,
> provenance, and database validation.

## File Map

### Backend service

- Create `app/models/content_agent.py`: job, upload, lesson-vocabulary, and provenance models.
- Create `app/schemas/content_agent.py`: request, artifact, progress, preview, and response contracts.
- Create `app/services/content_agent_uploads.py`: CSV/JSON parsing and validation.
- Create `app/services/content_agent_jobs.py`: job creation, state transitions, duplicate request protection, and status serialization.
- Create `app/services/content_agent_apply.py`: independent artifact validation, vocabulary deduplication, and transactional course creation.
- Create `app/services/content_agent_client.py`: authenticated AI-service HTTP client.
- Create `app/tasks/content_agent.py`: Celery orchestration and retry/resume boundaries.
- Create `app/routes/content_agent.py`: admin-only endpoints.
- Create `app/cli/content_agent.py`: generate/status/apply/retry commands.
- Create Alembic migration for new tables and indexes.
- Modify model/router/Celery registration and environment examples.
- Test in focused backend test modules.

### AI service

- Create `api/models/content_agent.py`: normalized input and course artifact contracts.
- Create `api/services/content_agent/policies.py`: source policy registry.
- Create `api/services/content_agent/adapters.py`: existing CEFR and normalized-record adapters.
- Create `api/services/content_agent/planner.py`: deterministic CEFR/topic curriculum planner.
- Create `api/services/content_agent/generator.py`: original definitions/examples/exercises behind a generator interface.
- Create `api/services/content_agent/store.py`: TTL job context.
- Create `api/services/content_agent/service.py`: ingestion and generation orchestration.
- Create `api/routes/content_agent.py`: service-token-protected internal endpoints.
- Modify route/config registration and environment examples.
- Test policy filtering, planner constraints, exercise mix, and internal authorization.

### Admin service

- Create `src/lib/contentAgentApi.ts`: typed API client.
- Create `src/components/content-agent/ContentAgentModal.tsx`: configuration/upload form.
- Create `src/components/content-agent/ContentAgentDrawer.tsx`: polling, progress, preview, apply/retry/cancel.
- Modify `CoursesPage.tsx`: add launch action and refresh after apply.
- Modify i18n dictionaries and styles.
- Test API calls and core UI state behavior.

## Chunk 1: Backend Persistence and API

### Task 1: Add content-agent database models and migration

**Files:**
- Create: `backend-service/app/models/content_agent.py`
- Modify: `backend-service/app/models/__init__.py`
- Create: `backend-service/alembic/versions/add_cefr_content_agent.py`
- Test: `backend-service/tests/test_content_agent_models.py`

- [ ] **Step 1: Write failing model tests**

Test job status defaults, unique lesson-vocabulary membership, upload metadata,
and job-to-created-ID persistence using the real test database.

- [ ] **Step 2: Run the focused tests**

Run: `cd backend-service && pytest tests/test_content_agent_models.py -q`

Expected: FAIL because the content-agent models do not exist.

- [ ] **Step 3: Implement focused models**

Add:

```python
class ContentAgentJob(Base):
    __tablename__ = "content_agent_jobs"
    id = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    requested_by_id = mapped_column(GUID(), ForeignKey("users.id"))
    status = mapped_column(String(32), default="queued", index=True)
    request_hash = mapped_column(String(64), index=True)
    config = mapped_column(PortableJSON, nullable=False)
    progress = mapped_column(PortableJSON, default=dict)
    source_manifest = mapped_column(PortableJSON, default=list)
    artifact = mapped_column(PortableJSON, nullable=True)
    warnings = mapped_column(PortableJSON, default=list)
    blocking_errors = mapped_column(PortableJSON, default=list)
    created_entity_ids = mapped_column(PortableJSON, default=dict)
    celery_task_id = mapped_column(String(255), nullable=True)
    error_message = mapped_column(Text, nullable=True)
```

Add `ContentAgentUpload`, `LessonVocabularyItem`, and `ContentProvenance` with
the constraints described by the design.

- [ ] **Step 4: Add the Alembic upgrade/downgrade**

Create all four tables with portable JSON/GUID types, indexes, foreign keys,
and uniqueness constraints. Keep legacy vocabulary origin columns unchanged.

- [ ] **Step 5: Run focused tests**

Run: `cd backend-service && pytest tests/test_content_agent_models.py -q`

Expected: PASS.

### Task 2: Add upload parsing and artifact schemas

**Files:**
- Create: `backend-service/app/schemas/content_agent.py`
- Create: `backend-service/app/services/content_agent_uploads.py`
- Test: `backend-service/tests/test_content_agent_uploads.py`

- [ ] **Step 1: Write failing upload tests**

Cover valid CSV, valid JSON array/envelope, invalid UTF-8, unsupported
extension, missing required fields, invalid CEFR/POS, 20,000-row cap, and
sanitized row-number errors.

- [ ] **Step 2: Run tests and confirm failure**

Run: `cd backend-service && pytest tests/test_content_agent_uploads.py -q`

- [ ] **Step 3: Implement strict Pydantic contracts**

Define CEFR enum/literals, source selection, generation configuration,
normalized vocabulary record, course artifact, quality report, and job
responses. Constrain words per lesson to 8-12 and selected levels to A1-C2.

- [ ] **Step 4: Implement upload parser**

Use `csv.DictReader` and `json.loads`, normalize field names, validate every row
through Pydantic, calculate SHA-256, and return either validated records or a
bounded list of row errors.

- [ ] **Step 5: Run focused tests**

Run: `cd backend-service && pytest tests/test_content_agent_uploads.py -q`

Expected: PASS.

### Task 3: Add job and apply services

**Files:**
- Create: `backend-service/app/services/content_agent_jobs.py`
- Create: `backend-service/app/services/content_agent_apply.py`
- Test: `backend-service/tests/test_content_agent_jobs.py`
- Test: `backend-service/tests/test_content_agent_apply.py`

- [ ] **Step 1: Write failing service tests**

Cover deterministic request hashes, duplicate active-job rejection, legal state
transitions, preview-only semantics, idempotent apply, reuse of existing
vocabulary, preservation of curated fields, lesson membership, and rollback on
invalid artifacts.

- [ ] **Step 2: Run focused tests**

Run:

```bash
cd backend-service
pytest tests/test_content_agent_jobs.py tests/test_content_agent_apply.py -q
```

- [ ] **Step 3: Implement job service**

Provide create/get/list/update-stage/fail/cancel/retry helpers. State transition
validation must reject stale or terminal writes.

- [ ] **Step 4: Implement artifact apply service**

Validate artifact independently, lock the job, create draft course trees,
deduplicate vocabulary by normalized `(word, part_of_speech)`, create junction
rows and provenance, update totals, and mark completed in one transaction.

- [ ] **Step 5: Run focused tests**

Expected: PASS.

### Task 4: Add AI client, Celery task, CLI, and admin API

**Files:**
- Create: `backend-service/app/services/content_agent_client.py`
- Create: `backend-service/app/tasks/content_agent.py`
- Create: `backend-service/app/routes/content_agent.py`
- Create: `backend-service/app/cli/__init__.py`
- Create: `backend-service/app/cli/content_agent.py`
- Modify: `backend-service/app/core/celery_app.py`
- Modify: `backend-service/app/core/config.py`
- Modify: `backend-service/app/main.py`
- Modify: `backend-service/.env.example`
- Modify: `docker-compose.yml`
- Modify: `docker-compose.production.yml`
- Test: `backend-service/tests/test_content_agent_routes.py`
- Test: `backend-service/tests/test_content_agent_task.py`

- [ ] **Step 1: Write failing route/task tests**

Cover admin authorization, upload, job create/list/detail/preview, apply,
retry/cancel, AI-service failure, cancellation checkpoints, and sanitized
errors.

- [ ] **Step 2: Run focused tests**

Run:

```bash
cd backend-service
pytest tests/test_content_agent_routes.py tests/test_content_agent_task.py -q
```

- [ ] **Step 3: Implement authenticated AI client**

Use `settings.AI_SERVICE_URL`, `CONTENT_AGENT_SERVICE_TOKEN`, bounded timeout,
and no logging of request records.

- [ ] **Step 4: Implement Celery orchestration**

Load approved records, update durable stages, call AI ingestion/generation,
persist preview artifacts, and clear AI temporary state. Retry transient HTTP
failures with bounded backoff.

- [ ] **Step 5: Implement admin router and CLI**

All routes depend on `require_admin`. The CLI calls the same application
services and exposes generate/status/apply/retry.

- [ ] **Step 6: Register worker task and configuration**

Add task include and environment variables:

```text
CONTENT_AGENT_ENABLED=false
CONTENT_AGENT_SERVICE_TOKEN=
CONTENT_AGENT_UPLOAD_TTL_DAYS=7
CONTENT_AGENT_AI_TIMEOUT_SECONDS=120
```

- [ ] **Step 7: Run focused backend tests**

Expected: PASS.

## Chunk 2: AI Pipeline

### Task 5: Add source policies and normalized contracts

**Files:**
- Create: `ai-service/api/models/content_agent.py`
- Create: `ai-service/api/services/content_agent/__init__.py`
- Create: `ai-service/api/services/content_agent/policies.py`
- Create: `ai-service/api/services/content_agent/adapters.py`
- Test: `ai-service/tests/test_content_agent_policies.py`
- Test: `ai-service/tests/test_content_agent_adapters.py`

- [ ] **Step 1: Write failing policy/adapter tests**

Prove metadata-only adapters strip bodies/examples/audio, disabled adapters
fail closed, existing CEFR records retain level attribution, and unsupported
sources are rejected.

- [ ] **Step 2: Run tests**

Run:

```bash
cd ai-service
pytest tests/test_content_agent_policies.py tests/test_content_agent_adapters.py -q
```

- [ ] **Step 3: Implement policy registry**

Encode all approved sources, modes, allowed fields, rate limits, and review
dates. Only `existing_cefr`, `admin_upload`, and verified VOA can carry content.

- [ ] **Step 4: Implement adapters**

Provide pure normalization/filtering functions. Existing CEFR loading wraps the
current crawler module without writing files during requests.

- [ ] **Step 5: Run focused tests**

Expected: PASS.

### Task 6: Add deterministic curriculum planner and generator

**Files:**
- Create: `ai-service/api/services/content_agent/planner.py`
- Create: `ai-service/api/services/content_agent/generator.py`
- Create: `ai-service/api/services/content_agent/service.py`
- Test: `ai-service/tests/test_content_agent_planner.py`
- Test: `ai-service/tests/test_content_agent_generator.py`

- [ ] **Step 1: Write failing planner tests**

Cover one course per selected level, topic grouping, stable ordering, 8-12
words per lesson, reuse without duplicate catalog entries, and low-confidence
rejection.

- [ ] **Step 2: Write failing exercise tests**

Require exactly ten default exercises with two speaking and two listening
items, supported option shapes, stable IDs, and no source-body leakage.

- [ ] **Step 3: Implement planner**

Use deterministic topic buckets and chunking. Generate original titles and
descriptions from level/topic metadata.

- [ ] **Step 4: Implement generator boundary**

Define a generator protocol. The initial implementation creates deterministic
original definitions/examples/exercises so tests and local operation do not
depend on Gemini; a model-backed implementation can replace it without
changing artifact contracts.

- [ ] **Step 5: Run focused tests**

Expected: PASS.

### Task 7: Add TTL store and internal endpoints

**Files:**
- Create: `ai-service/api/services/content_agent/store.py`
- Create: `ai-service/api/routes/content_agent.py`
- Modify: `ai-service/api/core/config.py`
- Modify: `ai-service/api/main.py`
- Modify: `ai-service/.env.example`
- Test: `ai-service/tests/test_content_agent_routes.py`

- [ ] **Step 1: Write failing authorization and lifecycle tests**

Cover missing/wrong service token, batch ingestion, generation, delete, expiry,
and bounded record counts.

- [ ] **Step 2: Implement in-memory/Redis-compatible TTL store**

Use Redis when available and a process-local fallback for tests/development.
Persist only policy-filtered normalized records.

- [ ] **Step 3: Implement internal routes**

Verify `X-Content-Agent-Token` with constant-time comparison and expose only the
three internal operations in the spec.

- [ ] **Step 4: Register configuration and route**

Add `CONTENT_AGENT_SERVICE_TOKEN`, maximum records, and TTL settings.

- [ ] **Step 5: Run focused AI tests**

Expected: PASS.

## Chunk 3: Admin Dashboard and Full Verification

### Task 8: Add typed dashboard API client

**Files:**
- Create: `admin-service/src/lib/contentAgentApi.ts`
- Test: `admin-service/src/lib/contentAgentApi.test.ts`

- [ ] **Step 1: Write failing API client tests**

Cover upload form data, job creation, list/detail/preview, apply, retry, and
cancel URLs/methods.

- [ ] **Step 2: Implement typed client**

Use the existing `apiFetch` JWT/refresh behavior and keep all response contracts
in the focused module.

- [ ] **Step 3: Run test**

Run: `cd admin-service && pnpm test -- contentAgentApi.test.ts`

Expected: PASS.

### Task 9: Add agent configuration modal and job drawer

**Files:**
- Create: `admin-service/src/components/content-agent/ContentAgentModal.tsx`
- Create: `admin-service/src/components/content-agent/ContentAgentDrawer.tsx`
- Modify: `admin-service/src/pages/CoursesPage.tsx`
- Modify: `admin-service/src/lib/i18n/en.ts`
- Modify: `admin-service/src/lib/i18n/vi.ts`
- Modify: `admin-service/src/styles.css`
- Test: `admin-service/src/components/content-agent/ContentAgentModal.test.tsx`
- Test: `admin-service/src/components/content-agent/ContentAgentDrawer.test.tsx`

- [ ] **Step 1: Write failing component tests**

Cover CEFR/source selection, 8-12 validation, upload flow, preview-only label,
progress rendering, blocking-error apply disablement, and successful apply.

- [ ] **Step 2: Implement modal**

Default to all CEFR levels, `existing_cefr`, ten vocabulary items, and ten
exercises. Show compliance badges and upload validation feedback.

- [ ] **Step 3: Implement drawer**

Poll active jobs, stop at terminal states, render preview tree/counters, and
provide apply/retry/cancel actions.

- [ ] **Step 4: Wire Courses page**

Add `Generate with Agent`, preserve existing CRUD/import flows, and refresh the
course list after apply.

- [ ] **Step 5: Run focused admin tests**

Expected: PASS.

### Task 10: Security review, full tests, and code review

**Files:**
- Review all changed files.

- [ ] **Step 1: Spawn test-writer**

Ask the test-writer to inspect all new public functions/endpoints and add
missing happy, edge, and error-path coverage without editing production files.

- [ ] **Step 2: Spawn security-reviewer**

Review admin authorization, uploads, service token, SSRF controls, DB migration,
environment variables, and error sanitization. Fix all critical/high findings.

- [ ] **Step 3: Run complete scoped verification**

```bash
cd ai-service && pytest tests/ -q
cd backend-service && pytest tests/ -q
cd admin-service && pnpm test && pnpm build:check
```

- [ ] **Step 4: Run migration checks**

```bash
cd backend-service
alembic heads
alembic upgrade head
```

Expected: one valid head and successful upgrade.

- [ ] **Step 5: Spawn code-reviewer**

Use code-review-graph change context, inspect impact and tests, then fix all
critical/warn correctness findings.

- [ ] **Step 6: Final smoke verification**

Create an A1 preview from existing CEFR data in eager/test mode, assert a draft
course artifact with speaking/listening exercises, apply it to a disposable
test database, and confirm a second apply is idempotent.
