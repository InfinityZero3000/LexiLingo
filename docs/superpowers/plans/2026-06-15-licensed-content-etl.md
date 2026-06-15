# Licensed Content ETL Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ambiguous website crawling with a reproducible, license-gated ETL that supplies validated CEFR A1-C2 source snapshots to the content agent and permits production database writes only when every required property passes backend validation.

**Architecture:** The AI service downloads pinned official datasets into immutable snapshots, verifies license metadata and checksums, normalizes records into contract v2, and quarantines invalid rows. Content-agent jobs pin approved snapshot IDs and generate a versioned course artifact. The backend independently validates the artifact and applies it to PostgreSQL in one idempotent transaction; the admin dashboard can select only approved snapshots.

**Tech Stack:** Python 3.11+, FastAPI, Pydantic v2, `httpx`, `defusedxml`, JSONL, SHA-256 manifests, Celery, SQLAlchemy async, Alembic, PostgreSQL, React 19, TypeScript, Vitest, Docker Compose.

---

## Scope And Delivery Order

This plan is split into independently testable releases:

1. **Core lexical release:** OEWN, CMUdict, CEFR-J, Wikidata, uploads, preview, and transactional apply.
2. **Sentence/audio release:** Tatoeba and Mini LibriSpeech behind opt-in flags.
3. **Large-corpus release:** full LibriSpeech and Common Voice after storage sizing and license-filter tests pass.

Firecrawl, Crawl4AI, browser scraping, and arbitrary URL ingestion are not part
of the production ETL. The existing content-agent feature remains behind
`CONTENT_AGENT_ENABLED`; dataset sync has its own `CONTENT_ETL_ENABLED` flag.

## File Map

### Shared contracts

- Create `contracts/content-agent/source-record-v2.schema.json`: normalized source record contract.
- Create `contracts/content-agent/course-artifact-v2.schema.json`: database-bound artifact contract.
- Create `contracts/content-agent/exercise-types-v1.json`: canonical `ui_type -> type` mapping.

### AI service

- Create `api/services/content_etl/contracts.py`: Pydantic manifest, record, quarantine, and report models.
- Create `api/services/content_etl/registry.py`: strict source and license allowlists.
- Create `api/services/content_etl/downloader.py`: HTTPS/host/size/checksum-safe downloader.
- Create `api/services/content_etl/storage.py`: immutable local snapshot storage and atomic promotion.
- Create `api/services/content_etl/pipeline.py`: extract, normalize, validate, quarantine, approve.
- Create `api/services/content_etl/cli.py`: `list`, `sync`, `validate`, and `activate` commands.
- Create `api/services/content_etl/adapters/`: focused adapters for each approved source.
- Modify content-agent contracts, policies, adapters, service, routes, and tests.
- Remove unsafe crawler stages and dependencies from `scripts/kg_pipeline`.

### Backend service

- Create `app/services/content_agent_validation.py`: independent artifact and database-boundary validator.
- Create `app/services/content_agent_sources.py`: AI source-catalog client and snapshot resolution.
- Create `app/services/vocabulary_catalog.py`: concurrency-safe normalized vocabulary upsert.
- Add a provenance-v2 Alembic migration.
- Modify content-agent schemas, client, task, routes, apply service, environment, and tests.

### Admin service

- Modify the content-agent API client and modal to load source snapshots dynamically.
- Add upload-rights attestation and source health/license/version badges.
- Extend preview/apply blocking-error rendering and tests.

### Operations

- Add persistent `/data/content-etl` volumes to Docker Compose.
- Add pinned source/version environment variables and an operator runbook.
- Add fixtures only; never commit downloaded datasets or generated audio.

## Contract And Database Gates

The following gates are mandatory. A warning may appear in preview; a blocking
failure prevents `preview_ready` or database apply.

