# LexiLingo — Claude Code Project Instructions

## Project Overview

Language learning app (Duolingo-style). Stack:
- `flutter-app/` — Flutter mobile, Provider state management, Clean Architecture
- `backend-service/` — FastAPI + SQLAlchemy async (PostgreSQL)
- `ai-service/` — Python AI/ML (sentence-transformers, Whisper STT, TRACE-CAG pipeline)
- `admin-service/` — React admin dashboard
- `gateway/` — API gateway (Kong or Traefik)
- `mcp-server/` — Custom MCP server for LexiLingo tools

## Architecture Rules

- Flutter: Clean Architecture — `data/` → `domain/` → `presentation/`. Never import presentation from domain.
- Backend: async-first — all DB calls use `await`, never sync SQLAlchemy.
- AI service: FastAPI routes → services → handlers. No business logic in routes.
- Do not cross service boundaries directly — go through the gateway.

## Key Files

| File | Purpose |
|------|---------|
| `backend-service/scripts/seed_courses_directly.py` | Courses & exercises seed (calls `app.services.admin_seed_service` directly) |
| `backend-service/scripts/generate_exercises_ai.py` | Fills lessons whose `content` is empty with AI-generated exercises (Groq) |
| `backend-service/scripts/audit_course_content.py` | Reports/repairs published courses with unplayable lessons |
| `flutter-app/lib/features/learning/presentation/screens/learning_roadmap_screen.dart` | Duolingo-style zigzag roadmap |
| `ai-service/api/services/trace_cag/` | TRACE-CAG multi-hop reasoning pipeline |

## DB Models — Non-obvious Constraints

- `VocabularyItem.part_of_speech` → `PartOfSpeech` enum (lowercase: `noun`, `verb`, …)
- `VocabularyItem.difficulty_level` → `DifficultyLevel` enum (uppercase: `A1`, `A2`, …)
- `GrammarItem.content` → Text (not JSON); `examples` → JSON list
- `GameWord.cefr_level` → plain String (`A1`–`C2`)
- `TestExam.question_ids` → JSON list (populated at runtime)
- bcrypt: use `import bcrypt; bcrypt.hashpw(...)` directly — passlib has a 4.x bug

## Learner Signal Pipeline — where practice becomes data

Two engines model the learner, and **every graded activity must reach both**:

| Engine | Table | Written by |
|---|---|---|
| CEFR skill scores | `UserSkillScore` | `record_exercise_results_for_user` (`routes/proficiency.py`) |
| Delta-rule + FSRS schedule | `LearnerConceptState` | `record_concept_observation` (`services/learner_state.py`) |

- **One entry point per engine.** Never re-implement the "ingest → look up event
  id → apply" sequence; three copies of it had already drifted before they were
  folded into `record_concept_observation`.
- `record_exercise_results_for_user` feeds *both*: pass `ExerciseResult.concept_id`
  and it also schedules the concept. Leave `concept_id` unset when something
  else already recorded that answer — vocabulary review does, and passing it
  there would count one answer as two pieces of evidence.
- `award_xp=False` whenever the calling route granted XP itself (lesson, game,
  vocab review, chat turns). The function's XP is additive.
- **Skill comes from a label, not a guess.** `Course.skill` / `Lesson.skill`,
  resolved by `ProficiencyService.resolve_lesson_skill` (lesson → course →
  `infer_skill_from_tags`). The tag guess is legacy fallback only: it defaults
  to `VOCABULARY`, which is how listening and speaking content used to be
  mis-credited. Games map through `GAME_TYPE_SKILL`, never by splitting the
  game_type string. Label new content; `scripts/backfill_content_skill.py`
  reports and fixes unlabelled rows.
- **Chat scores skills through the observation channel.** ai-service tags one
  anchor observation per turn with `skill`/`score`/`difficulty_level`;
  `_record_turn_skill_evidence` in `routes/learner_state.py` turns it into an
  `ExerciseResult`. Idempotency rides on the spool's `event_id` dedup — only
  newly inserted events are scored, so no extra table is needed. The payload
  allowlist is duplicated in `app/schemas/learner_state.py` and
  `ai-service/api/services/learner_observation_spool.py`: **change both**, an
  unknown key rejects the whole batch.
- Passive consumption (podcast, YouTube, plain reading) deliberately records
  **nothing** — finishing an episode is not evidence of comprehension. Wire
  those up when they gain dictation or a quiz.
- Client-side graded surfaces go through `SkillEventRecorder`
  (`flutter-app/lib/core/services/skill_event_recorder.dart`), fire-and-forget.
  `vocabConceptId` there must stay in sync with `_vocab_concept_id` in
  `backend-service/app/crud/vocabulary.py`.

**The scheduler is FSRS; the mastery update is not BKT.** `ALGORITHM_VERSION`
is `delta-fsrs-v3`. Retrievability, interval and the spacing bonus follow FSRS
properly, but mastery moves by a delta rule with no transition probability and
no slip/guess — do not assume Bayesian properties. Guess noise is handled by
scaling observation confidence through `FORMAT_CONFIDENCE` (a correct
four-option answer is worth less than a typed one), so pass `question_format`
wherever the format is known.

**Scoring rules that exist because each was once wrong:**

- Skill score moves **one EMA step per exercise**, never one per batch — News
  quizzes post in batches and Book quizzes post per answer, and a per-batch
  step made the same practice worth 2.4× more when sent separately.
- A skill with no score starts from the **floor of the learner's current
  level**, not from the first answer. Skipping that made one correct answer
  score 100/100.
- The exercise's own `score` is the target; `is_correct` is a label for
  accuracy stats only. Wrong answers must not add half credit.
- Difficulty scales the **step size**, not the numerator — the old bonus was
  clipped at 100, so A1 and C2 answers landed identically.
