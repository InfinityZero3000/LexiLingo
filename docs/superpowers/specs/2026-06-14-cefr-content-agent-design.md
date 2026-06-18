# CEFR Content Agent Design

## Goal

Add a compliance-first content agent that can build draft English courses from
CEFR A1-C2 data, uploaded CSV/JSON files, and versioned official datasets with
explicit commercial-use rights.
Administrators can start and monitor the agent from the Courses dashboard, while
operators can run the same pipeline from a CLI with dry-run and resume support.

The agent must:

1. ingest and normalize source records;
2. classify records by CEFR level and topic;
3. prevent duplicate vocabulary;
4. plan courses, units, and lessons;
5. generate speaking and listening exercises;
6. validate a complete preview;
7. save an approved preview to PostgreSQL in one idempotent operation.

Generated courses remain unpublished until an administrator explicitly reviews
and applies the preview.

## Scope

The feature is delivered in three rollout stages:

1. Core pipeline, CLI, dashboard, existing validated records, and CSV/JSON
   uploads.
2. Official lexical datasets: Open English WordNet, CMUdict, CEFR-J through the
   Open Language Profiles repository, and Wikidata topic metadata.
3. Sentence and audio corpora: license-filtered Tatoeba, LibriSpeech, and
   Common Voice datasets whose release metadata explicitly declares an allowed
   license.

The agent creates structured course content. It does not automatically publish a
course, bypass an administrator's review, crawl arbitrary user-provided URLs, or
copy restricted lesson text into LexiLingo.

## Architecture

The feature uses a layered pipeline:

```text
CLI or Admin API
        |
        v
Backend Content Job Service ---- PostgreSQL job state
        |
        v
Celery Content Agent Task
        |
        +---- AI Service ETL and generation endpoint
        |       Extract -> Normalize -> Policy -> CEFR -> Plan -> Generate -> QA
        |
        v
Validated Course Artifact
        |
        +---- Dry-run preview
        |
        v
Backend transactional apply
        |
        v
Course + Units + Lessons + Vocabulary + Provenance
```

### Service ownership

`ai-service` owns:

- source adapters and normalized source records;
- CEFR/topic classification and confidence scoring;
- course, unit, lesson, and exercise planning;
- LLM prompts and structured-output validation;
- source-policy filtering before any source text reaches generation;
- generation of a versioned course artifact.

`backend-service` owns:

- authenticated admin endpoints;
- upload validation;
- persistent job state and audit information;
- Celery task dispatch and retry coordination;
- vocabulary deduplication against PostgreSQL;
- preview validation against backend schemas;
- idempotent transaction boundaries and database writes.

`admin-service` owns:

- agent configuration controls;
- upload and source selection;
- job progress, errors, preview, approval, retry, and cancellation UI.

The backend calls the AI service through the configured gateway URL. The AI
service never receives PostgreSQL credentials and never writes course data
directly. Dataset extraction runs in the AI service, but production database
writes remain owned by the backend apply service.

## Job Lifecycle

The persistent job state machine is:

```text
queued
  -> extracting
  -> normalizing
  -> classifying
  -> planning
  -> generating
  -> validating
  -> preview_ready
  -> applying
  -> completed
```

Terminal alternatives are `failed` and `cancelled`.

Retry resumes from the latest durable artifact boundary. Applying a
`preview_ready` job is separately authorized and is idempotent: repeating the
apply request returns the original created course IDs rather than creating
duplicates.

Each job stores:

- requesting administrator ID;
- normalized request configuration;
- source manifest and policy snapshot;
- current stage, percentage, counters, and timestamps;
- deterministic request hash and prompt/artifact versions;
- structured preview artifact;
- validation warnings and blocking errors;
- Celery task ID;
- created entity IDs after apply;
- sanitized error details.

Only one active job with the same request hash is allowed by default. An
administrator must explicitly request a new revision to run the same material
and configuration again.