| Entity | Required before apply | Blocking checks |
| --- | --- | --- |
| Source snapshot | source/version, official URL/host, license ID/URL, attribution, retrieval time, raw SHA-256, adapter version, approved record count | unknown license, forbidden license, missing attribution, checksum mismatch, unpinned production version, quarantine ratio above threshold |
| Source record | schema v2, stable ID, source/version, language, license, lineage, record checksum | unknown fields, control characters, invalid URL, unsupported POS/CEFR, missing required content for its usage |
| Course | title, description, language `en`, A1-C2 level, normalized tag object, at least one unit | duplicate level course in artifact, overlong strings, totals mismatch |
| Unit | title, zero-based unique order, at least one lesson | duplicate/non-contiguous order, wrong course linkage |
| Lesson | title, supported type, unique order, duration, XP, exercises, vocabulary | empty content, count mismatch, duplicate exercise IDs |
| Vocabulary | canonical lowercase word, non-empty definition, POS enum, CEFR enum, source provenance | duplicate normalized identity inside artifact, placeholder definition, invalid translation/audio shape |
| Exercise | ID, base type, registered UI type, question, correct answer, difficulty, points | incompatible `type/ui_type`, malformed options, answer leakage, missing canonical speaking/listening text |
| Provenance | entity/job/source, source version, license, attribution, raw/record checksums, lineage | missing source snapshot, disallowed license, checksum not represented by manifest |

`VocabularyItem.word` stores the canonical normalized identity. Display spelling
and source variants live in provenance metadata. Existing curated vocabulary is
never overwritten; an approved source may fill only blank or recognized
placeholder fields.

## Chunk 1: Remove Unsafe Inputs And Establish Contracts

### Task 1: Remove denied sources from runtime configuration

**Files:**
- Modify: `ai-service/api/services/content_agent/policies.py`
- Modify: `ai-service/api/services/content_agent/adapters.py`
- Modify: `backend-service/app/schemas/content_agent.py`
- Modify: `admin-service/src/lib/contentAgentApi.ts`
- Modify: `admin-service/src/components/content-agent/ContentAgentModal.tsx`
- Modify: `ai-service/tests/test_content_agent_policies.py`
- Modify: `ai-service/tests/test_content_agent_adapters.py`
- Modify: `backend-service/tests/test_content_agent_contract.py`
- Modify: `admin-service/src/components/content-agent/ContentAgentModal.test.tsx`

- [ ] **Step 1: Write failing denylist tests**

Assert that `voa`, `bbc`, `british_council`, `cambridge_*`, `oxford`, `dol`,
`prep`, `ielts_workshop`, `wiktionary`, and `conceptnet` are unsupported rather
than merely disabled. Assert that the dashboard does not render them.

- [ ] **Step 2: Run focused tests**

```bash
cd ai-service && pytest tests/test_content_agent_policies.py tests/test_content_agent_adapters.py -q
cd ../backend-service && pytest tests/test_content_agent_contract.py -q
cd ../admin-service && pnpm test -- ContentAgentModal.test.tsx
```

Expected: FAIL because the old source IDs remain in registries and UI types.

- [ ] **Step 3: Replace source IDs**

The selectable source IDs become:

```text
oewn,cmudict,cefr_j,wikidata,tatoeba,librispeech,common_voice,admin_upload
```

Keep `existing_cefr` as a hidden compatibility alias for one release. It must
resolve only to an approved CEFR-J snapshot and must not load old Oxford data.

- [ ] **Step 4: Re-run focused tests**

Expected: PASS.

### Task 2: Disable and remove unsafe crawler stages

**Files:**
- Delete: `ai-service/scripts/kg_pipeline/crawlers/web_crawler.py`
- Delete: `ai-service/scripts/kg_pipeline/crawlers/wiktionary_kaikki.py`
- Delete: `ai-service/scripts/kg_pipeline/crawlers/conceptnet_extractor.py`
- Delete: `ai-service/scripts/kg_pipeline/crawlers/cefr_lists.py`
- Delete: `ai-service/scripts/kg_pipeline/crawlers/wordnet_extractor.py`
- Modify: `ai-service/scripts/kg_pipeline/config.py`
- Modify: `ai-service/scripts/kg_pipeline/run_pipeline.py`
- Modify: `ai-service/scripts/kg_pipeline/requirements_pipeline.txt`
- Test: `ai-service/tests/test_kg_pipeline_source_safety.py`

- [ ] **Step 1: Write a failing static safety test**

