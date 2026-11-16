"""
!!! NEVER use admin_seed_service.seed_courses for the real courses. !!!
It DELETES and RECREATES courses, so every course, unit and lesson gets a NEW
UUID and every learner's progress, enrolment and attempt rows point at nothing.
This script is the only supported way to put these courses into a database:
it keeps the ids stored in backend-service/content/courses/.

Import course files produced by export_course_content.py.

  default   insert rows whose id is absent; rows that already exist are left alone,
            so edits made in production are never overwritten
  --update  upsert: ON CONFLICT (id) DO UPDATE, for rows whose values differ

Never deletes, and only touches course_categories / courses / units / lessons,
never users, enrolments or progress. After inserting it fixes what raw SQL
bypasses: exercise `type` from `ui_type`, lessons.total_exercises, units/courses
total_lessons and categories.course_count.

Dry run unless --apply: everything executes, then the transaction rolls back.

Run (inside the backend-service container, or with DATABASE_URL set):
    python3 scripts/import_course_content.py --dir content/courses
    python3 scripts/import_course_content.py --dir content/courses --apply
    python3 scripts/import_course_content.py --dir content/courses --apply --update
    python3 scripts/import_course_content.py --file /tmp/course_content.json --apply   # legacy single file
"""

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.course_content_import import (  # noqa: E402
    documents_from_monolith,
    import_documents,
    load_course_dir,
)


def _async_dsn(dsn: str) -> str:
    for prefix in ("postgresql://", "postgres://"):
        if dsn.startswith(prefix):
            return "postgresql+asyncpg://" + dsn[len(prefix):]
    return dsn


async def main(dsn: str, documents: list[dict], apply: bool, overwrite: bool) -> None:
    engine = create_async_engine(_async_dsn(dsn))
    try:
        async with AsyncSession(engine) as session:
            report = await import_documents(session, documents, overwrite=overwrite)
            print("\n".join(report.lines()))
            if apply:
                await session.commit()
                print("\nImported. Verify with scripts/audit_course_content.py")
            else:
                await session.rollback()
                print("\nDRY RUN: rows were written and verified, then rolled back. Re-run with --apply to keep them.")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    source = p.add_mutually_exclusive_group(required=True)
    source.add_argument("--dir", type=Path, help="directory of per-course files")
    source.add_argument("--file", type=Path, help="single file from export_course_content.py -o")
    p.add_argument("--apply", action="store_true", help="write (default is dry run)")
    p.add_argument("--update", action="store_true", help="overwrite rows that already exist")
    p.add_argument("--dsn", default=os.getenv("DATABASE_URL", ""))
    args = p.parse_args()
    if not args.dsn:
        sys.exit("set --dsn or DATABASE_URL")
    docs = (
        load_course_dir(args.dir)
        if args.dir
        else documents_from_monolith(json.loads(args.file.read_text(encoding="utf-8")))
    )
    if not docs:
        sys.exit("no course files found")
    asyncio.run(main(args.dsn, docs, args.apply, args.update))