Uploaded source data is stored in a separate `content_agent_uploads` table as
validated JSON, with uploader ID, checksum, row count, schema version, and
expiry timestamp. Raw uploads are deleted after parsing. Upload records expire
after seven days unless referenced by a non-terminal job, which makes worker
restart/resume possible without permanent file storage.

## Input Modes

### Existing CEFR data

The legacy `existing_cefr` source remains as a temporary compatibility alias
only while the new CEFR-J snapshot is imported. It must not read the current
third-party Oxford list or the `leomauro/cefr-j` mirror.

The replacement adapter downloads CEFR-J from the Open Language Profiles
repository, pins a commit SHA, stores the accompanying permission notice, and
records the required citation. Only the files covered by CEFR-J's explicit
research and commercial-use grant are accepted. The Octanove C1/C2 profile and
other ShareAlike files in the repository are excluded.

### CSV/JSON upload

Accepted CSV columns:

```text
word,part_of_speech,cefr_level,definition,translation_vi,example,topic,source_url
```

Accepted JSON is either an array of equivalent objects or:

```json
{
  "records": [],
  "source_name": "admin_upload",
  "license_id": "LicenseRef-Admin-Owned",
  "rights_confirmed": true
}
```

Uploads are limited to UTF-8 `.csv` and `.json`, five megabytes, and 20,000
records. Parsing happens before a job is queued. Invalid rows are reported with
row numbers and do not silently disappear. The administrator must attest that
the organization owns the upload or may use it commercially.

### Official dataset adapters

Production ETL is dataset-first. It downloads only official release artifacts,
dumps, or documented APIs. It does not crawl HTML pages and the dashboard never
accepts arbitrary URLs.

| Source ID | Default state | License gate | Allowed data |
| --- | --- | --- | --- |
| `oewn` | enabled | CC BY 4.0 | lemma, part of speech, definitions, lexical relations |
| `cmudict` | enabled | explicit unrestricted commercial use | ARPAbet pronunciation |
| `cefr_j` | enabled | explicit commercial-use grant plus citation | CEFR labels only |
| `wikidata` | enabled | CC0 | topic/category identifiers and labels |
| `tatoeba` | opt-in | CC0 or CC BY rows only | example sentences and eligible audio metadata |
| `librispeech` | opt-in | CC BY 4.0 | English audio and transcripts |
| `common_voice` | opt-in | release metadata must be CC0-1.0 | English audio and transcripts |
| `admin_upload` | enabled | administrator ownership attestation | validated CSV/JSON fields |

Every adapter is pinned to a version, commit, or release identifier. Each run
stores an immutable source manifest containing the official URL, retrieval
timestamp, actual SHA-256, publisher/operator expected SHA-256 when available,
license ID and URL, attribution text, adapter version, record counts, and
validation report.

The following sources are denied by the default registry and removed from the
dashboard and crawler configuration:

- BBC Learning English, British Council LearnEnglish, Cambridge English,
  Cambridge Dictionary, Oxford Learner's Dictionaries, VOA Learning English,
  DOL English, PREP, The IELTS Workshop, IELTS Liz, EnglishClub, Grammar
  Monster, and Perfect English Grammar;
- third-party Oxford and CEFR mirrors;
- Wiktionary/Kaikki and ConceptNet because their ShareAlike obligations are
  outside the approved license policy;
- EFLLex because its license prohibits commercial use.

An excluded source can return only through a new design review and explicit
legal approval. `robots.txt` permission alone is never considered a content
license.

Official references:

- Open English WordNet: <https://github.com/globalwordnet/english-wordnet>
- CMUdict: <https://github.com/cmusphinx/cmudict>
- CEFR-J Open Language Profiles:
  <https://github.com/openlanguageprofiles/olp-en-cefrj>
- Tatoeba downloads: <https://tatoeba.org/en/downloads>
- LibriSpeech: <https://www.openslr.org/12>
- Common Voice datasets:
  <https://datacollective.mozillafoundation.org/datasets>
- Wikidata data access:
  <https://www.wikidata.org/wiki/Wikidata:Data_access>

## Normalized Source Contract

Every adapter produces normalized contract version 2:

