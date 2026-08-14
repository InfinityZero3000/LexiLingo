"""
Export published course content (categories → courses → units → lessons) to JSON.

Pairs with import_course_content.py. Used to move authored course content from
a development database into production, which has never had real courses —
the content exists only in a database, not in the repo.

Run:
    cd backend-service
    venv/bin/python3 scripts/export_course_content.py -o /tmp/course_content.json
"""

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path

import asyncpg

sys.path.insert(0, str(Path(__file__).parent.parent))

TABLES = {
    "course_categories": "select * from course_categories order by order_index",
    "courses": "select * from courses where is_published = true order by title",
    "units": """select u.* from units u join courses c on c.id = u.course_id
                where c.is_published = true order by u.order_index""",
    "lessons": """select l.* from lessons l join units u on u.id = l.unit_id
                  join courses c on c.id = u.course_id
                  where c.is_published = true order by l.order_index""",
}


def _encode(value):
    """asyncpg hands back UUID/datetime objects; JSON needs primitives."""
    if isinstance(value, (list, tuple)):
        return [_encode(v) for v in value]
    if hasattr(value, "isoformat"):
        return {"__dt__": value.isoformat()}
    if hasattr(value, "hex") and not isinstance(value, (bytes, str)):
        return str(value)
    return value


async def main(dsn: str, out: str) -> None:
    conn = await asyncpg.connect(dsn)
    payload = {}
    try:
        for table, query in TABLES.items():
            rows = await conn.fetch(query)
            payload[table] = [
                {k: _encode(v) for k, v in dict(r).items()} for r in rows
            ]
            print(f"  {table}: {len(rows)} rows")
    finally:
        await conn.close()

    # A lesson without exercises is unplayable and would recreate on production
    # exactly the empty-roadmap bug this export exists to fix.
    bad = [
        l["title"]
        for l in payload["lessons"]
        if not (json.loads(l["content"]) if isinstance(l["content"], str) else l["content"] or {}).get("exercises")
    ]
    if bad:
        print(f"\nREFUSING TO EXPORT: {len(bad)} lesson(s) have no exercises:")
        for t in bad[:10]:
            print(f"  - {t}")
        sys.exit(1)

    Path(out).write_text(json.dumps(payload, ensure_ascii=False))
    size = Path(out).stat().st_size
    print(f"\nWrote {out} ({size:,} bytes)")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("-o", "--out", default="/tmp/course_content.json")
    p.add_argument(
        "--dsn",
        default=os.getenv(
            "EXPORT_DSN",
            "postgresql://lexilingo:Thezero2077xx@localhost:5432/lexilingo",
        ),
    )
    args = p.parse_args()
    asyncio.run(main(args.dsn, args.out))
