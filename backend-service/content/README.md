# Course content

`courses/<slug>.json` holds one published course each: its category, units and lessons with the full
`content` (exercises). It is the repo's copy of what runs in production, exported with UUIDs intact so a
rebuilt database keeps the same ids that learner progress points at.

Course content only. No users, enrolments, progress or XP are exported, and
`tests/test_committed_course_content.py` fails if a lesson is unplayable (no exercises, or an exercise
`exercise_shape_problems` rejects), if ids repeat across files, or if a file is not in the canonical
format (sorted keys, 2-space indent, UTF-8, trailing newline).

Last export: 15 published courses, 53 units, 259 lessons, 1,314 exercises. Unpublished courses are not
exported (prod has one: "English for Daily Life", A2).

## Export

```bash
cd backend-service
DATABASE_URL=postgresql://user:pass@host/db venv/bin/python3 scripts/export_course_content.py \
    --split-dir content/courses
```

The export is read-only. It refuses to run if any published lesson has no exercises. A file whose course
is no longer published is reported as stale and left in place; delete it by hand if that is intended.
`-o FILE` still writes the older single-file format.

To refresh from production without touching it, dump the four content tables and run the export against
a scratch database:

```bash
ssh ovh-vps 'sudo lxc exec lexilingo -- bash -lc "cd /opt/lexilingo && docker compose \
  --env-file .env.production --env-file .env.production.secrets exec -T postgres sh -c \
  \"pg_dump -U \\\$POSTGRES_USER -d \\\$POSTGRES_DB --data-only \
  -t course_categories -t courses -t units -t lessons\""' > content.sql
# scratch db: alembic upgrade head, then psql -f content.sql, then run the export above
```

## Restore

```bash
cd backend-service
python3 scripts/import_course_content.py --dir content/courses            # dry run, rolled back
python3 scripts/import_course_content.py --dir content/courses --apply    # insert what is missing
python3 scripts/import_course_content.py --dir content/courses --apply --update   # also overwrite rows that differ
```

Default is insert-only: a row whose id already exists is left alone, so edits made in production are
never overwritten. `--update` is `ON CONFLICT (id) DO UPDATE` and does overwrite them. Nothing is ever
deleted, and only categories, courses, units and lessons are touched. The importer then recomputes
what raw SQL bypasses: exercise `type` from `ui_type`, `lessons.total_exercises`, `total_lessons` on
units and courses, and `course_categories.course_count`.

Never use `admin_seed_service.seed_courses` for these courses: it deletes and recreates, which gives
them new UUIDs and orphans learner progress.

CI proves the path on every PR: `backend-migrations` builds an empty database with
`alembic upgrade head`, restores every file with the script, then imports twice more and asserts
nothing changed (`tests/test_course_content_import.py`).

## What is still not reproducible from the repo

Read from production (counts at export time):

| Table | Rows | State |
|---|---|---|
| `vocabulary_items` | 6,591 | In the database only. `seed_vocab_from_anki.py` and the content ETL can rebuild a vocabulary, not these exact rows. |
| `question_bank` | 98 | `scripts/seed_questions.py` seeds it from inline data, so it is reproducible, but production edits are not captured. |
| `test_exams` | 4 | Same: `seed_questions.py` (`update_test_exams`) creates them; `question_ids` is filled at runtime. |
| `grammar_items` | 12 | Seed data in `seed_questions.py`; edits made in production are not captured. |
| `game_words` | 10 | Demo-sized. `seed_empty_tables_and_crawl.py` seeds it. |
| `achievements` / `shop_items` | 48 / 55 | Seed scripts (`seed_demo_data.py`, `seed_shop_items.py`) and migrations create them; production edits are not captured. |

`vocabulary_items` and `question_bank` now have an export/import pair (below); the other tables are still not exported.

## Reference content: vocabulary and questions

`vocabulary/vocabulary_items.<A1..C2>.json` (one file per CEFR level, plus `unlabelled` if a row ever has none),
`vocabulary/manifest.json` (counts only) and `questions/question_bank.json`. Ids are kept, rows are sorted
(vocabulary by word, part of speech, id; questions by level, type, id) and the format is the same canonical
JSON as the courses, so re-exporting unchanged data produces no diff. Timestamps are not exported. Per-user
rows (`user_vocabulary`) never are.

```bash
# inside the backend-service container (DATABASE_URL is already set there); read-only
python3 scripts/export_reference_content.py --out-dir content
python3 scripts/export_reference_content.py --out-dir content --seed-csv /tmp/vocab_seed.csv   # + admin_upload CSV
```

The export runs in a `READ ONLY` transaction. `--seed-csv` writes `word,part_of_speech,cefr_level,definition,example`,
the columns `app/services/content_agent_uploads.py` reads for the content-agent `admin_upload` source (it also
accepts `translation_vi` and `topic`); `--csv-only` skips the JSON files.

```bash
python3 scripts/import_reference_content.py --dir content                    # dry run, rolled back
python3 scripts/import_reference_content.py --dir content --write            # insert what is missing
python3 scripts/import_reference_content.py --dir content --write --update   # also overwrite rows that differ
```

Default is insert-only. Every row is validated first (`part_of_speech` lowercase, `difficulty_level` uppercase,
UUIDs, duplicate ids and duplicate word+part of speech); one bad row refuses the whole import. A word whose
(word, part of speech) already exists under another id is skipped and reported, and a `course_id`, `lesson_id`
or `grammar_id` pointing at a row the target lacks is left empty (import courses first). Nothing is deleted.
Tests: `tests/test_reference_content.py`.

## Reference corpus (vocabulary + question bank) — server only

The full vocabulary and question-bank export (`vocabulary/vocabulary_items.<LEVEL>.json`,
`vocabulary/manifest.json`, `questions/question_bank.json`, `export.json`) is **not** in this repo: the
GitHub repository is public and the corpus must stay private. The Celery task
`app.tasks.vocabulary_enrichment.export_reference_corpus` rewrites it daily (03:15 UTC) on the
`backend-reminder-worker` container, into `REFERENCE_CORPUS_DIR` (`/data/reference-corpus`), which is the
host directory `/var/lib/lexilingo/reference-content/live`. The previous export is kept in `previous/`.
With `REFERENCE_CORPUS_DIR` empty the task logs and does nothing. Create the host directory once
(`mkdir -p /var/lib/lexilingo/reference-content/live`) and never copy its contents into a checkout.
