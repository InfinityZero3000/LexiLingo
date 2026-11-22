"""
Export published course content (categories → courses → units → lessons) to JSON.

Two shapes:
  -o FILE         one monolithic file (legacy, for moving content between databases)
  --split-dir DIR one <slug>.json per course, stable and diff-friendly, meant to be
                  committed under backend-service/content/courses/

Only published courses are exported, and only course content: never users,
enrolments or progress. Pairs with import_course_content.py.

Run:
    cd backend-service
    DATABASE_URL=postgresql://... venv/bin/python3 scripts/export_course_content.py \
        --split-dir content/courses
"""

import argparse
import asyncio
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

import asyncpg

sys.path.insert(0, str(Path(__file__).parent.parent))

TABLES = {
    "course_categories": "select * from course_categories order by order_index, id",
    "courses": "select * from courses where is_published = true order by title, id",
    "units": """select u.* from units u join courses c on c.id = u.course_id
                where c.is_published = true order by u.order_index, u.id""",
    "lessons": """select l.* from lessons l join units u on u.id = l.unit_id
                  join courses c on c.id = u.course_id
                  where c.is_published = true order by l.order_index, l.id""",
}

JSON_TEXT_COLUMNS = {"tags", "content"}
FILE_FORMAT = 1


def _encode(value: Any) -> Any:
    if isinstance(value, (list, tuple)):
        return [_encode(v) for v in value]
    if hasattr(value, "isoformat"):
        return {"__dt__": value.isoformat()}
    if hasattr(value, "hex") and not isinstance(value, (bytes, str)):
        return str(value)
    return value


def _row(record: Any) -> dict[str, Any]:
    return {k: _encode(v) for k, v in dict(record).items()}


def _lesson_content(lesson: dict[str, Any]) -> dict[str, Any]:
    content = lesson.get("content")
    if isinstance(content, str):
        content = json.loads(content)
    return content or {}


def lessons_without_exercises(payload: dict[str, list[dict[str, Any]]]) -> list[str]:
    return [
        l["title"]
        for l in payload["lessons"]
        if not _lesson_content(l).get("exercises")
    ]


def slugify(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    return slug or "course"


def split_payload(payload: dict[str, list[dict[str, Any]]]) -> dict[str, dict[str, Any]]:
    """One document per course, keyed by file name, with deterministic ordering."""
    categories = {c["id"]: c for c in payload["course_categories"]}
    units_by_course: dict[str, list[dict[str, Any]]] = {}
    for unit in payload["units"]:
        units_by_course.setdefault(unit["course_id"], []).append(unit)
    lessons_by_course: dict[str, list[dict[str, Any]]] = {}
    for lesson in payload["lessons"]:
        lessons_by_course.setdefault(lesson["course_id"], []).append(lesson)

    courses = sorted(payload["courses"], key=lambda c: c["id"])
    taken: dict[str, int] = {}
    for course in courses:
        taken[slugify(course["title"])] = taken.get(slugify(course["title"]), 0) + 1

    documents: dict[str, dict[str, Any]] = {}
    for course in courses:
        slug = slugify(course["title"])
        if taken[slug] > 1:
            slug = f"{slug}-{course['id'][:8]}"

        units = sorted(
            units_by_course.get(course["id"], []),
            key=lambda u: (u["order_index"], u["id"]),
        )
        unit_rank = {u["id"]: i for i, u in enumerate(units)}
        lessons = sorted(
            lessons_by_course.get(course["id"], []),
            key=lambda l: (unit_rank.get(l["unit_id"], len(units)), l["order_index"], l["id"]),
        )
        for row in (course, *lessons):
            for column in JSON_TEXT_COLUMNS & row.keys():
                if isinstance(row[column], str):
                    row[column] = json.loads(row[column])

        documents[f"{slug}.json"] = {
            "format": FILE_FORMAT,
            "category": categories.get(course.get("category_id")),
            "course": course,
            "units": units,
            "lessons": lessons,
        }
    return documents


def write_split(documents: dict[str, dict[str, Any]], out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, document in documents.items():
        text = json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2)
        (out_dir / name).write_text(text + "\n", encoding="utf-8")
    return sorted(p for p in out_dir.glob("*.json") if p.name not in documents)


async def fetch_payload(dsn: str) -> dict[str, list[dict[str, Any]]]:
    conn = await asyncpg.connect(dsn)
    payload: dict[str, list[dict[str, Any]]] = {}
    try:
        for table, query in TABLES.items():
            rows = await conn.fetch(query)
            payload[table] = [_row(r) for r in rows]
            print(f"  {table}: {len(rows)} rows")
    finally:
        await conn.close()
    return payload


async def main(dsn: str, out: str | None, split_dir: str | None) -> None:
    payload = await fetch_payload(dsn)

    # A lesson without exercises is unplayable and would recreate on production
    # exactly the empty-roadmap bug this export exists to fix.
    bad = lessons_without_exercises(payload)
    if bad:
        print(f"\nREFUSING TO EXPORT: {len(bad)} lesson(s) have no exercises:")
        for t in bad[:10]:
            print(f"  - {t}")
        sys.exit(1)

    if out:
        Path(out).write_text(json.dumps(payload, ensure_ascii=False))
        print(f"\nWrote {out} ({Path(out).stat().st_size:,} bytes)")

    if split_dir:
        documents = split_payload(payload)
        stale = write_split(documents, Path(split_dir))
        print(f"\nWrote {len(documents)} course file(s) to {split_dir}")
        for path in stale:
            print(f"  stale (no longer published, not deleted): {path.name}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("-o", "--out", help="single-file export")
    p.add_argument("--split-dir", help="one <slug>.json per published course")
    p.add_argument(
        "--dsn",
        default=(os.getenv("EXPORT_DSN") or os.getenv("DATABASE_URL", "")).replace("+asyncpg", ""),
    )
    args = p.parse_args()
    if not args.dsn:
        sys.exit("set --dsn, EXPORT_DSN or DATABASE_URL")
    if not (args.out or args.split_dir):
        sys.exit("give -o FILE and/or --split-dir DIR")
    asyncio.run(main(args.dsn, args.out, args.split_dir))
