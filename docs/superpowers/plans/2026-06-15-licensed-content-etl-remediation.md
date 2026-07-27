# Licensed Content ETL Remediation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining ETL/content-agent gaps so an administrator can select an active licensed snapshot, generate a course from the exact pinned records, validate full provenance, and apply only contract-compliant data to PostgreSQL.

**Architecture:** `SnapshotStorage` is the source of truth for immutable approved datasets. The AI service exposes active snapshot descriptors and attaches exact pinned snapshots to a per-job record context; the backend proxies the catalog, persists the pins, and requires the worker to attach them before generation. The ETL CLI performs the real download-adapter-validation-storage flow, while the backend independently verifies artifact v2 and provenance before any database write.

**Tech Stack:** Python 3.11+, FastAPI, Pydantic v2, `httpx`, `defusedxml`, Typer, JSONL, SHA-256 manifests, Celery, SQLAlchemy async, PostgreSQL, React 19, TypeScript, Vitest, Docker Compose.

---

## Scope And Release Gates

This plan remediates findings from the review of commits
`7b41296^..3bfcdc1`. It is an addendum to
`docs/superpowers/plans/2026-06-15-licensed-content-etl.md`; where the two plans
conflict, this remediation plan is authoritative.

Deliver in three gated releases:

1. **Snapshot integrity:** strict contracts, exact source identities, immutable
   storage, and a real ETL command.
2. **Generation wiring:** active catalog, exact snapshot attachment, backend
   proxy, deterministic retries, and removal of the empty CEFR compatibility
   path.
3. **Apply boundary:** strict artifact/provenance validation, complete database
   mapping, admin attestation, polling, and an end-to-end test.

Do not enable `CONTENT_ETL_ENABLED` or expose content-agent generation in
production until all three release gates pass.

## Canonical Data Flow

```text
operator CLI
  -> resolve exact source URL/version/checksum
  -> SecureDownloader
  -> SourceAdapter
  -> SourceRecordV2 validation
  -> immutable normalized JSONL + manifest
  -> atomic active pointer

admin dashboard
  -> backend GET /admin/content-agent/sources
  -> AI GET /internal/content-agent/sources
  -> create job with requested source IDs
  -> backend resolves and persists exact snapshot descriptors
  -> worker POSTs descriptors to AI /jobs/{job_id}/snapshots
  -> AI verifies manifests and loads bounded normalized records
  -> generation returns artifact v2 with exact source manifest
  -> backend validates artifact against pinned descriptors
  -> explicit admin apply writes course tree + provenance transactionally
```

## File Map

### Shared contracts

- Modify `contracts/content-agent/source-record-v2.schema.json`: make the
  normalized record schema the executable validation authority.
- Modify `contracts/content-agent/course-artifact-v2.schema.json`: add strict
  snapshot manifest and vocabulary provenance definitions.
- Keep `contracts/content-agent/exercise-types-v1.json` as the canonical
  `ui_type -> type` mapping.

### AI service

- Modify `api/services/content_etl/contracts.py`: add `SourceRecordV2` and
  active snapshot descriptor models.
- Modify `api/services/content_etl/registry.py`: use exact source URL rules,
  pinned refs, and canonical paths.
- Modify `api/services/content_etl/storage.py`: verify every approved artifact,
  refuse empty snapshots, and use no-replace publication.
- Modify `api/services/content_etl/pipeline.py`: validate records through
  Pydantic and accept adapter/downloader outputs rather than prebuilt records.
- Create `api/services/content_etl/sources.py`: source-specific sync
  configuration and adapter registry.
- Modify `api/services/content_etl/cli.py`: execute the real async sync flow.
- Modify content-agent models, routes, service, store, and tests for snapshot
  catalog/attachment.

### Backend service

- Modify `app/services/content_agent_sources.py`: resolve canonical active
  descriptors and map the legacy `existing_cefr` alias to CEFR-J.
- Modify `app/services/content_agent_client.py`: attach pinned snapshots and
  preserve exact generation inputs.
- Modify `app/tasks/content_agent.py`: require snapshot attachment before
  upload ingestion or generation.
- Modify `app/routes/content_agent.py`: add the authenticated catalog proxy and
  reject unattested uploads immediately.
- Modify `app/schemas/content_agent.py`: replace open dictionaries with strict
  artifact/provenance models.
- Modify `app/services/content_agent_validation.py`: validate manifest
  coverage, licenses, hashes, exercise mapping, and pinned snapshot equality.
- Modify `app/services/content_agent_apply.py`: populate the existing
  provenance-v2 columns.

### Admin service

- Modify `src/lib/contentAgentApi.ts`: align catalog/status types and send
  upload attestation.
- Modify `ContentAgentModal.tsx`: submit the attestation and select active
  snapshots only.
- Modify `ContentAgentDrawer.tsx`: poll every backend active state.
- Extend the existing modal/drawer tests.