The test scans production Python/config files and fails on denied domains,
`WEB_SOURCES`, `crawl4ai`, Kaikki dump URLs, ConceptNet dump URLs, and the
third-party Oxford repository URL.

- [ ] **Step 2: Run the test**

Run: `cd ai-service && pytest tests/test_kg_pipeline_source_safety.py -q`

Expected: FAIL with the current crawler files and configuration.

- [ ] **Step 3: Remove unsafe stages**

Retain only hand-authored KG import utilities that have known ownership.
Remove Crawl4AI, BeautifulSoup, NLTK crawler-only dependencies, and rate-limit
packages from `requirements_pipeline.txt` when no retained module imports them.

- [ ] **Step 4: Run safety and import tests**

```bash
cd ai-service
pytest tests/test_kg_pipeline_source_safety.py -q
python scripts/kg_pipeline/run_pipeline.py --dry-run
```

Expected: PASS; dry-run lists no web/Wiktionary/ConceptNet/old-CEFR stage.

### Task 3: Add shared v2 schemas and parity tests

**Files:**
- Create: `contracts/content-agent/source-record-v2.schema.json`
- Create: `contracts/content-agent/course-artifact-v2.schema.json`
- Create: `contracts/content-agent/exercise-types-v1.json`
- Create: `ai-service/tests/test_content_contract_parity.py`
- Create: `backend-service/tests/test_content_contract_parity.py`
- Modify: `admin-service/src/lib/adminApi.ts`
- Modify: `admin-service/src/lib/contentAgentApi.ts`

- [ ] **Step 1: Add failing parity tests**

Tests must prove:

- both Python services expose artifact schema version 2;
- CEFR and POS enums match;
- every UI type maps to one supported base type;
- source-record required fields and maximum lengths match;
- unknown fields are rejected.

- [ ] **Step 2: Run parity tests**

```bash
cd ai-service && pytest tests/test_content_contract_parity.py -q
cd ../backend-service && pytest tests/test_content_contract_parity.py -q
cd ../admin-service && pnpm build:check
```

Expected: FAIL until schema v2 and mappings are aligned.

- [ ] **Step 3: Implement canonical JSON contracts**

Use `additionalProperties: false`. Include format/pattern constraints for
SHA-256, HTTPS/internal storage URLs, CEFR, POS, license IDs, source IDs, and
exercise IDs.

- [ ] **Step 4: Align service contracts and rerun**

Expected: all parity tests and TypeScript build pass.

## Chunk 2: Versioned Dataset ETL

### Task 4: Add ETL contracts, license registry, and settings

**Files:**
- Create: `ai-service/api/services/content_etl/__init__.py`
- Create: `ai-service/api/services/content_etl/contracts.py`
- Create: `ai-service/api/services/content_etl/registry.py`
- Modify: `ai-service/api/core/config.py`
- Modify: `ai-service/.env.example`
- Modify: `ai-service/requirements.txt`
- Test: `ai-service/tests/content_etl/test_registry.py`
- Test: `ai-service/tests/content_etl/test_contracts.py`

- [ ] **Step 1: Write failing registry tests**

Cover exact allowed license IDs, denied ShareAlike/non-commercial/unknown
licenses, official host allowlists, disabled-by-default large corpora, required
attribution, and production pin requirements.

- [ ] **Step 2: Add settings**

```text
CONTENT_ETL_ENABLED=false
CONTENT_ETL_STORAGE_ROOT=/data/content-etl
CONTENT_ETL_HTTP_TIMEOUT_SECONDS=60
CONTENT_ETL_MAX_DOWNLOAD_BYTES=1073741824
CONTENT_ETL_MAX_QUARANTINE_RATIO=0.02
CONTENT_ETL_USER_AGENT=LexiLingo-ETL/1.0
CONTENT_ETL_OEWN_VERSION=2025
CONTENT_ETL_CMU_REF=<pinned-commit>
CONTENT_ETL_CEFR_J_REF=<pinned-commit>
CONTENT_ETL_WIKIDATA_SNAPSHOT=<pinned-date>
CONTENT_ETL_TATOEBA_RELEASE=
CONTENT_ETL_LIBRISPEECH_RELEASE=
CONTENT_ETL_COMMON_VOICE_RELEASE=
```