```json
{
  "schema_version": 2,
  "record_id": "oewn:2025:stable-id",
  "source_name": "oewn",
  "source_version": "2025",
  "source_record_id": "stable-id",
  "source_url": "https://github.com/globalwordnet/english-wordnet",
  "license_id": "CC-BY-4.0",
  "license_url": "https://creativecommons.org/licenses/by/4.0/",
  "attribution_text": "Open English WordNet 2025",
  "content_usage": "lexical",
  "language": "en",
  "word": "example",
  "lemma": "example",
  "part_of_speech": "noun",
  "definition": "A representative form or pattern.",
  "translation_vi": null,
  "example": null,
  "pronunciation": null,
  "audio": null,
  "declared_cefr": null,
  "assigned_cefr": "A2",
  "classification_confidence": 0.82,
  "topic_ids": ["wikidata:Q..."],
  "retrieved_at": "2026-06-15T00:00:00Z",
  "raw_checksum": "sha256...",
  "record_checksum": "sha256...",
  "lineage": {
    "adapter": "oewn",
    "adapter_version": 1,
    "raw_path": "raw/oewn/2025/english-wordnet-2025.xml.gz"
  }
}
```

Unknown fields are forbidden. Strings are Unicode-normalized, bounded, and
control characters are rejected. URLs must use HTTPS or an approved internal
object-storage scheme. `license_id`, `source_version`, attribution, checksums,
language, and lineage are required for dataset records.

Records pass through `raw`, `normalized`, `quarantine`, and `approved` states.
Invalid rows are quarantined with stable error codes and row/source locations;
they never silently disappear. Restricted fields are removed before temporary
persistence and before LLM invocation.

The approved license IDs are `CC0-1.0`, `CC-BY-2.0-FR`, `CC-BY-4.0`,
`LicenseRef-CMUdict`, the pinned CEFR-J commercial permission,
`LicenseRef-Admin-Owned`, and `LicenseRef-Generated`. CC BY-SA, CC BY-NC,
unknown, missing, or mismatched licenses fail closed.

`content_usage` is one of `lexical`, `pronunciation`, `label`, `topic`,
`example`, or `audio`. Each usage has its own required and forbidden fields.

## CEFR and Curriculum Rules

The agent supports all six levels: A1, A2, B1, B2, C1, and C2.

Classification priority:

1. trusted declared CEFR from an approved CEFR dataset;
2. agreement among two source labels;
3. local classifier/LLM estimate with confidence;
4. reject for manual review when confidence is below the configured threshold.

The default generation creates one draft course per selected CEFR level. Units
are topic-based and lessons contain 8-12 vocabulary targets, with 10 as the
default. A vocabulary item may appear in multiple lessons when pedagogically
useful, but it exists only once in the master vocabulary catalog.

Default lesson exercise mix:

- two speaking exercises using `speaking_repeat` or
  `pronunciation_practice`;
- two listening exercises using `dictation` or `listen_and_choose`;
- six vocabulary, comprehension, matching, translation, or grammar exercises.

For listening exercises, `correct_answer` is also the canonical text-to-speech
input. The current Flutter widgets already synthesize that field on demand, so
persistent generated audio is optional. If a licensed or generated `audio_url`
exists, it may be included without changing the exercise contract.

Every exercise must have:

- a stable ID;
- a supported `type` and `ui_type`;
- a non-empty question and correct answer;
- valid option shape for choice/matching exercises;
- CEFR-appropriate language;
- no copied restricted source text;
- no answer leakage in the visible prompt.

## Course Artifact

The AI service returns a versioned artifact containing one course per selected
level:

```json
{
  "schema_version": 2,
  "prompt_version": "cefr-course-v2",
  "generation_key": "sha256...",
  "source_manifest": [],
  "courses": [
    {
      "title": "English A1 Foundations",
      "description": "...",
      "language": "en",
      "level": "A1",
      "tags": ["generated", "cefr", "A1"],
      "units": [
        {
          "title": "Daily Life",
          "order_index": 1,
          "lessons": [
            {
              "title": "Morning Routine",
              "order_index": 1,
              "vocabulary": [],
              "exercises": []
            }
          ]
        }
      ]
    }
  ],
  "quality": {
    "blocking_errors": [],
    "warnings": [],
    "metrics": {}
  }
}
```