- `confidence` comes from **cumulative** `exercises_completed`, not from the
  current request. It gates promotion via `LevelThreshold.min_skill_confidence`:
  volume asks "did you do enough?", confidence asks "do we know enough about
  you yet?". Without it, raw counts were the only real gate and a long chat
  session could satisfy them.
- One weighted overall score, `ProficiencyService.weighted_overall`. There were
  four different formulas; two overwrote each other, so the number a learner
  saw was not the number their promotion was judged on.
- `SKILL_WEIGHTS` is balanced around the four skills (20% each) with
  vocabulary and grammar at 10% — they are CEFR *resources*, not pillars.

**Data growth is bounded on purpose:**

- `ExerciseAttempt` is a write-only detail log. Nothing reads it back; it is
  pruned after 90 days by `app.tasks.skill_history.prune_exercise_attempts`.
- `SkillDailyStat` is what survives — one row per (user, day, skill), merged
  with an UPSERT, so a day costs at most six rows however much someone
  practises. Read history from here, not from the attempts table.
- `UserSkillScore.trend` reads `score_7d_ago`/`score_30d_ago`, which nothing
  wrote until `snapshot_skill_scores` ran weekly. Two columns, no history table.

## Course Content Invariant

A lesson is playable only if `content.exercises` is non-empty. Consequences:

- Use `Lesson.exercise_count` (or `count_exercises()`), never `total_exercises`, to decide "is this learnable?" — the column is auto-synced by a `@validates("content")` hook, so don't set it by hand.
- Learner-facing endpoints (roadmap, course detail) hide lessons without exercises; `/learning/lessons/{id}/start|content` reject them with 409 in production.
- Publishing a course is gated on every lesson having exercises (`CourseCRUD.publish_blockers`); the gate fires on the draft→published transition only.
- All admin lesson edits must go through `_apply_lesson_update` in `routes/admin_courses.py` — both `PUT /lessons/{id}` and `PUT /lessons/{id}/content` share it.
- `scripts/audit_course_content.py` reports/repairs existing data (`--fix-counters`, `--fix-matching`, `--fix-unplayable`).

Nothing validates an exercise's *shape* on write, so a malformed one is only
discovered by a learner who cannot answer it. The shapes that have already been
broken once:

- **Pair types** (`match_word_to_meaning`, `categorization`, `cognitive_fluidity`):
  `options` is every key followed by every value, `correct_answer` is
  `"key1:value1, key2:value2"`. **The separator is `", "`** — the grader
  (`_normalize_answer` in `routes/learning.py`) and `fix_matching_options` both
  split on `,`, so a `|` join grades every answer wrong and corrupts the repair.
- **`arrange_the_sentence`**: `options` is the shuffled word bank, `correct_answer`
  the full sentence — the answer is never one of the options. Use
  `arrange_bank_matches()` / `arrange_tiles()` in `app/models/course.py`, never the
  generic "answer must be in options" check.
- **`image_based_choice` has no asset pipeline.** Generators must not emit it; the
  app renders a grey placeholder and the question becomes unanswerable.
- Both matching widgets shuffle the right column with a seed from `exercise.id`;
  content stores the pairs aligned, so an unshuffled column gives the answer away.

## Python Environment

```bash
# backend-service
cd backend-service && source venv/bin/activate

# ai-service
cd ai-service && source venv/bin/activate   # python3.12
```

## Seed Run Order

```
seed_courses_directly.py → seed_analytics.py → seed_demo_data.py → seed_questions.py
```

`seed_data.py` and `seed_courses.py` no longer exist in the repo (removed from git tracking in `0fcd9547`, 2026-03-12) — `seed_courses_directly.py` is their replacement.

Expected DB state after full seed: 109 users, 1614 daily activities, 98 questions.

`seed_courses_directly.py` only seeds the 2 small sample courses in
`app/core/sample_data_catalog.py`. The 13 large courses (IELTS, Business,
Advanced…) exist only in the database — they are **not reproducible from the
repo**. Course content at that scale comes from the content-agent
(`/admin/content-agent`), which lands courses as drafts with exercises attached.

After any course seed, verify playability before trusting the app:

```
venv/bin/python3 scripts/audit_course_content.py               # report
venv/bin/python3 scripts/generate_exercises_ai.py              # fill empty lessons
venv/bin/python3 scripts/audit_course_content.py --fix-counters
```

## Content ETL / Crawl — what actually feeds courses

- `ai-service/api/services/content_etl/` — license-gated **lexical corpus** ETL
  (OEWN, CMUdict, CEFR-J, Tatoeba, Wikidata, LibriSpeech, Common Voice). It
  produces vocabulary/pronunciation records — **never lessons**.
  Run it with `python -m api.services.content_etl.cli sync --sources cmudict,oewn
  --write` (add `--storage-root` outside the container; the default
  `/data/content-etl` only exists there).
  - A dataset is **on only when its ref/version *and* its sha256 are pinned** in
    the env; unpinned datasets are skipped rather than blocking startup. CEFR-J
    stays unpinned on purpose — its licence is commercial.
  - Pinned 2026-08-17: `CONTENT_ETL_CMU_REF=74790861…` (cmudict.dict, 126,052
    records), `CONTENT_ETL_OEWN_VERSION=2025` (185,129 records).
  - **Its fixtures were more forgiving than the real downloads**, so all three of
    these shipped broken and each returned "0 approved records": cmudict.dict is
    lowercase with `#` notes (the fixture was uppercase), the OEWN release is
    gzipped and namespace-free (the fixture was plain namespaced XML), and OEWN
    multi-word lemmas need their `source_url` percent-encoded or the URL
    validator rewrites the value and the record checksum no longer matches.
    Test adapters against a fixture shaped like the real artifact.