### Operations

- Modify `ai-service/requirements.txt` only if the runtime image still omits an
  imported direct dependency.
- Modify both AI Dockerfiles to run an ETL import smoke check.
- Modify `docs/runbooks/licensed-content-etl.md` with the tested operator flow.

## Chunk 1: Contracts And Snapshot Integrity

### Task 1: Make Source Record And Snapshot Contracts Executable

**Files:**
- Modify: `contracts/content-agent/source-record-v2.schema.json`
- Modify: `contracts/content-agent/course-artifact-v2.schema.json`
- Modify: `ai-service/api/services/content_etl/contracts.py`
- Modify: `ai-service/tests/content_etl/test_contracts.py`
- Modify: `ai-service/tests/test_content_contract_parity.py`
- Modify: `backend-service/tests/test_content_contract_parity.py`

- [ ] **Step 1: Write failing SourceRecordV2 tests**

Add tests proving that a normalized record is rejected for:

- missing source version, record ID, license, retrieval time, checksum, or
  lineage;
- an unknown property;
- a control character in text fields;
- a checksum that is not lowercase SHA-256;
- a `content_usage` whose required payload is absent;
- a source/license pair not present in the registry.

Use a valid fixture shaped like:

```python
{
    "schema_version": 2,
    "record_id": "oewn:lemma-bank-n-1",
    "source_name": "oewn",
    "source_version": "2025",
    "source_record_id": "oewn-bank-n-1",
    "source_url": "https://en-word.net/lemma/bank",
    "license_id": "CC-BY-4.0",
    "license_url": "https://creativecommons.org/licenses/by/4.0/",
    "attribution_text": "Open English WordNet 2025",
    "content_usage": "lexical",
    "language": "en",
    "word": "bank",
    "part_of_speech": "noun",
    "definition": "A financial institution.",
    "retrieved_at": "2026-06-15T00:00:00Z",
    "raw_checksum": "a" * 64,
    "record_checksum": "b" * 64,
    "lineage": {
        "adapter": "oewn",
        "adapter_version": 1,
        "raw_path": "english-wordnet-2025.xml",
        "source_location": "oewn-bank-n-1"
    }
}
```

- [ ] **Step 2: Run contract tests and verify failure**

```bash
cd ai-service
pytest tests/content_etl/test_contracts.py tests/test_content_contract_parity.py -q
cd ../backend-service
./venv/bin/pytest tests/test_content_contract_parity.py -q
```

Expected: FAIL because the pipeline currently validates only `record_id` and
the artifact schema accepts arbitrary manifest objects.

- [ ] **Step 3: Add strict Pydantic models**

Implement:

```python
class SourceRecordV2(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    schema_version: Literal[2] = 2
    record_id: str
    source_name: SourceName
    source_version: str
    source_record_id: str
    source_url: AnyHttpUrl
    license_id: AllowedLicenseId
    license_url: AnyHttpUrl
    attribution_text: str
    content_usage: ContentUsage
    language: str
    retrieved_at: datetime
    raw_checksum: str = Field(pattern=SHA256_PATTERN)
    record_checksum: str = Field(pattern=SHA256_PATTERN)
    lineage: SourceLineage
```

Add model validators for content-usage payload requirements and source/license
compatibility. Reject C0 controls except tab/newline where explicitly allowed.

- [ ] **Step 4: Define a strict artifact source manifest**

The artifact schema must require:

```text
snapshot_id, source_name, source_version, official_url,
license_id, license_url, attribution_text, retrieved_at,
raw_checksum, adapter_version, record_count
```

Set `additionalProperties: false`, `minItems: 1`, and require a lowercase
SHA-256 `generation_key`.

- [ ] **Step 5: Run contract tests**

Expected: all AI/backend parity tests pass.

- [ ] **Step 6: Commit**

```bash
git add contracts/content-agent ai-service/api/services/content_etl/contracts.py \
  ai-service/tests/content_etl/test_contracts.py \
  ai-service/tests/test_content_contract_parity.py \
  backend-service/tests/test_content_contract_parity.py
git commit -m "fix(etl): enforce source record and manifest contracts"
```

### Task 2: Lock Every Remote Source To An Exact Identity

**Files:**
- Modify: `ai-service/api/services/content_etl/registry.py`
- Modify: `ai-service/api/services/content_etl/contracts.py`
- Modify: `ai-service/api/services/content_etl/downloader.py`
- Modify: `ai-service/tests/content_etl/test_registry.py`
- Modify: `ai-service/tests/content_etl/test_downloader.py`

- [ ] **Step 1: Write failing source-substitution tests**

Prove that these are rejected:

```text
https://github.com/attacker/cmudict/archive/<ref>.tar.gz
https://raw.githubusercontent.com/attacker/olp-en-cefrj/<ref>/wordlist.csv
https://github.com/globalwordnet/other-project/releases/download/file.xml.gz
https://www.wikidata.org/wiki/Special:EntityData/../../unexpected
```