Production validation rejects empty or moving refs such as `main`, `master`,
or `latest` for enabled sources.

- [ ] **Step 3: Add the only new parsing dependency**

Add `defusedxml>=0.7.1` to `ai-service/requirements.txt`. Use existing
`httpx`, stdlib `csv/json/gzip/bz2/tarfile`, and SHA-256 utilities.

- [ ] **Step 4: Implement contracts and registry**

Core models:

```python
class SourceManifest(BaseModel):
    schema_version: Literal[1] = 1
    snapshot_id: str
    source_name: SourceName
    source_version: str
    official_url: AnyHttpUrl
    license_id: AllowedLicenseId
    license_url: AnyHttpUrl
    attribution_text: str
    retrieved_at: datetime
    raw_sha256: str
    adapter_version: int
    status: Literal["downloaded", "normalized", "approved", "rejected"]
    counts: SourceCounts

class QuarantineEntry(BaseModel):
    source_name: SourceName
    source_version: str
    source_location: str
    error_code: str
    message: str
    raw_excerpt_hash: str
```

- [ ] **Step 5: Run focused tests**

Run: `cd ai-service && pytest tests/content_etl/test_registry.py tests/content_etl/test_contracts.py -q`

Expected: PASS.

### Task 5: Implement secure download and immutable snapshot storage

**Files:**
- Create: `ai-service/api/services/content_etl/downloader.py`
- Create: `ai-service/api/services/content_etl/archive.py`
- Create: `ai-service/api/services/content_etl/storage.py`
- Test: `ai-service/tests/content_etl/test_downloader.py`
- Test: `ai-service/tests/content_etl/test_archive.py`
- Test: `ai-service/tests/content_etl/test_storage.py`

- [ ] **Step 1: Write failing security/storage tests**

Cover HTTPS-only, exact host allowlist, redirect revalidation, DNS resolution
blocking private/loopback/link-local IPs, content-length and streaming byte
limits, timeout, checksum mismatch, temporary-file cleanup, immutable version
directories, and atomic `current.json` activation. Archive tests cover absolute
paths, `..` traversal, symlinks/hardlinks, file-count limits, per-file limits,
and total decompressed-byte limits.

- [ ] **Step 2: Implement safe downloader**

Stream to `<storage>/tmp/<uuid>.part`, hash while downloading, fsync, verify,
then move into `raw/<source>/<version>/`. Never log query strings or source
record bodies.

- [ ] **Step 3: Implement snapshot layout**

Archive extraction must validate every member before writing any file and
extract only the members requested by the source adapter.

```text
/data/content-etl/
  raw/<source>/<version>/
  normalized/<source>/<version>/records.jsonl
  quarantine/<source>/<version>/errors.jsonl
  manifests/<source>/<version>.json
  active/<source>.json
  tmp/
```

Approval writes the manifest last. Existing approved directories are read-only
and a different checksum for the same source/version is a blocking error.

- [ ] **Step 4: Run focused tests**

Expected: PASS.

### Task 6: Implement the pipeline and CLI

**Files:**
- Create: `ai-service/api/services/content_etl/pipeline.py`
- Create: `ai-service/api/services/content_etl/cli.py`
- Test: `ai-service/tests/content_etl/test_pipeline.py`
- Modify: `ai-service/Dockerfile`
- Modify: `ai-service/Dockerfile.prod`

- [ ] **Step 1: Write failing pipeline tests**

Cover state transitions, deterministic record ordering, record checksum
stability, quarantine counts, max quarantine ratio, duplicate record IDs,
license recheck before approval, resume after normalized output, and failed-run
non-activation.

- [ ] **Step 2: Implement pipeline stages**

```text
resolve pinned source
→ download raw artifact
→ verify artifact/license/checksum
→ adapter normalize
→ schema validate each record
→ deterministic dedup
→ quarantine invalid rows
→ quality report
→ approve immutable snapshot
→ atomically activate snapshot
```

- [ ] **Step 3: Implement CLI**