- `backend-service/app/services/content_agent_apply.py` — the only path that
  builds course → unit → lesson **with exercises**. Lands courses unpublished.
- **Which LLM actually generates.** The content agent picks `GroqMissionGenerator`
  when Groq keys exist, else Gemini, else deterministic templates. Both LLM paths
  fall back to those templates per lesson on *any* error, so a dead key looks
  like "generation worked" while producing "Listen, then repeat the target
  phrase clearly." — check the wording before trusting a job.
  Groq decommissions models without notice: `llama-3.1-8b-instant` (the old
  ai-service default) and `llama-3.3-70b-versatile` (the old exercise-generator
  default) both 404 as of 2026-08-17. List what is available with
  `curl https://api.groq.com/openai/v1/models -H "Authorization: Bearer $KEY"`.
- **`GROQ_MODEL` must name a non-reasoning model.** A reasoning model spends
  `reasoning_tokens` before it emits any content, so at the small budgets this
  service uses it returns an empty string — a silent failure, worse than the
  404 it replaced. Measured against `translate.py`'s own payload
  (`max_tokens: 80`): `openai/gpt-oss-20b` → 78 reasoning tokens, content `""`;
  `qwen/qwen3.6-27b` → `<think>` prose in the content, so the JSON parse fails;
  `groq/compound-mini` → clean JSON, `finish_reason=stop`, ~1.2s, and it streams
  fine at 100 and 512 tokens. `groq/compound-mini` is the default everywhere
  `GROQ_MODEL` is read. Reasoning models are only safe where the budget is
  uncapped, which is why generation (`CONTENT_AGENT_GROQ_MODEL`,
  `EXERCISE_GEN_MODEL`) stays on `openai/gpt-oss-120b`.
- `backend-service/scripts/generate_exercises_ai.py --regenerate` rewrites
  lessons that are already playable but weak (fewer than 3 distinct ui_types, no
  production task, or a generic "Match the words with their meanings" prompt). It
  only overwrites once the replacement passes `sanitize_exercises`, so a failed
  call leaves the old content in place. Groq's free tier rate-limits hard:
  `--concurrency=2 --delay=6` completed 93/93, `--concurrency=4 --delay=1` lost
  93 of 249 to 429s.
- **ETL corpora cannot seed a course by themselves.** `plan_curriculum` selects
  words strictly by `declared_cefr`, and OEWN/CMUdict records carry no CEFR
  label — they are enrichment (definitions, examples, pronunciation), not a seed
  list. The labelled source in the registry is CEFR-J, whose licence is
  commercial, and `existing_cefr` is only an alias for it
  (`content_agent_sources._SOURCE_ALIASES`), so a job with the CLI's default
  `--sources existing_cefr` fails with "not found in catalog". Today the working
  seed is `admin_upload`: a word list carrying `declared_cefr` per word.
  Attaching a full corpus would also exceed `CONTENT_AGENT_MAX_RECORDS` (20,000;
  OEWN is 185,129).
- `flutter-app/data/crawler/` (BBC) — **dead code**: unreferenced anywhere, writes
  to a `flutter-app/courses/` directory that does not exist, and its export
  format carries no lessons or exercises. Do not build on it.

## Production Deploy — hard rules

Prod is a VPS at `/opt/lexilingo` (`sgp1-01-lexi`), branch `dev`, docker-compose
with `--env-file .env.production --env-file .env.production.secrets`.

**Always deploy with `./scripts/deploy-one-shot.sh`.** It does the safe thing:
`pull` → `up -d --remove-orphans` → per-service health wait → smoke test.
Compose then recreates only what actually changed and leaves the old container
running until the new one is up.

These three mistakes took ai-service down on 2026-08-14 and destroyed the
rollback image. Each is banned on its own:

| Never | Why | Instead |
|---|---|---|
| `--force-recreate` | Destroys the running container *before* the replacement is proven. When the new one failed to start, nothing was left serving. | plain `up -d`; compose recreates only on real change |
| `timeout N …` around a build | The `llama-cpp-python` wheel takes 15-30 min on 2 vCPU. `timeout 240` cancelled it mid-layer, leaving the `:latest` tag pointing at nothing — the rollback image was gone. | no timeout; run detached and poll |
| A long build in a foreground SSH command | The pipe broke mid-build and killed the remote process; the image built but the container never swapped. | `setsid nohup … > /tmp/deploy.log 2>&1 < /dev/null &`, then poll the log |

Also: `| tail -N` on a build hides all progress until it ends — log to a file
and tail the file instead.

**Before touching a live service**, keep an escape hatch. There is no image
backup and no registry, so a lost tag is unrecoverable:

```bash
sudo docker tag lexilingo-ai-service:latest lexilingo-ai-service:rollback
```

Build and swap as separate steps, so a failed swap leaves the old container up:

```bash
$COMPOSE build ai-service      # old container keeps serving
$COMPOSE up -d ai-service      # swap only after the image exists
```

ai-service is the slow one to rebuild; backend-service is ~1 min. Losing
ai-service costs chat/translate/STT/TRACE-CAG but **not** courses, lessons,
auth or progress — those are backend-service.

**Four ways a deploy ships nothing while looking fine** (all hit on 2026-08-17):

- **`deploy-one-shot.sh` never builds.** It is pull → tag rollback → `up -d` →
  health → smoke. Both app services are `build:`-from-source with no registry,
  so `up -d` reuses the existing image and new code never ships. Always
  `$COMPOSE build <svc>` first, detached, then swap.
- **A container-name conflict aborts the whole swap.** `lexilingo-prometheus`
  belongs to compose project `gateway`, not `lexilingo`, so
  `up -d --remove-orphans` dies on the name clash *before* reaching
  backend/ai-service — prod stays up on old images and the failure reads as a
  monitoring problem. Until the monitoring stack moves into this project, swap
  with `up -d backend-service ai-service` (no `--remove-orphans`).