Also test percent-encoded path separators, mixed-case hosts, trailing dots,
credentials, query strings, fragments, and a moving Git ref.

- [ ] **Step 2: Run focused tests**

Run:

```bash
cd ai-service
pytest tests/content_etl/test_registry.py tests/content_etl/test_downloader.py -q
```

Expected: FAIL because current validation checks only the hostname.

- [ ] **Step 3: Replace host tuples with exact URL rules**

Use a focused rule model:

```python
@dataclass(frozen=True)
class SourceUrlRule:
    host: str
    path_pattern: Pattern[str]
    required_ref: str | None = None
```

Rules must bind each source to its official owner/repository or official
dataset path. Canonicalize host and repeatedly URL-decode the path before
matching. Reject refs equal to `main`, `master`, `latest`, or `HEAD` in write
mode.

- [ ] **Step 4: Keep redirect validation fail-closed**

Validate every redirect target against the same source-specific rule and public
IP checks. The final promoted URL must still satisfy the source rule.

- [ ] **Step 5: Run focused tests**

Expected: PASS.

- [ ] **Step 6: Security review checkpoint**

Dispatch `security-reviewer` with the registry/downloader diff. Resolve all
high-severity findings before continuing.

- [ ] **Step 7: Commit**

```bash
git add ai-service/api/services/content_etl/registry.py \
  ai-service/api/services/content_etl/contracts.py \
  ai-service/api/services/content_etl/downloader.py \
  ai-service/tests/content_etl/test_registry.py \
  ai-service/tests/content_etl/test_downloader.py
git commit -m "fix(etl): bind downloads to canonical source identities"
```

### Task 3: Make Snapshot Publication Immutable And Self-Verifying

**Files:**
- Modify: `ai-service/api/services/content_etl/contracts.py`
- Modify: `ai-service/api/services/content_etl/storage.py`
- Modify: `ai-service/tests/content_etl/test_storage.py`

- [ ] **Step 1: Write failing integrity tests**

Cover:

- approved manifest with missing `records.jsonl`;
- approved count of zero;
- normalized count differing from non-empty JSONL lines;
- more than one raw artifact without an explicit raw file manifest;
- changed raw/normalized bytes after manifest creation;
- concurrent publication of different bytes for one source/version;
- activation after raw or normalized checksum corruption.

- [ ] **Step 2: Run focused tests**

Run: `cd ai-service && pytest tests/content_etl/test_storage.py -q`

Expected: FAIL for missing normalized output, empty approval, race publication,
and activation revalidation.

- [ ] **Step 3: Record every immutable artifact**

Extend `SourceManifest` with:

```python
raw_files: list[SnapshotFile]
normalized_file: SnapshotFile
quarantine_file: SnapshotFile | None
```

Each `SnapshotFile` contains relative path, SHA-256, and byte count. Do not use
`raw_files[0]` as an implicit identity.

- [ ] **Step 4: Publish without replacement**

Use exclusive creation or a lock file scoped to `<source>/<version>`. A second
writer may return the existing file only when its checksum is identical; it
must never replace different bytes or a manifest.

- [ ] **Step 5: Revalidate before activation**

`activate()` must verify:

- approved status;
- `counts.approved > 0`;
- all manifest files exist;
- every checksum and count matches;
- the manifest snapshot ID still matches source/version/raw checksum.

Only then atomically replace the mutable active pointer.

- [ ] **Step 6: Run focused tests**

Expected: PASS, including a multiprocessing/concurrency regression test.

- [ ] **Step 7: Commit**

```bash
git add ai-service/api/services/content_etl/storage.py \
  ai-service/api/services/content_etl/contracts.py \
  ai-service/tests/content_etl/test_storage.py
git commit -m "fix(etl): make snapshot publication immutable"
```

## Chunk 2: Real ETL Execution

### Task 4: Validate Adapter Output Through SourceRecordV2

**Files:**
- Modify: `ai-service/api/services/content_etl/adapters/base.py`
- Modify: `ai-service/api/services/content_etl/adapters/oewn.py`
- Modify: `ai-service/api/services/content_etl/adapters/cmudict.py`
- Modify: `ai-service/api/services/content_etl/adapters/cefr_j.py`
- Modify: `ai-service/api/services/content_etl/adapters/wikidata.py`
- Modify: `ai-service/api/services/content_etl/adapters/tatoeba.py`
- Modify: `ai-service/api/services/content_etl/adapters/librispeech.py`
- Modify: `ai-service/api/services/content_etl/adapters/common_voice.py`
- Modify: `ai-service/api/services/content_etl/pipeline.py`
- Modify: `ai-service/tests/content_etl/test_core_adapters.py`
- Modify: `ai-service/tests/content_etl/test_corpus_adapters.py`
- Modify: `ai-service/tests/content_etl/test_pipeline.py`