The backend validates this artifact independently. AI-service validation is not
trusted as the database boundary.

The backend sends source records to the AI service in bounded batches and then
requests final planning/generation for the accumulated job context. The
AI-service internal endpoints are authenticated with a dedicated
`CONTENT_AGENT_SERVICE_TOKEN`, use job-scoped temporary state with a TTL, and
never expose their operations to the admin browser.

Internal AI endpoints:

```text
GET    /api/v1/internal/content-agent/sources
POST   /api/v1/internal/content-agent/jobs/{job_id}/snapshots
POST   /api/v1/internal/content-agent/jobs/{job_id}/records
POST   /api/v1/internal/content-agent/jobs/{job_id}/generate
DELETE /api/v1/internal/content-agent/jobs/{job_id}
```

If AI temporary state expires, the backend replays the validated source batches
from its persisted upload/source artifact before retrying generation.

## Vocabulary Deduplication

Canonical vocabulary identity remains `(normalized_word, part_of_speech)`,
matching the existing unique constraint. The normalized word is stored in
`VocabularyItem.word`; display variants remain in provenance metadata.

Normalization:

- Unicode-aware case folding;
- trim and collapse whitespace;
- normalize apostrophes and hyphens;
- reject punctuation-only or empty values;
- do not automatically merge different lemmas or parts of speech.

When a vocabulary item already exists, the apply service:

- reuses its ID;
- fills missing optional fields only;
- does not overwrite a curated definition, translation, pronunciation, or
  audio URL with generated data;
- records the new lesson relationship and provenance.

The current single `VocabularyItem.lesson_id` cannot represent reuse across
lessons. Add a `lesson_vocabulary_items` junction table containing
`lesson_id`, `vocabulary_id`, `order_index`, `is_primary`, and `source_job_id`,
with a unique constraint on `(lesson_id, vocabulary_id)`.

Existing `course_id` and `lesson_id` columns remain as legacy origin fields for
API compatibility. New agent code reads lesson membership from the junction
table.

## Production Database Contract

Only a backend-validated `ContentAgentArtifact` may enter production tables.
The apply validator enforces the following mapping:

| Target | Required properties and invariants |
| --- | --- |
| `courses` | non-empty title; `language="en"`; level in A1-C2; normalized tag object with unique string arrays; `is_published=false`; totals equal child records |
| `units` | non-empty title; zero-based `order_index` unique within the course; `total_lessons` equals persisted lessons |
| `lessons` | non-empty title; zero-based `order_index` unique within the unit; supported `lesson_type`; pass threshold 0-100; positive duration; totals equal exercise JSON |
| `vocabulary_items` | canonical word; non-empty definition; allowed part-of-speech and CEFR enums; valid translation object; bounded pronunciation/audio URL; unique `(word, part_of_speech)` |
| `lesson_vocabulary_items` | existing lesson and vocabulary IDs; unique pair; contiguous order; source job linkage |
| `lessons.content` | object with `version`, `generated_by`, and non-empty `exercises`; exercise IDs unique within the lesson |
| `content_provenance` | job/entity/source IDs, license ID, source version, checksums, attribution, lineage, and generated/derived flag |

Exercise `type` must be one of `multiple_choice`, `true_false`, `fill_blank`,
`translate`, `matching`, or `reorder`. `ui_type` must be in the admin/mobile
registry. `dictation` and `listen_and_choose` require canonical listening text;
`speaking_repeat` and `pronunciation_practice` require canonical speaking text.
Choice exercises require well-formed options and exactly one answer. Matching
and reorder exercises require type-specific option shapes.

Warnings may pass to preview, but any missing required property, unsupported
enum, invalid license, duplicate order/index/ID, checksum mismatch, malformed
exercise, or cross-table total mismatch is a blocking error.