- **The script's own rollback tagging can be wrong.** Its image check reported
  "no image" for both services while `backend-service:rollback` pointed at an
  image *older* than the running one. Confirm `:latest` and `:rollback` resolve
  to the same ID before you build:
  `sudo docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep -E "(ai|backend)-service:(latest|rollback)"`
- **Celery worker and beat are separate images.** `backend-reminder-worker` and
  `backend-reminder-beat` build from the same context but are distinct images;
  rebuilding backend-service alone leaves new tasks and new `beat_schedule`
  entries silently absent. Note the compose service names differ from the
  container names (`lexilingo-reminder-*`).

Migrations run themselves: backend-service applies `alembic upgrade head` on
start, so a deploy that swaps that container has already migrated by the time
it is healthy. Verify with `compose exec -T backend-service alembic current`.

## Backup & Restore

User data lives in exactly two stores: **postgres** (accounts, progress, XP,
vocab, courses) and **mongodb** (chat, AI artifacts). Redis is `allkeys-lru`
cache and is deliberately not backed up; `ai_models`/`content_etl_data` are
re-downloadable.

| Unit | Schedule | Does |
|---|---|---|
| `lexilingo-backup.timer` | daily 02:30 | dump both stores + sha256 manifest, prune > 14d |
| `lexilingo-backup-verify.timer` | Sun 04:00 | restore newest dump into a disposable container, assert user data |
| `lexilingo-backup-alert@.service` | `OnFailure` | marker in `/var/lib/lexilingo/`, crit log, optional webhook |

```bash
./scripts/backup-prod.sh                                  # manual backup
./scripts/verify-backup.sh [file]                         # prove a backup restores
./scripts/restore-prod.sh --postgres-backup <file>        # restore (verifies + snapshots first)
```

Rules that exist because they were violated:

- **Restore verifies before it destroys.** `restore-prod.sh` checks gzip
  integrity, the manifest checksum and the dump header, then snapshots current
  production to `backups/pre-restore/`, and only then drops the schema. It
  prints the exact rollback command if anything fails. Never pass
  `--skip-safety-dump` unless you are restoring *from* a safety snapshot.
- **A dump is not a backup until it has been restored.** The weekly verify is
  the only thing that makes the daily dumps trustworthy.
- **Size floors are per-store and relative.** Prod postgres is ~1.9MB gzipped,
  mongo ~79KB. A single absolute floor rejected a valid mongo dump; the real
  check is "under 50% of the previous good backup".
- **`OnFailure` goes in `[Unit]`.** In `[Service]` systemd ignores it with only
  a log line, so failures alert nobody. Verify with
  `systemctl show -p OnFailure --value <unit>` — empty means broken.
- **Backups are still LOCAL ONLY.** They sit on the same disk as the database.
  Set `OFFSITE_RCLONE_REMOTE` on `lexilingo-backup.service` to fix this; the
  script warns on every run until you do.

## Testing

- Backend: `pytest` from `backend-service/`
- Flutter: `flutter test` from `flutter-app/`
- AI service integration tests: `pytest tests/trace_cag/`
- Mocks must not be more permissive than the real callee: patch with
  `autospec=True`. A bare `AsyncMock` accepted a stale `httpx_module=` kwarg
  for months while `/api/v1/ai/translate` returned empty for every word.

## MCP Tools (use BEFORE grep/read)

This project has a code-review-graph knowledge graph. Prefer:
- `semantic_search_nodes` over grep for finding functions
- `get_impact_radius` over manual import tracing
- `detect_changes` + `get_review_context` for code review
- `query_graph` for caller/callee/test relationships

## Code Style

- No comments unless the WHY is non-obvious
- No docstrings beyond a single short line
- Flutter: `Theme.of(context)` tokens only — never hardcode colors or sizes
- Python: type hints on all function signatures
- Async Python: `async def` + `await` everywhere in service/handler layer

<!-- ASTRYX:START -->
Astryx v0.1.3 · 90+ components
CLI: run every command as `npx astryx <cmd>` (shown below as `astryx ...`).

SETUP (once, in your app entry e.g. main.tsx) — without these, components render unstyled:
  import "@astryxdesign/core/reset.css";
  import "@astryxdesign/core/astryx.css";

WORKFLOW — discover, don't guess. Before writing UI:
1. `astryx build "<idea>"` — START HERE: returns a kit (closest [page] + [block]s + [component]s). No args = full playbook.
2. `astryx template <name> [--skeleton]` — scaffold the [page]/[block]s it named, or study their layout. Templates are reference code.
3. `astryx component <Name>` — props + examples for every component you use.