```bash
python -m api.services.content_etl.cli list
python -m api.services.content_etl.cli sync --sources oewn,cmudict,cefr_j,wikidata
python -m api.services.content_etl.cli validate --source oewn --version 2025
python -m api.services.content_etl.cli activate --source oewn --version 2025
```

`sync` is dry-run unless `--write` is passed. `activate` requires an approved
manifest and refuses a rejected snapshot.

- [ ] **Step 4: Run pipeline tests and CLI smoke test**

```bash
cd ai-service
pytest tests/content_etl/test_pipeline.py -q
python -m api.services.content_etl.cli list
```

Expected: PASS and a valid empty/source registry listing.

### Task 7: Add core lexical adapters

**Files:**
- Create: `ai-service/api/services/content_etl/adapters/base.py`
- Create: `ai-service/api/services/content_etl/adapters/oewn.py`
- Create: `ai-service/api/services/content_etl/adapters/cmudict.py`
- Create: `ai-service/api/services/content_etl/adapters/cefr_j.py`
- Create: `ai-service/api/services/content_etl/adapters/wikidata.py`
- Create: `ai-service/tests/content_etl/fixtures/`
- Test: `ai-service/tests/content_etl/test_core_adapters.py`

- [ ] **Step 1: Add small official-format fixtures and failing golden tests**

Fixtures contain only the minimum rows needed to test parsers. Golden tests
assert exact normalized JSON for POS mapping, definitions, ARPAbet, CEFR labels,
topic QIDs, attribution, lineage, and checksums.

- [ ] **Step 2: Implement OEWN adapter**

Parse XML with `defusedxml`; emit one lexical record per lemma/POS/sense needed
by the agent. Preserve OEWN IDs in `source_record_id`.

- [ ] **Step 3: Implement CMUdict adapter**

Normalize numbered pronunciation variants without treating them as different
vocabulary identities. Store ARPAbet in metadata until an explicit IPA
converter is added.

- [ ] **Step 4: Implement CEFR-J adapter**

Accept only the pinned CEFR-J files covered by the permission notice. Emit
label-only records. Reject Octanove/ShareAlike files by path and license.

- [ ] **Step 5: Implement Wikidata topic adapter**

Use only configured QIDs through official EntityData/API responses. Store
topic IDs and English labels; do not import descriptions as dictionary
definitions.

- [ ] **Step 6: Run adapter tests**

Run: `cd ai-service && pytest tests/content_etl/test_core_adapters.py -q`

Expected: PASS with byte-for-byte stable golden records.

### Task 8: Add opt-in sentence and audio adapters

**Files:**
- Create: `ai-service/api/services/content_etl/adapters/tatoeba.py`
- Create: `ai-service/api/services/content_etl/adapters/librispeech.py`
- Create: `ai-service/api/services/content_etl/adapters/common_voice.py`
- Test: `ai-service/tests/content_etl/test_corpus_adapters.py`

- [ ] **Step 1: Write failing per-record license tests**

Tatoeba audio rows pass only when their individual license is CC0 or CC BY and
contributor attribution is present. Common Voice passes only when release
metadata says `CC0-1.0`. LibriSpeech passes only with its CC BY 4.0 license file.

- [ ] **Step 2: Implement Tatoeba text/audio metadata adapter**

Prefer CC0 rows. Keep CC BY sentence/audio attribution on every emitted record.
Do not copy rows with missing or incompatible licenses.

- [ ] **Step 3: Implement Mini LibriSpeech first**

Use Mini LibriSpeech for development fixtures and capacity tests. Full
LibriSpeech remains disabled until an operator explicitly sets its release and
storage budget.

- [ ] **Step 4: Implement Common Voice release adapter**

Require an operator-provided downloaded release or authorized Mozilla Data
Collective URL. Validate release metadata before reading TSV/audio members.

- [ ] **Step 5: Run corpus tests**

Expected: PASS; incompatible rows appear in quarantine with stable error codes.

## Chunk 3: Content Agent And Database Integration

### Task 9: Expose approved snapshots to content-agent jobs

