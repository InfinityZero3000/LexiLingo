# CEFR Content Agent Design

## Goal

Add a compliance-first content agent that can build draft English courses from
CEFR A1-C2 data, uploaded CSV/JSON files, and approved web-source adapters.
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

The first delivery is one vertical feature with three rollout stages:

1. Core pipeline, CLI, dashboard, existing CEFR files, and CSV/JSON uploads.
2. VOA full-content ingestion where the item is confirmed as VOA-produced, plus
   metadata-only adapters for the other named sources.
3. Licensed API/full-content adapters enabled only after credentials and storage
   rights are configured.

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
directly.

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

Reuse `ai-service/scripts/kg_pipeline/crawlers/cefr_lists.py` and its cached
CEFR-J/Oxford-list inputs. The adapter converts the existing `{word: level}`
mapping into normalized records and preserves source attribution.

The Oxford-derived local list is treated only as a CEFR label source under its
existing dataset terms. Dictionary definitions, examples, and audio are not
copied from Oxford Learner's Dictionaries.

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
  "license_mode": "admin_owned"
}
```

Uploads are limited to UTF-8 `.csv` and `.json`, five megabytes, and 20,000
records. Parsing happens before a job is queued. Invalid rows are reported with
row numbers and do not silently disappear.

### Web-source adapters

Adapters are allowlisted in code. The dashboard never accepts arbitrary crawl
URLs.

| Source | Default mode | Allowed data |
| --- | --- | --- |
| VOA Learning English | `public_domain_verified` | RSS metadata and VOA-produced text/audio after per-item ownership checks |
| BBC Learning English | `metadata_only` | title, URL, date, declared level/topic, structured page metadata |
| British Council LearnEnglish | `metadata_only` | title, URL, declared CEFR/topic, page metadata |
| Cambridge English | `metadata_only` | public resource metadata and declared CEFR labels |
| Cambridge Dictionary | `disabled_pending_license` | no dictionary entry copying |
| Oxford Learner's Dictionaries | `api_pending_license` | API integration only after storage/display rights are configured |
| DOL English | `metadata_only` | title, URL, date, topic signals |
| PREP | `metadata_only` | title, URL, date, topic signals |
| The IELTS Workshop | `metadata_only` | title, URL, date, topic signals |

Metadata-only records can influence topic coverage, search terms, and curriculum
planning from titles, structured metadata, and declared labels only. Connectors
must not fetch an article body merely to summarize it. Article bodies, examples,
exercises, images, and audio cannot be stored in artifacts or prompts. Generated
lessons must be original and contain source attribution only as planning
provenance.

The source policy registry records `license_mode`, allowed fields, robots/terms
review date, rate limit, and whether content storage is permitted. A connector
fails closed when its policy is missing or expired.

Relevant source policies reviewed for this design:

- VOA copyright statement:
  <https://learningenglish.voanews.com/p/6021.html>
- British Council terms:
  <https://www.britishcouncil.org/terms>
- Oxford Dictionaries API terms:
  <https://developer.oxforddictionaries.com/api-terms-and-conditions>
- PREP terms:
  <https://prepedu.com/en/terms-and-conditions-of-transactions>
- DOL terms:
  <https://www.dolenglish.vn/dieu-khoan-su-dung>

## Normalized Source Contract

Every adapter produces:

```json
{
  "record_id": "source:stable-id",
  "source_name": "voa",
  "source_url": "https://...",
  "license_mode": "public_domain_verified",
  "content_usage": "full_text",
  "title": "Optional title",
  "word": "example",
  "part_of_speech": "noun",
  "definition": "Optional owned or generated definition",
  "translation_vi": "ví dụ",
  "example": "Optional owned or generated example",
  "declared_cefr": "A2",
  "declared_topic": "daily_life",
  "published_at": "2026-06-01T00:00:00Z",
  "checksum": "sha256...",
  "metadata": {}
}
```

Restricted fields are removed before persistence and before LLM invocation.
`content_usage` is one of `full_text`, `metadata_only`, or `label_only`.

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
  "schema_version": 1,
  "prompt_version": "cefr-course-v1",
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
POST   /api/v1/internal/content-agent/jobs/{job_id}/records
POST   /api/v1/internal/content-agent/jobs/{job_id}/generate
DELETE /api/v1/internal/content-agent/jobs/{job_id}
```

If AI temporary state expires, the backend replays the validated source batches
from its persisted upload/source artifact before retrying generation.

## Vocabulary Deduplication

Canonical vocabulary identity remains `(normalized_word, part_of_speech)`,
matching the existing unique constraint.

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

## Database Apply

The apply operation runs in one PostgreSQL transaction:

1. lock the job and confirm it is `preview_ready`;
2. validate that it has not already been applied;
3. create draft course, units, and lessons;
4. upsert vocabulary by normalized word and part of speech;
5. create lesson-vocabulary links;
6. write lesson exercise JSON;
7. calculate course/unit/lesson totals;
8. write provenance records;
9. mark the job `completed` with created entity IDs;
10. commit.

Any failure rolls back the complete course. Partial course trees are never
visible.

`content_provenance` records entity type/ID, job ID, source name/URL, license
mode, source checksum, whether the entity is generated/derived, and timestamps.

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
  --sources existing_cefr,voa \
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
- Web connectors use hard-coded hosts, HTTPS, response-size limits, timeouts,
  redirect limits, and private-network/IP blocking to prevent SSRF.
- Connector concurrency and per-host request rates are bounded.
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

- adapter contract tests for existing CEFR, upload fixtures, VOA, and
  metadata-only sources;
- source-policy tests proving restricted fields never reach prompts/artifacts;
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

1. Ship migrations, core pipeline, existing CEFR adapter, upload adapter, CLI,
   and dashboard behind `CONTENT_AGENT_ENABLED=false`.
2. Enable in development with Celery eager/test mode and dry-run only.
3. Enable the worker and preview/apply flow for administrators.
4. Add VOA with ownership verification and conservative rate limits.
5. Add metadata-only adapters one source at a time after policy fixtures pass.
6. Enable Oxford/Cambridge full-data integrations only under explicit licensed
   configuration.

## Non-Goals

- automatic publishing;
- learner-triggered course generation;
- arbitrary URL crawling;
- bypassing paywalls, authentication, robots restrictions, or anti-bot controls;
- cloning third-party courses or dictionary entries;
- replacing the existing course editors;
- generating or permanently storing TTS audio in the first release.