- [ ] **Step 1: Write failing adapter golden tests**

Every pipeline-finalized adapter result must contain all SourceRecordV2 fields,
including `source_version`, `source_record_id`, retrieval timestamp, raw
checksum, deterministic record checksum, and lineage. Adapter-only tests assert
the source-specific draft fields; pipeline golden tests assert the complete
record. Re-running with the same timestamp/raw checksum must produce
byte-identical ordered JSONL.

- [ ] **Step 2: Run adapter and pipeline tests**

```bash
cd ai-service
pytest tests/content_etl/test_core_adapters.py \
  tests/content_etl/test_corpus_adapters.py \
  tests/content_etl/test_pipeline.py -q
```

Expected: FAIL because adapters emit partial records and `_validate_record`
checks only `record_id`.

- [ ] **Step 3: Pass sync context into adapters**

Change the protocol to:

```python
class SourceAdapter(Protocol):
    source_name: SourceName
    adapter_version: int

    def parse(
        self,
        raw_path: Path,
        *,
        source_version: str,
        raw_checksum: str,
        retrieved_at: datetime,
    ) -> Iterable[dict[str, Any]]: ...
```

Adapters parse source-specific draft fields. The pipeline adds canonical
manifest-level fields and calculates `record_checksum` from canonical JSON with
the `record_checksum` field omitted. It then inserts the digest and validates
the complete object as SourceRecordV2.

- [ ] **Step 4: Replace `_validate_record`**

Use `SourceRecordV2.model_validate(record)`. Quarantine bounded sanitized
validation errors by stable error code; never write invalid dictionaries to
normalized output.

- [ ] **Step 5: Make resume perform full validation**

`resume_from_normalized()` must stream and validate every JSONL record, reject
empty output, recompute normalized checksum/count, and enforce quarantine
thresholds before writing or activating a manifest.

- [ ] **Step 6: Run focused tests**

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ai-service/api/services/content_etl/adapters \
  ai-service/api/services/content_etl/pipeline.py \
  ai-service/tests/content_etl
git commit -m "fix(etl): validate normalized adapter records"
```

### Task 5: Implement The Actual Download-To-Activation Sync

**Files:**
- Create: `ai-service/api/services/content_etl/sources.py`
- Modify: `ai-service/api/services/content_etl/pipeline.py`
- Modify: `ai-service/api/services/content_etl/cli.py`
- Modify: `ai-service/api/core/config.py`
- Modify: `ai-service/.env.example`
- Modify: `ai-service/tests/content_etl/test_pipeline.py`
- Create: `ai-service/tests/content_etl/test_cli.py`

- [ ] **Step 1: Write failing orchestration tests**

Using `httpx.MockTransport`, prove that `sync --write`:

1. resolves an exact configured version/ref and URL;
2. downloads through `SecureDownloader`;
3. invokes the registered adapter;
4. validates/quarantines records;
5. writes an approved manifest;
6. activates only after all checks pass;
7. exits non-zero and leaves the old active pointer unchanged on failure.

- [ ] **Step 2: Run focused tests**

Run:

```bash
cd ai-service
pytest tests/content_etl/test_pipeline.py tests/content_etl/test_cli.py -q
```

Expected: FAIL because `sync --write` currently prints a placeholder.

- [ ] **Step 3: Add source sync definitions**

`sources.py` owns the adapter registry and source-specific sync descriptor:

```python
@dataclass(frozen=True)
class SourceSyncSpec:
    source_name: SourceName
    source_version: str
    download_url: str
    expected_sha256: str | None
    raw_member: str | None
    adapter: SourceAdapter
    license_id: AllowedLicenseId
    license_url: str
```

Resolve values from settings. Production write mode requires a pinned version
or immutable ref and, where the provider publishes one, an expected checksum.

- [ ] **Step 4: Add one orchestration entrypoint**

Implement:

```python
async def sync_source(
    spec: SourceSyncSpec,
    *,
    downloader: SecureDownloader,
    storage: SnapshotStorage,
    dry_run: bool,
) -> PipelineReport:
    ...
```

The function must be the only path used by the CLI for remote sources. Archive
extraction remains bounded by the existing archive safety helper.

- [ ] **Step 5: Execute it from Typer**

Use `asyncio.run()` at the CLI boundary. `--write` must persist and activate;
dry-run may resolve and validate configuration but must not create raw,
normalized, manifest, or active files.

- [ ] **Step 6: Add CLI exit semantics**

Return non-zero when any selected source fails. Print source, version, counts,
quarantine ratio, snapshot ID, and activation status without printing record
bodies or signed URLs.

- [ ] **Step 7: Run tests and CLI smoke checks**

```bash
cd ai-service
pytest tests/content_etl/test_pipeline.py tests/content_etl/test_cli.py -q
python -m api.services.content_etl.cli list
python -m api.services.content_etl.cli sync --sources oewn
```

Expected: tests pass; dry-run performs no writes.

- [ ] **Step 8: Commit**

```bash
git add ai-service/api/services/content_etl/sources.py \
  ai-service/api/services/content_etl/pipeline.py \
  ai-service/api/services/content_etl/cli.py \
  ai-service/api/core/config.py ai-service/.env.example \
  ai-service/tests/content_etl
