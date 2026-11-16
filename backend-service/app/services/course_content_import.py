import copy
import json
import uuid
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from sqlalchemy import Table, and_, func, literal_column, or_, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db_types import GUID, GUIDArray, PortableJSON
from app.models.course import (
    Course,
    Lesson,
    Unit,
    count_exercises,
    sync_exercise_types,
)
from app.models.course_category import CourseCategory

FILE_FORMAT = 1
TABLES: dict[str, Table] = {
    "course_categories": CourseCategory.__table__,
    "courses": Course.__table__,
    "units": Unit.__table__,
    "lessons": Lesson.__table__,
}
KEPT_ON_UPDATE = {"id", "created_at"}
# Counters the importer derives from the rows it lands; a stale value in a file must not win.
DERIVED_COLUMNS = {
    "course_categories": {"course_count"},
    "courses": {"total_lessons"},
    "units": {"total_lessons"},
}


@dataclass
class ImportReport:
    counts: dict[str, Counter] = field(
        default_factory=lambda: {t: Counter() for t in TABLES}
    )
    remapped_categories: int = 0
    ignored_columns: set[str] = field(default_factory=set)
    derived_rows: int = 0

    def total(self, outcome: str) -> int:
        return sum(c[outcome] for c in self.counts.values())

    def lines(self) -> list[str]:
        out = [
            f"  {table}: {c['inserted']} inserted, {c['updated']} updated, {c['skipped']} unchanged"
            for table, c in self.counts.items()
        ]
        out.append(f"  categories reused from target by name/slug: {self.remapped_categories}")
        out.append(f"  derived counters corrected: {self.derived_rows}")
        if self.ignored_columns:
            out.append(f"  columns in files but not in the schema (ignored): {sorted(self.ignored_columns)}")
        return out


def load_course_dir(path: Path) -> list[dict[str, Any]]:
    documents = []
    for file in sorted(path.glob("*.json")):
        document = json.loads(file.read_text(encoding="utf-8"))
        if document.get("format") != FILE_FORMAT:
            raise ValueError(f"{file.name}: unsupported format {document.get('format')!r}")
        documents.append(document)
    return documents