## Database Apply

The apply operation runs in one PostgreSQL transaction:

1. lock the job and confirm it is `preview_ready`;
2. validate artifact schema version, source manifests, license IDs, checksums,
   uniqueness, field lengths, enums, URLs, and exercise shapes;
3. confirm it has not already been applied;
4. create draft course, units, and lessons;
5. upsert vocabulary by normalized word and part of speech;
6. preserve curated fields and fill only missing values from approved sources;
7. create lesson-vocabulary links;
8. write versioned lesson exercise JSON;
9. calculate and cross-check course/unit/lesson totals;
10. write provenance records;
11. mark the job `completed` with created entity IDs;
12. commit.

Any failure rolls back the complete course. Partial course trees are never
visible.

`content_provenance` records entity type/ID, job ID, source name/version/URL,
license ID/URL, attribution, raw and record checksums, lineage, whether the
entity is generated/derived, and timestamps.

## Backend API

All endpoints require `admin` or `super_admin`.

```text
POST   /api/v1/admin/content-agent/uploads
POST   /api/v1/admin/content-agent/jobs
GET    /api/v1/admin/content-agent/jobs
GET    /api/v1/admin/content-agent/jobs/{job_id}
GET    /api/v1/admin/content-agent/jobs/{job_id}/preview
POST   /api/v1/admin/content-agent/jobs/{job_id}/apply
POST   /api/v1/admin/content-agent/jobs/{job_id}/retry
POST   /api/v1/admin/content-agent/jobs/{job_id}/cancel
```

Creating a job accepts:

- selected CEFR levels;
- source adapters and optional upload ID;
- optional course title/topic focus;
- units per course and lessons per unit;
- vocabulary count per lesson, default 10 and constrained to 8-12;
- exercise count/mix;
- confidence threshold;
- revision flag for intentionally repeating a previous request.

The list/detail endpoints expose progress and sanitized errors. Raw prompts,
source bodies, secrets, and stack traces are never returned.

Dashboard-created jobs always stop at `preview_ready`. Database writes require
the separate apply endpoint. This is the dashboard's dry-run guarantee.

## CLI

The backend CLI calls the same job/application services:

```bash
python -m app.cli.content_agent generate \
  --levels A1,A2 \
  --sources cefr_j,oewn,cmudict \
  --words-per-lesson 10 \
  --dry-run

python -m app.cli.content_agent status <job-id>
python -m app.cli.content_agent apply <job-id>
python -m app.cli.content_agent retry <job-id>
```

`generate` queues a Celery job by default and stops at preview when `--dry-run`
is present. Operators may use `--apply-on-success` instead, but the two flags
are mutually exclusive. A test-only eager mode may execute the task inline
without changing pipeline behavior.

## Admin Dashboard

The Courses page adds a `Generate with Agent` action.

The configuration modal contains:

- CEFR multi-select;
- source checkboxes with policy badges;
- CSV/JSON upload;
- optional topic/title focus;
- units, lessons, vocabulary-per-lesson, and exercise controls;
- preview-only execution, fixed on for dashboard jobs;
- an explicit acknowledgment that generated courses are drafts.

After submission, a job drawer shows:

- current stage and progress;
- processed/rejected/deduplicated counts;
- source-policy warnings;
- validation errors;
- retry/cancel actions.

`preview_ready` displays:

- course/unit/lesson tree;
- vocabulary counts and duplicate reuse counts;
- speaking/listening exercise counts;
- sample exercises;
- source/provenance summary;
- blocking errors and warnings.

The `Apply Draft to Database` button is disabled when blocking errors exist.
Applying does not publish the course. On completion, the UI links to the
existing course/unit/lesson editors.

The dashboard polls active jobs with bounded intervals and stops polling at a
terminal state. Refreshing the page restores state from the backend.

## Security and Compliance

- Admin JWT authorization is enforced on every backend endpoint.
- AI-service generation endpoints use a service credential and are not exposed
  as public learner endpoints.