git commit -m "fix(etl): execute licensed source sync end to end"
```

## Chunk 3: Snapshot Catalog And Generation Wiring

### Task 6: Expose Active Snapshots And Attach Exact Records In AI

**Files:**
- Modify: `ai-service/api/models/content_agent.py`
- Modify: `ai-service/api/services/content_agent/store.py`
- Modify: `ai-service/api/services/content_agent/service.py`
- Modify: `ai-service/api/routes/content_agent.py`
- Modify: `ai-service/tests/test_content_agent_routes.py`
- Modify: `ai-service/tests/test_content_agent_adapters.py`

- [ ] **Step 1: Write failing catalog and attachment tests**

Test:

- catalog excludes registered sources with no active approved snapshot;
- each entry contains `source_id`, `source_name`, `source_version`,
  `snapshot_id`, license fields, attribution, record count, retrieval time,
  `status="active"`, and `enabled`;
- attach rejects unknown, rejected, mismatched, or corrupted snapshots;
- attach can load an older approved pin even after the active pointer changes;
- attached records are bounded by `CONTENT_AGENT_MAX_RECORDS`;
- generate cannot run until at least one snapshot/upload record is attached.

- [ ] **Step 2: Replace the activation-shaped job endpoint**

Use:

```text
GET  /api/v1/internal/content-agent/sources
POST /api/v1/internal/content-agent/jobs/{job_id}/snapshots
```

Request:

```json
{
  "snapshots": [
    {
      "source_id": "oewn",
      "source_version": "2025",
      "snapshot_id": "oewn:2025:<sha256>"
    }
  ]
}
```

The POST endpoint attaches records to the job; it must never mutate the global
active pointer.

- [ ] **Step 3: Read catalog entries from storage**

Iterate active pointers, load and verify their manifests, and return sanitized
descriptors. A broken active pointer is omitted and logged; it is not presented
as selectable.

- [ ] **Step 4: Stream normalized records into the job context**

Verify exact manifest identity, stream JSONL, validate each record again, and
append in bounded batches. Persist attached descriptors with the job context so
generation can emit the exact source manifest.

- [ ] **Step 5: Remove the empty CEFR fallback**

Delete `_load_cached_existing_cefr_mapping()` and do not fabricate
`dataset:approved-cefr-j-snapshot` records. CEFR labels must come from an
attached CEFR-J snapshot.

- [ ] **Step 6: Generate provenance from attached descriptors**

Artifact `source_manifest` must be copied from verified snapshot descriptors,
not reconstructed from the old policy registry or record counts.

- [ ] **Step 7: Run focused tests**

```bash
cd ai-service
pytest tests/test_content_agent_routes.py \
  tests/test_content_agent_adapters.py \
  tests/content_etl/test_storage.py -q
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add ai-service/api/models/content_agent.py \
  ai-service/api/services/content_agent \
  ai-service/api/routes/content_agent.py \
  ai-service/tests/test_content_agent_routes.py \
  ai-service/tests/test_content_agent_adapters.py
git commit -m "fix(content-agent): attach immutable ETL snapshots"
```

### Task 7: Wire Backend Catalog, Pinning, And Worker Attachment

**Files:**
- Modify: `backend-service/app/services/content_agent_sources.py`
- Modify: `backend-service/app/services/content_agent_client.py`
- Modify: `backend-service/app/tasks/content_agent.py`
- Modify: `backend-service/app/routes/content_agent.py`
- Modify: `backend-service/app/schemas/content_agent.py`
- Modify: `backend-service/tests/test_content_agent_sources.py`
- Modify: `backend-service/tests/test_content_agent_routes.py`
- Modify: `backend-service/tests/test_content_agent_tasks.py`
- Modify: `backend-service/tests/test_content_agent_jobs.py`

- [ ] **Step 1: Write failing backend flow tests**

Cover:

- authenticated `GET /admin/content-agent/sources`;
- canonical pass-through of active descriptors;
- inactive/malformed descriptors rejected;
- `existing_cefr` resolves to the active CEFR-J descriptor;
- new jobs default to `cefr_j`, not `existing_cefr`;
- retry reuses stored pins even if the active catalog changes;
- worker calls `attach_snapshots()` during `loading_snapshots`;
- generation is not called when attachment fails;
- `pinned_snapshots` participate in the request hash.

- [ ] **Step 2: Run focused tests**

```bash
cd backend-service
./venv/bin/pytest tests/test_content_agent_sources.py \
  tests/test_content_agent_routes.py \
  tests/test_content_agent_tasks.py \
  tests/test_content_agent_jobs.py -q
