"""
Import course content produced by export_course_content.py.

Idempotent: rows are keyed by their original UUID and skipped if already
present, so a partial run can simply be repeated. Only touches
course_categories / courses / units / lessons — never users, enrolments or
progress.

Run (inside the backend-service container on the target host):
    python3 scripts/import_course_content.py --file /tmp/course_content.json
    python3 scripts/import_course_content.py --file ... --apply   # actually write
"""

import argparse
import asyncio
import json
import os
import sys
from datetime import datetime

import asyncpg

# Insert order matters: categories → courses → units → lessons (FK chain).
ORDER = ["course_categories", "courses", "units", "lessons"]
JSON_COLUMNS = {"tags", "content"}


def _decode(value):
    if isinstance(value, dict) and "__dt__" in value:
        return datetime.fromisoformat(value["__dt__"])
    if isinstance(value, list):
        return [_decode(v) for v in value]
    return value


async def import_table(conn, table: str, rows: list, apply: bool) -> tuple[int, int]:
    if not rows:
        return 0, 0

    columns = list(rows[0].keys())
    placeholders = ", ".join(
        # JSON columns arrive as text and must be cast, or asyncpg rejects them.
        f"${i + 1}::json" if columns[i] in JSON_COLUMNS else f"${i + 1}"
        for i in range(len(columns))
    )
    sql = (
        f'insert into {table} ({", ".join(columns)}) values ({placeholders}) '
        f"on conflict (id) do nothing"
    )

    inserted = skipped = 0
    for row in rows:
        exists = await conn.fetchval(f"select 1 from {table} where id = $1", _decode(row["id"]))
        if exists:
            skipped += 1
            continue
        # Always execute, even on a dry run — the transaction is rolled back
        # afterwards. A dry run that skips the INSERT proves nothing about
        # column types, casts or constraints, which is exactly what can fail.
        values = []
        for col in columns:
            v = _decode(row[col])
            if col in JSON_COLUMNS and v is not None and not isinstance(v, str):
                v = json.dumps(v, ensure_ascii=False)
            values.append(v)
        await conn.execute(sql, *values)
        inserted += 1
    return inserted, skipped


async def remap_categories(conn, payload: dict) -> int:
    """Point courses at the target's own categories.

    course_categories.name is UNIQUE, and the target already has categories
    with the same names under different ids. Inserting ours would violate the
    constraint, so reuse what is there and rewrite courses.category_id.
    """
    remapped = 0
    mapping: dict[str, str] = {}
    for cat in payload.get("course_categories", []):
        existing = await conn.fetchval(
            "select id from course_categories where name = $1 or slug = $2",
            cat["name"], cat.get("slug"),
        )
        if existing:
            mapping[cat["id"]] = str(existing)

    if mapping:
        kept = []
        for cat in payload["course_categories"]:
            if cat["id"] not in mapping:
                kept.append(cat)
        payload["course_categories"] = kept

        for course in payload.get("courses", []):
            old = course.get("category_id")
            if old and old in mapping:
                course["category_id"] = mapping[old]
                remapped += 1
    return remapped


async def main(dsn: str, path: str, apply: bool) -> None:
    payload = json.loads(open(path, encoding="utf-8").read())
    conn = await asyncpg.connect(dsn)
    try:
        async with conn.transaction():
            remapped = await remap_categories(conn, payload)
            print(f"  categories reused from target: {remapped} course(s) remapped")

            total_new = 0
            for table in ORDER:
                new, skip = await import_table(conn, table, payload.get(table, []), apply)
                total_new += new
                print(f"  {table}: {new} new, {skip} already present")

            if not apply:
                print(
                    f"\nDRY RUN — {total_new} rows inserted and verified, "
                    f"now rolling back. Re-run with --apply to keep them."
                )
                raise asyncio.CancelledError  # roll the transaction back
    except asyncio.CancelledError:
        pass
    finally:
        await conn.close()

    if apply:
        print(f"\nImported. Verify with scripts/audit_course_content.py")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--file", required=True)
    p.add_argument("--apply", action="store_true", help="write (default is dry run)")
    p.add_argument("--dsn", default=os.getenv("DATABASE_URL", "").replace("+asyncpg", ""))
    args = p.parse_args()
    if not args.dsn:
        sys.exit("set --dsn or DATABASE_URL")
    asyncio.run(main(args.dsn, args.file, args.apply))