- The admin browser never receives the AI service credential.
- Uploads validate size, MIME type, extension, encoding, row count, and schema.
- Dataset downloaders use hard-coded official hosts, HTTPS, response-size
  limits, timeouts, redirect limits, private-network/IP blocking, and expected
  checksums where publishers provide them.
- Downloads are written to temporary files, verified, then atomically promoted
  into immutable version directories.
- Source text and upload contents are not logged.
- API keys remain in service environment variables and never enter job JSON.
- Source policy is checked before extraction and again before artifact apply.
- Metadata-only content cannot be included verbatim in prompts or lessons.
- Generated artifacts keep source checksums and policy versions for audit.
- Job creation, apply, retry, cancel, and configuration changes are audit logged.

## Failure Handling

- Temporary network/AI failures use bounded exponential retries.
- Parser or schema failures reject only affected records when safe.
- Policy, authorization, artifact integrity, and database validation failures
  fail the whole job.
- A cancelled Celery task checks cancellation between pipeline stages.
- Worker restart recovery uses the persisted job stage and artifacts.
- Stale `running` jobs are marked recoverable and can be retried by an admin.
- AI output exceeding limits or failing schema validation is regenerated once,
  then returned as a blocking preview error.

## Observability

Metrics include:

- job counts and duration by status/stage/source;
- records extracted, rejected, and deduplicated;
- LLM calls, retries, latency, and token estimates;
- courses, lessons, vocabulary links, and exercises created;
- source-policy denials;
- apply transaction failures.

Logs use job IDs and request IDs but omit source bodies and generated answer
content. The existing monitoring/log pages can link to filtered job events.

## Testing

### AI service

- adapter contract tests for OEWN, CMUdict, CEFR-J, Wikidata, Tatoeba,
  LibriSpeech, Common Voice, and uploads;
- source-policy tests proving unknown, ShareAlike, non-commercial, or
  attribution-incomplete records never reach prompts/artifacts;
- golden normalized-record fixtures and checksum/reproducibility tests;
- quarantine tests with stable row-level error codes;
- CEFR/topic classifier tests including low-confidence rejection;
- deterministic planner tests for 8-12 vocabulary items per lesson;
- exercise schema tests for speaking/listening quotas;
- artifact validator and prompt-injection fixture tests.

### Backend

- migration tests for job, provenance, and lesson-vocabulary tables;
- real-database tests for vocabulary reuse and curated-field preservation;
- idempotent apply and full rollback integration tests;
- admin authorization and upload validation tests;
- Celery task stage/retry/cancel tests;
- API tests for create, progress, preview, apply, retry, and duplicate request
  handling.

### Admin service

- API client tests;
- modal validation and upload tests;
- progress restoration/polling tests;
- preview warning/error rendering;
- apply disabled on blocking errors;
- successful apply navigation to the created draft.

### Required verification

```bash
cd ai-service && pytest tests/ -q
cd backend-service && pytest tests/ -q
cd admin-service && pnpm test && pnpm build:check
```

## Rollout

1. Remove legacy web/ShareAlike/non-commercial source definitions and disable
   the old crawl pipeline.
2. Ship the versioned ETL core, manifest registry, quarantine reports, OEWN,
   CMUdict, CEFR-J, and Wikidata adapters behind `CONTENT_ETL_ENABLED=false`.
3. Sync pinned development snapshots and run dry-run validation without
   production database writes.
4. Enable content-agent preview with approved snapshots.
5. Enable transactional apply for administrators after migration and rollback
   tests pass.
6. Add Tatoeba, Mini LibriSpeech, LibriSpeech, and Common Voice independently
   after capacity and per-record license-filter tests pass.

## Non-Goals

- automatic publishing;
- learner-triggered course generation;
- arbitrary URL crawling;
- HTML crawling for course source material;
- mixing ShareAlike or non-commercial datasets into the proprietary database;
- bypassing paywalls, authentication, robots restrictions, or anti-bot controls;
- cloning third-party courses or dictionary entries;
- replacing the existing course editors;
- generating or permanently storing TTS audio in the first release.