**Files:**
- Modify: `ai-service/api/models/content_agent.py`
- Modify: `ai-service/api/services/content_agent/policies.py`
- Modify: `ai-service/api/services/content_agent/adapters.py`
- Modify: `ai-service/api/services/content_agent/service.py`
- Modify: `ai-service/api/routes/content_agent.py`
- Test: `ai-service/tests/test_content_agent_routes.py`
- Test: `ai-service/tests/test_content_agent_adapters.py`

- [ ] **Step 1: Write failing source-catalog and attach tests**

Add internal contracts:

```text
GET  /api/v1/internal/content-agent/sources
POST /api/v1/internal/content-agent/jobs/{job_id}/snapshots
```

Tests prove only approved active snapshots are returned/attachable, requested
source IDs resolve to exact snapshot IDs, and a snapshot cannot change during a
job.

- [ ] **Step 2: Upgrade source records to contract v2**

Remove old `license_mode/content_usage` assumptions where they conflict with
v2. Preserve compatibility parsing only for stored stage-1 uploads.

- [ ] **Step 3: Load snapshot records in bounded batches**

The AI service reads normalized JSONL lazily, filters selected CEFR/topic data,
and enforces `CONTENT_AGENT_MAX_RECORDS`. It never sends raw dataset bodies to
the admin browser.

- [ ] **Step 4: Run content-agent AI tests**

Expected: PASS.

### Task 10: Add backend source resolution and provenance-v2 migration

**Files:**
- Create: `backend-service/app/services/content_agent_sources.py`
- Modify: `backend-service/app/services/content_agent_client.py`
- Modify: `backend-service/app/models/content_agent.py`
- Create: `backend-service/alembic/versions/add_content_provenance_v2.py`
- Modify: `backend-service/app/schemas/content_agent.py`
- Test: `backend-service/tests/test_content_agent_sources.py`
- Test: `backend-service/tests/test_content_agent_contract.py`

- [ ] **Step 1: Write failing source-resolution tests**

Cover unavailable source, inactive snapshot, license mismatch, stale catalog,
exact snapshot pinning in request hashes, and sanitized AI-service failures.

- [ ] **Step 2: Extend provenance**

Add:

```text
source_version
license_id
license_url
attribution_text
raw_checksum
record_checksum
lineage
content_usage
rights_confirmed_at
rights_statement_version
```

Keep `license_mode` and `source_checksum` temporarily for backward-compatible
reads; new provenance records must populate v2 fields. The rights fields are
added to `content_agent_uploads` and are required for new uploads.

- [ ] **Step 3: Resolve snapshots at job creation**

The backend stores the resolved snapshot descriptors in job config and request
hash. Retrying a job reuses those descriptors rather than resolving `current`
again.

- [ ] **Step 4: Run migration and focused tests**

```bash
cd backend-service
alembic upgrade head
pytest tests/test_content_agent_sources.py tests/test_content_agent_contract.py -q
```

Expected: migration succeeds and tests pass.

### Task 11: Add strict artifact/database-boundary validation

**Files:**
- Create: `backend-service/app/services/content_agent_validation.py`
- Modify: `backend-service/app/schemas/content_agent.py`
- Modify: `backend-service/app/services/content_agent_apply.py`
- Test: `backend-service/tests/test_content_agent_validation.py`

- [ ] **Step 1: Write a failing validation matrix**

One test per blocking gate: schema version, manifest coverage, license, hash,
course level, unique orders, definition, POS, CEFR, translation shape, URL,
exercise ID, `type/ui_type`, options, speaking/listening text, counts, and
provenance.

- [ ] **Step 2: Implement pure validator**

Return:

```python
class ValidationReport(BaseModel):
    blocking_errors: list[ValidationIssue]
    warnings: list[ValidationIssue]
    metrics: dict[str, int | float]
```

Each issue has `code`, `path`, and sanitized `message`. Apply accepts only a
report with no blocking errors.

- [ ] **Step 3: Validate exact DB property mapping**

Standardize content-agent course tags as:

```json
{
  "categories": ["cefr", "A1"],
  "source": ["content-agent"],
  "topics": ["daily_life"]
}
```

Lesson content is:

```json
{
  "version": 2,
  "generated_by": "cefr-content-agent",
  "source_job_id": "<uuid>",
  "exercises": []
}
```

- [ ] **Step 4: Run validation tests**