```

Expected: FAIL because the backend route and client attachment method do not
exist.

- [ ] **Step 3: Define one backend descriptor model**

```python
class SourceSnapshotDescriptor(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_id: str
    source_name: str
    source_version: str
    snapshot_id: str
    license_id: str
    license_url: AnyHttpUrl
    attribution_text: str
    record_count: int = Field(gt=0)
    retrieved_at: datetime
    status: Literal["active"]
    enabled: bool
```

Validate AI responses before proxying or pinning them.

- [ ] **Step 4: Make legacy CEFR an alias, not a virtual source**

Keep `admin_upload` as the only virtual source. Resolve `existing_cefr` by
looking up `cefr_j`, store the canonical descriptor, and send canonical
generation sources. Default all new requests to `cefr_j`.

- [ ] **Step 5: Add catalog proxy**

Add:

```text
GET /api/v1/admin/content-agent/sources
```

It depends on `get_current_admin`, calls the authenticated AI client, validates
the response, and returns no storage paths or internal errors.

- [ ] **Step 6: Attach before generation**

Add `ContentAgentClient.attach_snapshots(job_id, descriptors)`. During
`loading_snapshots`, call it with every non-virtual pinned descriptor. Do not
strip pins from generation state; the worker and validator must retain them for
comparison.

- [ ] **Step 7: Run focused tests**

Expected: PASS.

- [ ] **Step 8: Security review checkpoint**

Dispatch `security-reviewer` for the new admin route, service-token call, and
snapshot request validation.

- [ ] **Step 9: Commit**

```bash
git add backend-service/app/services/content_agent_sources.py \
  backend-service/app/services/content_agent_client.py \
  backend-service/app/tasks/content_agent.py \
  backend-service/app/routes/content_agent.py \
  backend-service/app/schemas/content_agent.py \
  backend-service/tests/test_content_agent_sources.py \
  backend-service/tests/test_content_agent_routes.py \
  backend-service/tests/test_content_agent_tasks.py \
  backend-service/tests/test_content_agent_jobs.py
git commit -m "fix(content-agent): wire snapshot catalog and attachment"
```

## Chunk 4: Apply Boundary And Admin Reliability

### Task 8: Enforce Artifact V2 And Persist Complete Provenance

**Files:**
- Modify: `backend-service/app/schemas/content_agent.py`
- Modify: `backend-service/app/services/content_agent_validation.py`
- Modify: `backend-service/app/services/content_agent_apply.py`
- Modify: `backend-service/tests/test_content_agent_validation.py`
- Modify: `backend-service/tests/test_content_agent_apply.py`
- Modify: `backend-service/tests/test_content_agent_contract.py`

- [ ] **Step 1: Write a failing boundary matrix**

Reject artifacts with:

- malformed or empty source manifest;
- manifest snapshot not present in `job.config.pinned_snapshots`;
- mismatched version, license, attribution, or raw checksum;
- vocabulary source absent from manifest;
- missing record checksum/lineage for imported vocabulary;
- invalid `ui_type -> type` mapping;
- non-SHA generation key;
- duplicate/non-contiguous course, unit, or lesson order;
- answer missing from multiple-choice options;
- speaking/listening exercise missing canonical text;
- totals inconsistent with generated entities.

- [ ] **Step 2: Run focused tests**

```bash
cd backend-service
./venv/bin/pytest tests/test_content_agent_validation.py \
  tests/test_content_agent_apply.py \
  tests/test_content_agent_contract.py -q
```

Expected: FAIL because manifest/provenance fields are open dictionaries and
the validator currently checks only shallow presence.

- [ ] **Step 3: Replace open dictionaries with strict models**

Add `ArtifactSourceManifest` and vocabulary provenance fields to the Pydantic
artifact. Imported vocabulary must carry:

```text
source_name, source_version, source_url, license_id, license_url,
attribution_text, raw_checksum, record_checksum, lineage, content_usage
```

Generated vocabulary uses `LicenseRef-Generated` and explicit
`is_generated=true`; it must not pretend to originate from a dataset.

- [ ] **Step 4: Load canonical exercise mapping**

Parse `contracts/content-agent/exercise-types-v1.json` once through a cached
structured loader. Reject any UI type absent from the map or paired with the
wrong base type.

- [ ] **Step 5: Compare artifact to job pins**

Change the validator entrypoint to accept the pinned descriptors:

```python
validate_artifact(
    artifact: dict[str, Any],
    *,
    pinned_snapshots: list[dict[str, Any]],
) -> ValidationReport
```

Apply must call this validator while holding the job lock and abort before
creating any entity when blocking errors exist.

- [ ] **Step 6: Populate provenance-v2 columns**

Map all existing columns on `ContentProvenance`:

```text
source_version, license_id, license_url, attribution_text,
raw_checksum, record_checksum, lineage, content_usage,
rights_confirmed_at
```

For `admin_upload`, copy attestation timestamp from the upload. Keep legacy
`license_mode/source_checksum` only for backward-compatible reads.

- [ ] **Step 7: Run focused tests**

Expected: PASS, including rollback assertions proving no course/vocabulary/
provenance rows survive an invalid apply.

- [ ] **Step 8: Commit**

```bash
git add backend-service/app/schemas/content_agent.py \
  backend-service/app/services/content_agent_validation.py \
  backend-service/app/services/content_agent_apply.py \
  backend-service/tests/test_content_agent_validation.py \
  backend-service/tests/test_content_agent_apply.py \
  backend-service/tests/test_content_agent_contract.py
git commit -m "fix(content-agent): enforce provenance at apply boundary"
```

### Task 9: Fix Upload Attestation, Catalog Semantics, And Polling

**Files:**
- Modify: `admin-service/src/lib/contentAgentApi.ts`
- Modify: `admin-service/src/components/content-agent/ContentAgentModal.tsx`
- Modify: `admin-service/src/components/content-agent/ContentAgentDrawer.tsx`
- Modify: `admin-service/src/components/content-agent/ContentAgentModal.test.tsx`
- Modify: `admin-service/src/components/content-agent/ContentAgentDrawer.test.tsx`
- Modify: `backend-service/app/routes/content_agent.py`
- Modify: `backend-service/tests/test_content_agent_uploads.py`
- Modify: `backend-service/tests/test_content_agent_routes.py`

- [ ] **Step 1: Write failing UI/API tests**

Test:

- checked attestation calls
  `/uploads?rights_confirmed=true`;
- unchecked upload never sends a request;
- backend rejects unattested uploads at upload time with `422`;
- only `status="active"` snapshots are selectable;
- `resolving_sources`, `loading_snapshots`, and `normalizing_upload` are active
  polling states;
- polling continues through every durable backend stage and stops at
  preview/completed/failed/cancelled.

- [ ] **Step 2: Run focused tests**

```bash
cd admin-service
npm exec --offline vitest -- run \
  src/components/content-agent/ContentAgentModal.test.tsx \
  src/components/content-agent/ContentAgentDrawer.test.tsx
cd ../backend-service
./venv/bin/pytest tests/test_content_agent_uploads.py \
  tests/test_content_agent_routes.py -q
```

Expected: FAIL for attestation query, catalog status mismatch, and missing
polling states.

- [ ] **Step 3: Send attestation explicitly**

Change:

```typescript
uploadContentAgentFile(file, { rightsConfirmed: true })
```

Build the query with `URLSearchParams`; do not encode the attestation only in
client state.

- [ ] **Step 4: Reject unattested upload immediately**

The backend upload route must return `422` before parsing/persisting when
`rights_confirmed` is false. Do not permit a job that is guaranteed to fail
later in the worker.

- [ ] **Step 5: Align catalog and job status types**

Use `status: "active"` for selectable snapshots and add:

```text
resolving_sources, loading_snapshots, normalizing_upload
```

to `CONTENT_AGENT_ACTIVE_STATUSES`. Remove obsolete
`extracting/normalizing` unless the backend still emits them.

- [ ] **Step 6: Run frontend/backend tests and TypeScript build**

```bash
cd admin-service
npm exec --offline vitest -- run \
  src/components/content-agent/ContentAgentModal.test.tsx \
  src/components/content-agent/ContentAgentDrawer.test.tsx
npm exec --offline tsc -- -b
cd ../backend-service
./venv/bin/pytest tests/test_content_agent_uploads.py \
  tests/test_content_agent_routes.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add admin-service/src/lib/contentAgentApi.ts \
  admin-service/src/components/content-agent/ContentAgentModal.tsx \
  admin-service/src/components/content-agent/ContentAgentDrawer.tsx \
  admin-service/src/components/content-agent/ContentAgentModal.test.tsx \
  admin-service/src/components/content-agent/ContentAgentDrawer.test.tsx \
  backend-service/app/routes/content_agent.py \
  backend-service/tests/test_content_agent_uploads.py \
  backend-service/tests/test_content_agent_routes.py
git commit -m "fix(content-agent): align admin ETL workflow"
```

## Chunk 5: End-To-End Verification And Operations

### Task 10: Prove The Licensed Course Flow And Close Runtime Gaps

**Files:**
- Create: `ai-service/tests/integration/test_licensed_etl_content_agent_flow.py`
- Create: `backend-service/tests/integration/test_content_agent_licensed_etl_flow.py`
- Create: `contracts/content-agent/fixtures/licensed-etl-artifact-v2.json`
- Modify: `ai-service/requirements.txt`
- Modify: `ai-service/Dockerfile`
- Modify: `ai-service/Dockerfile.prod`
- Modify: `docs/runbooks/licensed-content-etl.md`

- [ ] **Step 1: Add service-level integration tests and one shared artifact**

The AI integration test creates a tiny approved CEFR-J/OEWN snapshot through
the real pipeline using local fixtures, activates it, fetches the catalog,
attaches exact records, and generates an artifact. Store the expected sanitized
artifact as the shared v2 fixture.

The backend integration test serves that fixture through mocked AI HTTP
boundaries, resolves and persists exact pins, validates the artifact, applies
one draft course, asserts every provenance-v2 column, retries, and proves the
same snapshot/generation key is reused.

Do not import AI application modules into the backend test process and do not
download internet datasets in CI.

- [ ] **Step 2: Add runtime import smoke checks**

The AI image build must run:

```bash
python -c "import defusedxml, typer; from api.services.content_etl.cli import app"
```

Ensure direct imports are explicit requirements:

```text
defusedxml>=0.7.1
typer>=0.24.1,<1
```

Rebuild the environment before accepting the seven currently failing OEWN
tests.

- [ ] **Step 3: Run the full focused verification suite**

```bash
cd ai-service
pytest tests/content_etl \
  tests/integration/test_licensed_etl_content_agent_flow.py \
  tests/test_content_agent_routes.py \
  tests/test_content_agent_adapters.py \
  tests/test_content_agent_policies.py \
  tests/test_content_contract_parity.py -q

cd ../backend-service
DEBUG=false ./venv/bin/pytest \
  tests/test_content_agent_sources.py \
  tests/test_content_agent_validation.py \
  tests/test_content_agent_apply.py \
  tests/test_vocabulary_catalog.py \
  tests/test_content_agent_routes.py \
  tests/test_content_agent_tasks.py \
  tests/test_content_agent_uploads.py \
  tests/test_content_contract_parity.py \
  tests/integration/test_content_agent_licensed_etl_flow.py -q

cd ../admin-service
npm exec --offline vitest -- run \
  src/components/content-agent/ContentAgentModal.test.tsx \
  src/components/content-agent/ContentAgentDrawer.test.tsx
npm exec --offline tsc -- -b

cd ..
git diff --check
```

Expected: all commands pass with no skipped critical-flow test.

- [ ] **Step 4: Run migration and container smoke checks**

```bash
cd backend-service
alembic upgrade head
cd ..
docker compose config
docker compose -f docker-compose.production.yml config
```

Expected: migration reaches head and both Compose files validate.

- [ ] **Step 5: Update the runbook**

Document:

- exact pin/checksum configuration;
- dry-run and `--write` commands;
- expected catalog output;
- how to inspect manifests/quarantine without editing snapshot files;
- rollback with the validated `content-etl activate` command targeting another
  approved snapshot;
- dashboard preview/apply flow;
- incident response for checksum, license, or provenance failures.

- [ ] **Step 6: Agent review sequence**

1. Spawn `test-writer` to inspect coverage and add missing edge cases.
2. Spawn `security-reviewer` for URLs, filesystem publication, service-token
   endpoints, uploads, and apply validation.
3. Spawn `code-reviewer` for the complete remediation range.
4. Resolve all critical/high findings and rerun the full suite.

- [ ] **Step 7: Commit**

```bash
git add backend-service/tests/integration/test_content_agent_licensed_etl_flow.py \
  ai-service/tests/integration/test_licensed_etl_content_agent_flow.py \
  contracts/content-agent/fixtures/licensed-etl-artifact-v2.json \
  ai-service/requirements.txt ai-service/Dockerfile ai-service/Dockerfile.prod \
  docs/runbooks/licensed-content-etl.md
git commit -m "test(etl): verify licensed course generation flow"
```

## Definition Of Done

- `sync --write` downloads, adapts, validates, persists, and activates a real
  approved snapshot; no placeholder branch remains.
- Every normalized row validates as SourceRecordV2 before storage.
- Remote URLs are bound to exact official source identities and immutable refs.
- Approved snapshots are non-empty, immutable, checksummed, and reverified on
  activation.
- The AI catalog exposes only active verified snapshots.
- A content-agent job attaches its exact persisted pins before generation and
  retries never silently switch snapshots.
- `existing_cefr` cannot bypass CEFR-J approval and is not the default source.
- The backend catalog route is admin-authenticated.
- Upload attestation is transmitted and enforced before persistence.
- Artifact apply rejects missing/mismatched provenance and invalid exercise
  mappings before any database write.
- All provenance-v2 columns are populated for imported content.
- Admin polling covers every durable backend stage.
- AI, backend, admin, integration, migration, Compose, and diff checks pass.

## Rollback Strategy

- Keep all feature flags disabled during migration and verification.
- Each task is a separate commit and can be reverted independently before
  production enablement.
- Never delete or edit an approved snapshot during rollback. Run
  `content-etl activate --source <source> --version <approved-version>` so the
  same integrity verification executes before the active pointer changes.
- Existing applied courses remain drafts; remove or archive them through the
  normal admin workflow rather than deleting provenance rows manually.