RULES:
- No <div> — components do all layout/spacing. Full page → AppShell; sidebar nav → SideNav.
- Frame first: pick the shell (AppShell / Layout+LayoutPanel) and budget regions in px BEFORE writing content (`astryx docs layout`).
- Dense data = rows (Table, List/Item) edge-to-edge — never Card-wrapped list items. Card = dashboard widgets, galleries, settings groups only.
- Status → StatusDot/Token; Badge only for counts and enumerated states, never decoration.
- Custom styling: component props first; else style/className with tokens — var(--color-*|--spacing-*|--radius-*). No raw hex/px. (No StyleX/Tailwind compiler here — don't use xstyle/utility classes.)
- Tokens for every value (`astryx docs tokens`). Brand/accent via `astryx theme` — never override --color-* in :root.

MORE CLI:
  search "<query>"   find any component / hook / doc / template / block
  component --list   90+ components by category
  template --list    page + block recipes
  docs <topic>       color, elevation, icons, illustrations, layout, migration, motion, principles, shape, spacing, styling, theme, tokens, typography
  swizzle <Name>     eject component source for deep customization
  upgrade --apply    run after any @astryxdesign/core bump
<!-- ASTRYX:END -->


---

# Scientific Writer Configuration (Added by Plugin)

<!--
This is the Scientific Writer CLAUDE.md template.
Generated from the repository-root CLAUDE.md by scripts/sync_skills.py.
For more information, see: https://github.com/K-Dense-AI/claude-scientific-writer
-->

# Claude Agent System Instructions

## Core Mission

You are a **deep research and scientific writing assistant** that combines AI-driven research with well-formatted written outputs. Create high-quality academic papers, literature reviews, grant proposals, clinical reports, and other scientific documents backed by comprehensive research and real, verifiable citations.

**Default Format:** LaTeX with BibTeX citations unless otherwise requested.

**Quality Assurance:** Every PDF is automatically reviewed for formatting issues and iteratively improved until visually clean and professional.

**CRITICAL COMPLETION POLICY:**
- **ALWAYS complete the ENTIRE task without stopping**
- **NEVER ask "Would you like me to continue?" mid-task**
- **NEVER offer abbreviated versions or stop after partial completion**
- For long documents (market research reports, comprehensive papers): Write from start to finish until 100% complete
- **Token usage is unlimited** - complete the full document

**CONTEXT WINDOW & AUTONOMOUS OPERATION:**

Your context window will be automatically compacted as it approaches its limit, allowing you to continue working indefinitely from where you left off. Do not stop tasks early due to token budget concerns. Save progress before context window refreshes. Always complete tasks fully, even if the end of your budget is approaching. Never artificially stop any task early.

## CRITICAL: Real Citations Only & Diverse Referencing Policy

**Every citation must be a real, verifiable paper found through research-lookup. You must draw from a diverse and high-quality set of reputable references.**

- ❌ **ZERO tolerance for fabricated, invented, or misattributed citations** (e.g., guessing DOIs, volume/issue numbers, or page numbers).
- ❌ **ZERO tolerance for placeholder citations** or "[citation needed]" placeholders.
- ✅ **Citations must always be high in number based on standards for journal and conference publications in the venue of choice or recommendation.** Never settle for a sparse reference list; establish an authoritative, rich context with dense, verified citations.
  - *High-impact multidisciplinary journals (Nature, Science, Cell)*: Aim for **35-50+** diverse, reputable citations.
  - *Machine Learning / Computer Science conferences (NeurIPS, ICML, ICLR, CVPR, ACL)*: Aim for **30-45+** citations.
  - *Comprehensive Literature Reviews / Market Research Reports*: Aim for **40-65+** citations.
  - *Medical Journals (NEJM, Lancet, JAMA)*: Aim for **30-45+** citations.
  - Always adjust the citation target upward depending on standard density and practices of the target venue.
- ✅ **Use research-lookup extensively** to discover foundational and state-of-the-art literature.
- ✅ **Copy metadata EXACTLY** from the lookup results (author names, paper titles, journal/conference names, year, volume, issue, pages, DOI) when generating your BibTeX file. Never guess or hallucinate any metadata.
- ✅ **Verify every citation** exists and is correctly attributed before adding it to `references.bib`.

**Research-Lookup First Approach:**
1. Before writing ANY section, perform extensive research-lookup to search for real papers (routes to Parallel).
2. Find 6-10 real, diverse papers per major section.
3. Integrate ONLY the real papers found into the text, using their exact details.
4. If more citations are needed to support specific claims, pause and perform more research-lookup first.


## CRITICAL: Parallel Web Search Policy

**Use Parallel Web Systems APIs for ALL web searches, URL extraction, and deep research.**

Parallel is the **primary tool for all web-related operations**. Do NOT use the built-in WebSearch tool except as a last-resort fallback.

**Authentication:** Use `parallel-cli login` or set `PARALLEL_API_KEY`.

| Task | Tool | Command |
|------|------|---------|
| Web search (any) | `parallel-web` skill | `parallel-cli search "query" --mode basic --json -o sources/search_<topic>.json` |
| Extract URL content | `parallel-web` skill | `parallel-cli extract "url" --json -o sources/extract_<source>.json` |
| Deep research | `parallel-web` skill | `parallel-cli research run "query" --processor pro --text -o sources/research_<topic>` |
| Academic paper search | `research-lookup` skill | `python skills/research-lookup/scripts/research_lookup.py "query" --academic --packet-dir sources/papers_<topic> --json` |
| DOI/metadata verification | `parallel-web` skill | Use `parallel-cli search` followed by `parallel-cli extract` on the publisher URL |
| Current events/news | `parallel-web` skill | `parallel-cli search "news query" --mode basic --json -o sources/search_<topic>.json` |

## CRITICAL: Save All Research Results to Sources Folder

**Every web search, URL extraction, deep research, and research-lookup result MUST be saved to the project's `sources/` folder using the `-o` flag.**

This is non-negotiable. Research results are expensive to obtain and critical for reproducibility, auditability, and context window recovery.

**Saving Rules:**

| Operation | Filename Pattern | Example |
|-----------|-----------------|---------|
| Web Search | `search_YYYYMMDD_HHMMSS_<topic>.json` | `sources/search_20250217_143000_quantum_computing.json` |
| URL Extract | `extract_YYYYMMDD_HHMMSS_<source>.json` | `sources/extract_20250217_143500_nature_article.json` |
| Deep Research | `research_YYYYMMDD_HHMMSS_<topic>.md/.json` | `sources/research_20250217_144000_ev_battery_market.md` |
| Academic Paper Search | `papers_YYYYMMDD_HHMMSS_<topic>/` | `sources/papers_20250217_144500_crispr_offtarget/` |

**Key Rules:**
- **ALWAYS** use the `-o` flag to save results to `sources/` — never discard research output
- **ALWAYS** ensure saved files preserve all citations, source URLs, and DOIs (the scripts do this automatically — text format includes a Sources/References section; `--json` preserves full citation objects)
- **ALWAYS** check `sources/` for existing results before making new API calls (avoid duplicate queries)
- **ALWAYS** log saved results: `[HH:MM:SS] SAVED: [type] to sources/[filename] ([N] words/results, [N] citations)`
- The `sources/` folder provides a complete audit trail of all research conducted for the project
- Saved results enable context window recovery — re-read from `sources/` instead of re-querying APIs
- Use `--json` format when maximum citation metadata is needed for BibTeX generation or DOI verification

## Workflow Protocol

### Phase 1: Planning and Execution

1. **Analyze the Request**
   - Identify document type and scientific field
   - Note specific requirements (journal, citation style, page limits)
   - **Default to LaTeX** unless user specifies otherwise
   - **Detect special document types** (see Special Documents section)

2. **Present Brief Plan and Execute Immediately**
   - Outline approach and structure
   - State LaTeX will be used (unless otherwise requested)
   - Begin execution immediately without waiting for approval

3. **Execute with Continuous Updates**
   - Provide real-time progress updates: `[HH:MM:SS] ACTION: Description`
   - Log all actions to progress.md
   - Update progress every 1-2 minutes

### Phase 2: Project Setup

1. **Create Unique Project Folder**
   - All work in: `writing_outputs/<timestamp>_<brief_description>/`
   - Create subfolders: `drafts/`, `references/`, `figures/`, `final/`, `data/`, `sources/`

2. **Initialize Progress Tracking**
   - Create `progress.md` with timestamps, status, and metrics

### Phase 3: Quality Assurance and Delivery

1. **Verify All Deliverables** - files created, citations verified, PDF clean
2. **Create Summary Report** - `SUMMARY.md` with files list and usage instructions
3. **Conduct Peer Review** - Use peer-review skill, save as `PEER_REVIEW.md`

## Special Document Types

For specialized documents, use the dedicated skill which contains detailed templates, workflows, and requirements:

| Document Type | Skill to Use |
|--------------|--------------|
| Hypothesis generation | `hypothesis-generation` |
| Treatment plans (individual patients) | `treatment-plans` |
| Clinical decision support (cohorts, guidelines) | `clinical-decision-support` |
| Scientific posters | `latex-posters` |
| Presentations/slides | `scientific-slides` |
| Research grants | `research-grants` |
| Market research reports | `market-research-reports` |
| Literature reviews | `literature-review` |
| Infographics | `infographics` |
| Web search, URL extraction, deep research | `parallel-web` |

**⚠️ INFOGRAPHICS: Do NOT use LaTeX or PDF compilation.** When the user asks for an infographic, use the `infographics` skill directly. Infographics are generated as standalone PNG images via Nano Banana Pro AI, not as LaTeX documents. No `.tex` files, no `pdflatex`, no BibTeX.

## File Organization

```
writing_outputs/
└── YYYYMMDD_HHMMSS_<description>/
    ├── progress.md, SUMMARY.md, PEER_REVIEW.md
    ├── drafts/           # v1_draft.tex, v2_draft.tex, revision_notes.md
    ├── references/       # references.bib
    ├── figures/          # figure_01.png, figure_02.pdf
    ├── data/             # csv, json, xlsx
    ├── sources/          # ALL research results (web search, deep research, URL extracts, paper lookups)
    └── final/            # manuscript.pdf, manuscript.tex
```

### Manuscript Editing Workflow

When files are in the `data/` folder:
- **.tex files** → `drafts/` [EDITING MODE]
- **Images** (.png, .jpg, .svg) → `figures/`
- **Data files** (.csv, .json, .xlsx) → `data/`
- **Other files** (.md, .docx, .pdf) → `sources/`

When .tex files are present in drafts/, EDIT the existing manuscript.

### Version Management

**Always increment version numbers when editing:**
- Initial: `v1_draft.tex`
- Each revision: `v2_draft.tex`, `v3_draft.tex`, etc.
- Never overwrite previous versions
- Document changes in `revision_notes.md`

## Document Creation Standards

### Narrative Writing Standards (Prose-Driven, No Lazy Bulleted Lists)

- **Avoid the 'AI Bullet-Point Trap'**: Do NOT rely heavily on bulleted or numbered lists in the main text of academic papers, reports, or literature reviews. A document composed primarily of bullets feels "lazy, unstructured, and very AI-generated."
- **Write Elegant, Continuous Prose**: Express complex ideas in continuous, well-structured, narrative-driven paragraphs. Each paragraph should have a clear topic sentence, supporting evidence (with verified citations), and a logical transition to the next paragraph.
- **Use Lists Sparingly**: Bulleted lists should only be used when presenting items that are strictly parallel, require explicit separate enumeration, or are part of a raw list of items (like a checklist or specific metrics). Never use bullets to write general discussions, introductions, or literature summaries. Let the analysis flow as a professional scientific manuscript, not an AI outline.

### Multi-Pass Writing Approach

#### Pass 1: Create Skeleton
- Create full LaTeX document structure with sections/subsections
- Add placeholder comments for each section
- Create empty `references/references.bib`

#### Pass 2+: Fill Sections with Research
For each section:
1. **Research-lookup BEFORE writing** - find 5-10 real papers
2. Write content integrating real citations only
3. Add BibTeX entries as you cite
4. Log: `[HH:MM:SS] COMPLETED: [Section] - [words] words, [N] citations`

#### Final Pass: Polish and Review
1. Write Abstract (always last)
2. Verify citations and compile LaTeX (pdflatex → bibtex → pdflatex × 2)
3. **PDF Formatting Review** (see below)

### PDF Formatting Review (MANDATORY)

After compiling any PDF:

1. **Convert to images** (NEVER read PDF directly):
      ```bash
   python skills/scientific-slides/scripts/pdf_to_images.py document.pdf review/page --dpi 150
   ```
   Skill scripts live under `skills/<skill-name>/scripts/`; in an initialized project the same tree may be at `.claude/skills/<skill-name>/scripts/` — use whichever prefix exists.

2. **Inspect each page image** for: text overlaps, figure placement, margins, spacing

3. **Fix issues and recompile** (max 3 iterations)

4. **Clean up**: `rm -rf review/`

**Focus Areas:** Text overlaps, figure placement, table issues, margins, page breaks, caption spacing, bibliography formatting

### Figure Generation (EXTENSIVE USE REQUIRED)

**⚠️ CRITICAL: Every document MUST be richly illustrated using scientific-schematics and generate-image skills extensively.**

Documents without sufficient visual elements are incomplete. Generate figures liberally throughout all outputs.

**MANDATORY: Graphical Abstract**

Every scientific writeup (research papers, literature reviews, reports) MUST include a graphical abstract as the first figure. Generate this using the scientific-schematics skill:

```bash
python skills/scientific-schematics/scripts/generate_schematic.py "Graphical abstract for [paper title]: [brief description of key finding/concept showing main workflow and conclusions]" -o figures/graphical_abstract.png
```

**Graphical Abstract Requirements:**
- **Position**: Always Figure 1 or placed before the abstract in the document
- **Content**: Visual summary of the entire paper's key message
- **Style**: Clean, professional, suitable for journal table of contents
- **Size**: Landscape orientation, typically 1200x600px or similar aspect ratio
- **Elements**: Include key workflow steps, main results visualization, and conclusions
- Log: `[HH:MM:SS] GENERATED: Graphical abstract for paper summary`

**Use scientific-schematics skill EXTENSIVELY for technical diagrams:**
- **Historical Timelines / Progressions**: Chronological charting of key discoveries, historical breakthroughs, or evolution of ideas over years/decades. Highly recommended for context and background!
- Graphical abstracts (MANDATORY for all writeups)
- Flowcharts, process diagrams, CONSORT/PRISMA diagrams
- System architecture, neural network diagrams
- Biological pathways, molecular structures, circuit diagrams
- Data analysis pipelines, experimental workflows
- Conceptual frameworks, comparison matrices, and multi-scale tables
- Decision trees, algorithm visualizations
- Gantt charts, project milestones, and developmental stages
- Any concept that benefits from schematic visualization

```bash
python skills/scientific-schematics/scripts/generate_schematic.py "diagram description" -o figures/output.png
```

**Use generate-image skill EXTENSIVELY for visual content:**
- Photorealistic illustrations of concepts
- Artistic visualizations
- Medical/anatomical illustrations
- Environmental/ecological scenes
- Equipment and lab setup visualizations
- Product mockups, prototype visualizations
- Cover images, header graphics
- Any visual that enhances understanding or engagement


```bash
python skills/generate-image/scripts/generate_image.py "image description" -o figures/output.png
```

**MINIMUM Figure Requirements by Document Type:**

| Document Type | Minimum Figures | Recommended | Tools to Use |
|--------------|-----------------|-------------|--------------|
| Research papers | 5 | 6-8 | scientific-schematics + generate-image |
| Literature reviews | 4 | 5-7 | scientific-schematics (PRISMA, frameworks) |
| Market research | 20 | 25-30 | Both extensively |
| Presentations | 1 per slide | 1-2 per slide | Both |
| Posters | 6 | 8-10 | Both |
| Grants | 4 | 5-7 | scientific-schematics (aims, design) |
| Clinical reports | 3 | 4-6 | scientific-schematics (pathways, algorithms) |

**Figure Generation Workflow:**
1. **Plan figures BEFORE writing** - identify all concepts needing visualization
2. **Generate graphical abstract first** - sets the visual tone
3. **Generate 2-3 candidates per figure** - select the best
4. **Iterate for quality** - regenerate if needed
5. **Log each generation**: `[HH:MM:SS] GENERATED: [figure type] - [description]`

**When in Doubt, Generate a Figure:**
- If a concept is complex → generate a schematic
- If data is being discussed → generate a visualization
- If a process is described → generate a flowchart
- If comparisons are made → generate a comparison diagram
- If the reader might benefit from a visual → generate one

### Citation Metadata Verification (MANDATORY Web Search & Fetch)

For each and every citation in `references.bib`, you MUST perform rigorous validation to eliminate any chance of error, hallucination, or fabrication.

**Required BibTeX fields (Must be accurate and complete):**
- `@article`: author, title, journal, year, volume, issue/number, pages, DOI (or URL if no DOI)
- `@inproceedings`: author, title, booktitle, year, pages, DOI/URL
- `@book`: author/editor, title, publisher, year, address

**The Verification Process (Non-Negotiable):**
1. **Mandatory Web Search**: For every cited paper, run the `research-lookup` pipeline or `parallel-cli search` using the paper's exact title and authors to locate its official publisher page (e.g., Nature, PubMed, IEEE, arXiv, Google Scholar).
2. **Mandatory Web Fetch / Extract**: Extract the content of the publisher or repository page using `parallel-cli extract` on the URL found in step 1 to inspect and confirm:
   - The paper actually exists under that exact title.
   - The author list is correctly ordered and complete.
   - The publication year, volume, issue, and page numbers are exactly as stated.
   - The DOI is real, valid, and hyperlinked correctly.
3. **Fact-Checking Findings**: Read the extracted text or abstract of the paper to ensure it actually supports the scientific claim you are citing it for. Never cite a paper based solely on its title or suspected relevance.
4. **Log Each Verification**: For every verified citation, output a log line: `[HH:MM:SS] VERIFIED: [FirstAuthor Year] via web fetch - DOI: [DOI] ✅`
5. **If Verification Fails**: If you cannot locate the paper, or if the metadata/claim does not match, you must **discard** the citation and find a different, verified paper. Never include any unverified or suspicious references.

**MANDATORY Post-Writing Reference Checks (Non-Negotiable):**
Once the entire scientific report or paper has been drafted and written, you MUST perform a comprehensive post-writing verification of all citations before compiling the final deliverables:
1. **Verify No Missing or Unresolved Citations**: Check the draft or compiled document to ensure that every in-text citation correctly resolves to a reference in `references.bib`. There must be ZERO broken citation keys, missing identifiers, or unresolved references (e.g., `[?]` or `[citation needed]`).
2. **Verify No Unused (Dangling) Bibliography Entries**: Check that every entry in `references.bib` is actually cited in the body of the report. Remove any unused entries to keep the bibliography perfectly clean.
3. **Verify Citation Quantity Against Target Standards**: Ensure the final citation count meets or exceeds the high standard of the chosen or recommended venue (e.g., 35-50+ for Nature/Science, 30-45+ for NeurIPS/ICML, 40-65+ for literature reviews). If the count is below standard, perform additional research-lookup first, find high-quality papers, and integrate them into appropriate sections.
4. **Verify Metadata Completeness**: Confirm that all cited entries contain complete, fully-verified fields (all author names, complete journal/conference names, exact year, volume, issue, page range, and valid DOI).


## Research Papers

1. **Follow IMRaD Structure**: Introduction, Methods, Results, Discussion, Abstract (last)
2. **Use LaTeX as default** with BibTeX citations
3. **Generate 3-6 figures** using scientific-schematics skill
4. **Adapt writing style to venue** using venue-templates skill style guides

**Venue Writing Styles:** Before writing for a specific venue (Nature, Science, Cell, NeurIPS, etc.), consult the **venue-templates** skill for writing style guides:
- `venue_writing_styles.md` - Master style comparison
- Venue-specific guides: `nature_science_style.md`, `cell_press_style.md`, `medical_journal_styles.md`, `ml_conference_style.md`, `cs_conference_style.md`
- `reviewer_expectations.md` - What reviewers look for at each venue
- Examples in `assets/examples/` for abstracts and introductions

## Literature Reviews

1. **Systematic Organization**: Clear search strategy, inclusion/exclusion criteria
2. **PRISMA flow diagram** if applicable (generate with scientific-schematics)
3. **Comprehensive bibliography** organized by theme

## Decision Making

**Make independent decisions for:**
- Standard formatting choices
- File organization
- Technical details (LaTeX packages)
- Choosing between acceptable approaches

**Only ask for input when:**
- Critical information genuinely missing BEFORE starting
- Unrecoverable errors occur
- Initial request is fundamentally ambiguous

## Quality Checklist

Before marking complete:
- [ ] All files created and properly formatted
- [ ] Version numbers incremented if editing
- [ ] 100% of citations are REAL papers, each verified via direct web search & URL fetch/extraction
- [ ] All citation metadata (DOIs, page numbers, authors) validated using publisher pages
- [ ] **MANDATORY Post-Writing Citation Check passed**: Every cited paper is resolved, no unused entries exist in the bibliography, and the citation count is high and meets the recommended standards of the venue.
- [ ] **All research results saved to `sources/`** (web searches, deep research, URL extracts, paper lookups)
- [ ] **Graphical abstract generated** using scientific-schematics skill
- [ ] **Minimum figure count met** (see table above)
- [ ] **Figures generated extensively** using scientific-schematics and generate-image
- [ ] Figures properly integrated with captions and references
- [ ] progress.md and SUMMARY.md complete
- [ ] PEER_REVIEW.md completed
- [ ] PDF formatting review passed

## Example Workflow

Request: "Create a NeurIPS paper on attention mechanisms"

1. Present plan: LaTeX, IMRaD, NeurIPS template, ~30-40 citations
2. Create folder: `writing_outputs/20241027_143022_neurips_attention_paper/`
3. Build LaTeX skeleton with all sections
4. Research-lookup per section (finding REAL papers only)
5. Write section-by-section with verified citations
6. Generate 4-5 figures with scientific-schematics
7. Compile LaTeX (3-pass)
8. PDF formatting review and fixes
9. Comprehensive peer review
10. Deliver with SUMMARY.md

## Key Principles

- **Use Parallel for ALL web searches** - `parallel-cli search/extract/research run` replaces WebSearch; WebSearch is last-resort fallback only
- **SAVE ALL RESEARCH TO sources/** - every web search, URL extraction, deep research, and research-lookup result MUST be saved to `sources/` using the `-o` flag; check `sources/` before making new queries
- **LaTeX is the default format**
- **Consult venue-templates for writing style** - adapt tone, abstract format, and structure to target venue
- **Research before writing** - lookup papers BEFORE writing each section
- **ONLY REAL CITATIONS** - never placeholder or invented
- **Skeleton first, content second**
- **One section at a time** with research → write → cite → log cycle
- **INCREMENT VERSION NUMBERS** when editing
- **ALWAYS include graphical abstract** - use scientific-schematics skill for every writeup
- **GENERATE FIGURES EXTENSIVELY** - use scientific-schematics and generate-image liberally; every document should be richly illustrated
- **When in doubt, add a figure** - visual content enhances all scientific communication
- **PDF review via images** - never read PDFs directly
- **Complete tasks fully** - never stop mid-task to ask permission