Expected: PASS.

### Task 12: Make vocabulary upsert concurrency-safe and idempotent

**Files:**
- Create: `backend-service/app/services/vocabulary_catalog.py`
- Modify: `backend-service/app/services/content_agent_apply.py`
- Test: `backend-service/tests/test_vocabulary_catalog.py`
- Modify: `backend-service/tests/test_content_agent_apply.py`

- [ ] **Step 1: Write failing database tests**

Cover canonical Unicode/apostrophe/hyphen normalization, same word/different
POS, duplicate words across lessons, concurrent inserts, placeholder-definition
replacement, curated-field preservation, rollback, and repeat apply.

- [ ] **Step 2: Implement batch lookup/upsert**

Query only artifact keys, lock matching rows where supported, insert missing
rows with conflict handling, reselect after conflicts, and return a stable
identity map. Do not load the entire vocabulary table.

- [ ] **Step 3: Apply provenance and membership**

Create one vocabulary row per canonical identity, one membership per
lesson/vocabulary pair, and provenance entries linked to exact source records.

- [ ] **Step 4: Run focused tests with PostgreSQL when available**

```bash
cd backend-service
pytest tests/test_vocabulary_catalog.py tests/test_content_agent_apply.py -q
```

Expected: PASS on SQLite compatibility tests and PostgreSQL integration tests.

### Task 13: Update Celery flow and upload ownership validation

**Files:**
- Modify: `backend-service/app/services/content_agent_uploads.py`
- Modify: `backend-service/app/tasks/content_agent.py`
- Modify: `backend-service/app/routes/content_agent.py`
- Test: `backend-service/tests/test_content_agent_uploads.py`
- Test: `backend-service/tests/test_content_agent_tasks.py`
- Test: `backend-service/tests/test_content_agent_routes.py`

- [ ] **Step 1: Write failing flow tests**

Cover rights attestation, snapshot resolution, stage counters, quarantine
warnings, snapshot replay on retry, preview blocking, cancellation boundaries,
and no automatic apply from dashboard jobs.

- [ ] **Step 2: Require upload rights attestation**

The upload endpoint accepts `rights_confirmed=true`. Persist uploader, checksum,
schema version, and attestation timestamp. Reject uploads without confirmation.

- [ ] **Step 3: Update durable stages**

```text
queued → resolving_sources → loading_snapshots → normalizing_upload
→ classifying → planning → generating → validating → preview_ready
→ applying → completed
```

- [ ] **Step 4: Run focused backend tests**

Expected: PASS.

## Chunk 4: Admin And Operations

### Task 14: Make dashboard source selection dynamic

**Files:**
- Modify: `backend-service/app/routes/content_agent.py`
- Modify: `backend-service/tests/test_content_agent_routes.py`
- Modify: `admin-service/src/lib/contentAgentApi.ts`
- Modify: `admin-service/src/components/content-agent/ContentAgentModal.tsx`
- Modify: `admin-service/src/components/content-agent/ContentAgentDrawer.tsx`
- Modify: `admin-service/src/lib/i18n/en.ts`
- Modify: `admin-service/src/lib/i18n/vi.ts`
- Modify: `admin-service/src/styles.css`
- Modify: `admin-service/src/components/content-agent/ContentAgentModal.test.tsx`
- Modify: `admin-service/src/components/content-agent/ContentAgentDrawer.test.tsx`

- [ ] **Step 1: Write failing UI tests**

Cover loading/error/empty catalog states, approved source selection, disabled
inactive snapshots, license/version/count badges, upload attestation, and apply
disabled when any blocking issue exists.

- [ ] **Step 2: Add backend source-catalog API**

Expose:

```text
GET /api/v1/admin/content-agent/sources
```

The backend authenticates admin users and returns sanitized AI catalog data.
Source sync remains an operator CLI action in this release.

- [ ] **Step 3: Replace hard-coded source options**

The modal loads the catalog, preselects enabled core lexical snapshots, and
submits source IDs. Display source version, license, record count, last sync,
and status.

- [ ] **Step 4: Add upload attestation**

Require a checkbox confirming the administrator owns the upload or has rights
to use it commercially.

