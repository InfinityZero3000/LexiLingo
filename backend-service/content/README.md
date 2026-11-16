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

`scripts/import_course_content.py --dir content/courses` (added in the follow-up PR) restores these
files into an empty or existing database. Never use `admin_seed_service.seed_courses` for these courses:
it deletes and recreates, which gives them new UUIDs and orphans learner progress.

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

Nothing here is exported yet. `vocabulary_items` is the largest gap.