def documents_from_monolith(payload: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    categories = {c["id"]: c for c in payload.get("course_categories", [])}
    documents = []
    for course in payload["courses"]:
        documents.append(
            {
                "format": FILE_FORMAT,
                "category": categories.get(course.get("category_id")),
                "course": course,
                "units": [u for u in payload["units"] if u["course_id"] == course["id"]],
                "lessons": [l for l in payload["lessons"] if l["course_id"] == course["id"]],
            }
        )
    return documents


def _coerce(column_type: Any, value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, dict) and "__dt__" in value:
        return datetime.fromisoformat(value["__dt__"])
    if isinstance(column_type, GUID):
        return value if isinstance(value, uuid.UUID) else uuid.UUID(value)
    if isinstance(column_type, GUIDArray):
        return [v if isinstance(v, uuid.UUID) else uuid.UUID(v) for v in value]
    if isinstance(column_type, PortableJSON) and isinstance(value, str):
        return json.loads(value)
    return value


def _prepare(table: Table, row: dict[str, Any], report: ImportReport) -> dict[str, Any]:
    report.ignored_columns |= row.keys() - table.c.keys()
    skipped = DERIVED_COLUMNS.get(table.name, set())
    values = {k: _coerce(table.c[k].type, v) for k, v in row.items() if k in table.c and k not in skipped}
    if table.name == "lessons":
        content = sync_exercise_types(copy.deepcopy(values.get("content")))
        values["content"] = content
        values["total_exercises"] = count_exercises(content)
    return values


async def _upsert(session: AsyncSession, table: Table, values: dict[str, Any], overwrite: bool) -> str:
    stmt = pg_insert(table).values(**values)
    if overwrite:
        changed = [k for k in values if k not in KEPT_ON_UPDATE]
        stmt = stmt.on_conflict_do_update(
            index_elements=["id"],
            set_={k: stmt.excluded[k] for k in changed},
            where=or_(*[table.c[k].is_distinct_from(stmt.excluded[k]) for k in changed]),
        ).returning(literal_column("(xmax = 0)").label("inserted"))
        row = (await session.execute(stmt)).first()
        return "skipped" if row is None else ("inserted" if row.inserted else "updated")
    stmt = stmt.on_conflict_do_nothing(index_elements=["id"]).returning(table.c.id)
    return "inserted" if (await session.execute(stmt)).first() else "skipped"


async def _reuse_existing_category(session: AsyncSession, category: dict[str, Any]) -> uuid.UUID | None:
    table = CourseCategory.__table__
    return await session.scalar(
        select(table.c.id).where(
            or_(table.c.name == category["name"], table.c.slug == category.get("slug"))
        )
    )


async def refresh_derived_fields(
    session: AsyncSession, course_ids: set[uuid.UUID], category_ids: set[uuid.UUID]
) -> int:
    """Counters that raw SQL inserts bypass; touches only rows whose value is wrong."""
    fixed = 0
    unit, course, category = Unit.__table__, Course.__table__, CourseCategory.__table__
    lesson = Lesson.__table__

    def _lessons_in(column: Any, key: Any) -> Any:
        return select(func.count()).where(column == key).scalar_subquery()

    if course_ids:
        unit_count = _lessons_in(lesson.c.unit_id, unit.c.id)
        result = await session.execute(
            update(unit)
            .where(and_(unit.c.course_id.in_(course_ids), unit.c.total_lessons.is_distinct_from(unit_count)))
            .values(total_lessons=unit_count, updated_at=unit.c.updated_at)
        )
        fixed += result.rowcount
        course_count = _lessons_in(lesson.c.course_id, course.c.id)
        result = await session.execute(
            update(course)
            .where(and_(course.c.id.in_(course_ids), course.c.total_lessons.is_distinct_from(course_count)))
            .values(total_lessons=course_count, updated_at=course.c.updated_at)
        )
        fixed += result.rowcount
    if category_ids:
        published = (
            select(func.count())
            .where(course.c.category_id == category.c.id, course.c.is_published.is_(True))
            .scalar_subquery()
        )
        result = await session.execute(
            update(category)
            .where(and_(category.c.id.in_(category_ids), category.c.course_count.is_distinct_from(published)))
            .values(course_count=published, updated_at=category.c.updated_at)
        )
        fixed += result.rowcount
    return fixed


async def import_documents(
    session: AsyncSession, documents: list[dict[str, Any]], *, overwrite: bool = False
) -> ImportReport:
    """Insert course files by their own ids; with overwrite, upsert on id.

    Caller owns the transaction. Rows are never deleted, and users, enrolments and
    progress are never touched.
    """
    report = ImportReport()
    touched_courses: set[uuid.UUID] = set()
    touched_categories: set[uuid.UUID] = set()
    category_map: dict[str, uuid.UUID] = {}

    async def put(name: str, row: dict[str, Any], course_id: Any) -> str:
        outcome = await _upsert(session, TABLES[name], _prepare(TABLES[name], row, report), overwrite)
        report.counts[name][outcome] += 1
        if outcome != "skipped" and course_id is not None:
            touched_courses.add(uuid.UUID(str(course_id)))
        return outcome

    for document in documents:
        category = document.get("category")
        if not category or category["id"] in category_map:
            continue
        table = CourseCategory.__table__
        exists = await session.scalar(select(table.c.id).where(table.c.id == uuid.UUID(category["id"])))
        reused = None if exists else await _reuse_existing_category(session, category)
        if reused:
            category_map[category["id"]] = reused
            report.remapped_categories += 1
            continue
        category_map[category["id"]] = uuid.UUID(category["id"])
        outcome = await _upsert(session, table, _prepare(table, category, report), overwrite)
        report.counts["course_categories"][outcome] += 1
        if outcome != "skipped":
            touched_categories.add(category_map[category["id"]])

    for document in documents:
        course = dict(document["course"])
        if course.get("category_id") in category_map:
            course["category_id"] = str(category_map[course["category_id"]])
        await put("courses", course, course["id"])
    for document in documents:
        for unit in document["units"]:
            await put("units", unit, unit["course_id"])
    for document in documents:
        for lesson in document["lessons"]:
            await put("lessons", lesson, lesson["course_id"])

    for document in documents:
        mapped = category_map.get(document["course"].get("category_id"))
        if mapped and uuid.UUID(document["course"]["id"]) in touched_courses:
            touched_categories.add(mapped)

    report.derived_rows = await refresh_derived_fields(session, touched_courses, touched_categories)
    return report