- [ ] **Step 5: Run UI tests and build**

```bash
cd admin-service
pnpm test -- ContentAgentModal.test.tsx ContentAgentDrawer.test.tsx
pnpm build:check
```

Expected: PASS.

### Task 15: Configure persistent storage and installation

**Files:**
- Modify: `docker-compose.yml`
- Modify: `docker-compose.production.yml`
- Modify: `ai-service/.env.example`
- Modify: `backend-service/.env.example`
- Modify: `ai-service/.gitignore`
- Create: `docs/runbooks/licensed-content-etl.md`

- [ ] **Step 1: Add persistent volume**

Mount `content_etl_data:/data/content-etl` into the AI service in development
and production Compose. Do not mount this path into backend/admin containers.

- [ ] **Step 2: Document installation**

```bash
cd ai-service
python -m pip install -r requirements.txt
CONTENT_ETL_ENABLED=true \
python -m api.services.content_etl.cli sync \
  --sources oewn,cmudict,cefr_j,wikidata \
  --write
python -m api.services.content_etl.cli list

cd ../backend-service
alembic upgrade head

cd ../admin-service
pnpm install --frozen-lockfile
pnpm build:check
```

- [ ] **Step 3: Document production activation**

1. Pin all enabled source refs.
2. Back up PostgreSQL and `/data/content-etl`.
3. Sync and inspect manifests/quarantine reports.
4. Activate core snapshots.
5. Enable `CONTENT_AGENT_ENABLED=true`.
6. Create a preview-only A1 smoke job.
7. Apply only after preview validation has zero blocking errors.
8. Keep large audio sources disabled until storage and attribution review pass.

- [ ] **Step 4: Add rollback instructions**

Deactivate a bad snapshot by repointing `active/<source>.json` to the previous
approved version. Existing jobs retain their pinned snapshot. Database apply
rollback is transaction-based; already completed courses are unpublished and
must be removed through an audited admin operation rather than automatic
destructive rollback.

### Task 16: Full verification and review gates

**Files:**
- Modify tests discovered during implementation only when required.

- [ ] **Step 1: Run AI tests**

```bash
cd ai-service
pytest tests/content_etl tests/test_content_agent_adapters.py \
  tests/test_content_agent_policies.py tests/test_content_agent_routes.py -q
```

- [ ] **Step 2: Run backend tests**

```bash
cd backend-service
pytest tests/test_content_agent_contract.py \
  tests/test_content_agent_sources.py \
  tests/test_content_agent_validation.py \
  tests/test_vocabulary_catalog.py \
  tests/test_content_agent_apply.py \
  tests/test_content_agent_uploads.py \
  tests/test_content_agent_tasks.py \
  tests/test_content_agent_routes.py -q
```

- [ ] **Step 3: Run admin tests**

```bash
cd admin-service
pnpm test
pnpm build:check
```

- [ ] **Step 4: Run required repository gates**

```bash
cd flutter-app && flutter analyze
cd ../ai-service && pytest tests/ -q
cd ../backend-service && pytest tests/ -q
```

- [ ] **Step 5: Perform security review**

Review downloader SSRF controls, archive traversal protection, decompression
limits, service-token authorization, upload attestation, log redaction,
production pin enforcement, migration safety, and DB transaction rollback.

- [ ] **Step 6: Perform final code review**

Review findings first, fix all correctness/security issues, rerun focused tests,
then rerun the full gates above. Do not enable production flags until all gates
pass.

## Acceptance Criteria

- No denied domain or unsafe crawler remains reachable from production code.
- Every enabled source has an immutable approved manifest and explicit allowed
  license.
- Re-running normalization on identical raw bytes produces identical record
  checksums and ordering.
- Invalid rows are quarantined with stable errors and never silently imported.
- Course jobs pin source snapshots and are reproducible after active versions
  change.
- Backend validation rejects every malformed property before database writes.
- Vocabulary deduplication is idempotent and safe under concurrent applies.
- All generated courses remain unpublished until explicit admin apply.
- Admin can see source license/version/status and cannot select invalid sources.
- Core lexical ETL and an A1 preview/apply smoke flow pass end to end.
