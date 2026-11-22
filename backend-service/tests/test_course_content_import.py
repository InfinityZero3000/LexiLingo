import asyncio
import copy
import os
import subprocess
import sys
import uuid
from collections.abc import Awaitable, Callable
from pathlib import Path

import pytest
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine
from sqlalchemy.pool import NullPool

from app.models.course import Course, Lesson, Unit
from app.models.course_category import CourseCategory
from app.services.course_content_import import (
    TABLES,
    import_documents,
    load_course_dir,
)

BACKEND_ROOT = Path(__file__).resolve().parents[1]
COURSES_DIR = BACKEND_ROOT / "content" / "courses"
SCRIPT = BACKEND_ROOT / "scripts" / "import_course_content.py"
DRILL_URL = os.getenv("RESTORE_DRILL_DATABASE_URL")


async def _snapshot(session: AsyncSession) -> dict[str, list[dict]]:
    out = {}
    for name, table in TABLES.items():
        rows = (await session.execute(select(table).order_by(table.c.id))).mappings().all()
        out[name] = [dict(r) for r in rows]
    return out


async def _import(engine: AsyncEngine, documents: list[dict], **kwargs):
    async with AsyncSession(engine, expire_on_commit=False) as session:
        report = await import_documents(session, documents, **kwargs)
        await session.commit()
    return report


async def _drill(engine: AsyncEngine, restore: Callable[[], Awaitable[None]] | None = None) -> None:
    documents = load_course_dir(COURSES_DIR)
    lesson_total = sum(len(d["lessons"]) for d in documents)

    if restore:
        await restore()
    else:
        first = await _import(engine, documents)
        assert first.counts["lessons"]["inserted"] == lesson_total
    async with AsyncSession(engine) as session:
        before = await _snapshot(session)
    assert len(before["courses"]) == len(documents)
    assert len(before["lessons"]) == lesson_total
    assert all(c["is_published"] for c in before["courses"])
    assert all(l["total_exercises"] >= 1 for l in before["lessons"])

    for overwrite in (False, True):
        again = await _import(engine, documents, overwrite=overwrite)
        assert again.total("inserted") == 0 and again.total("updated") == 0
        assert again.derived_rows == 0
        async with AsyncSession(engine) as session:
            assert await _snapshot(session) == before


@pytest.fixture
def documents() -> list[dict]:
    return copy.deepcopy(load_course_dir(COURSES_DIR)[:2])


async def test_restore_drill_on_test_schema(db_engine: AsyncEngine) -> None:
    await _drill(db_engine)


@pytest.mark.skipif(not DRILL_URL, reason="RESTORE_DRILL_DATABASE_URL points at a migrated, empty database")
async def test_restore_drill_on_migrated_schema() -> None:
    engine = create_async_engine(DRILL_URL, poolclass=NullPool)
    try:
        async with engine.connect() as conn:
            assert await conn.scalar(text("select count(*) from courses")) == 0

        async def restore_with_the_script() -> None:
            done = await asyncio.to_thread(
                subprocess.run,
                [sys.executable, str(SCRIPT), "--dir", str(COURSES_DIR), "--apply"],
                env={**os.environ, "DATABASE_URL": DRILL_URL},
                capture_output=True,
                text=True,
            )
            assert done.returncode == 0, done.stdout + done.stderr

        await _drill(engine, restore_with_the_script)
    finally:
        await engine.dispose()


async def test_default_never_overwrites_an_existing_row_and_update_does(
    db_engine: AsyncEngine, documents: list[dict]
) -> None:
    await _import(db_engine, documents)
    lesson_id = uuid.UUID(documents[0]["lessons"][0]["id"])
    async with AsyncSession(db_engine) as session:
        lesson = await session.get(Lesson, lesson_id)
        lesson.title = "edited in production"
        await session.commit()

    report = await _import(db_engine, documents)
    assert report.total("updated") == 0
    async with AsyncSession(db_engine) as session:
        assert (await session.get(Lesson, lesson_id)).title == "edited in production"

    report = await _import(db_engine, documents, overwrite=True)
    assert report.counts["lessons"]["updated"] == 1 and report.total("inserted") == 0
    async with AsyncSession(db_engine) as session:
        assert (await session.get(Lesson, lesson_id)).title == documents[0]["lessons"][0]["title"]


async def test_missing_lesson_is_added_to_an_existing_course(
    db_engine: AsyncEngine, documents: list[dict]
) -> None:
    doc = documents[0]
    dropped = doc["lessons"].pop()
    await _import(db_engine, [doc])
    doc["lessons"].append(dropped)

    report = await _import(db_engine, [doc])
    assert report.counts["lessons"]["inserted"] == 1
    async with AsyncSession(db_engine) as session:
        course = await session.get(Course, uuid.UUID(doc["course"]["id"]))
        assert course.total_lessons == len(doc["lessons"])


async def test_derived_fields_are_recomputed_not_trusted(
    db_engine: AsyncEngine, documents: list[dict]
) -> None:
    doc = documents[0]
    lesson = doc["lessons"][0]
    exercise = lesson["content"]["exercises"][0]
    exercise["type"] = exercise["ui_type"]
    lesson["total_exercises"] = 0
    doc["course"]["total_lessons"] = 999
    doc["units"][0]["total_lessons"] = 999
    doc["category"]["course_count"] = 999

    report = await _import(db_engine, [doc])
    assert report.derived_rows >= 3

    async with AsyncSession(db_engine) as session:
        stored = await session.get(Lesson, uuid.UUID(lesson["id"]))
        assert stored.total_exercises == len(lesson["content"]["exercises"])
        from app.models.course import base_type_for

        assert stored.content["exercises"][0]["type"] == base_type_for(exercise["ui_type"])
        unit = await session.get(Unit, uuid.UUID(doc["units"][0]["id"]))
        assert unit.total_lessons == sum(1 for l in doc["lessons"] if l["unit_id"] == str(unit.id))
        course = await session.get(Course, uuid.UUID(doc["course"]["id"]))
        assert course.total_lessons == len(doc["lessons"])
        category = await session.get(CourseCategory, uuid.UUID(doc["category"]["id"]))
        assert category.course_count == 1


async def test_existing_category_with_same_name_is_reused(
    db_engine: AsyncEngine, documents: list[dict]
) -> None:
    doc = documents[0]
    existing_id = uuid.uuid4()
    existing = CourseCategory(id=existing_id, name=doc["category"]["name"], slug=doc["category"]["slug"])
    async with AsyncSession(db_engine) as session:
        session.add(existing)
        await session.commit()

    report = await _import(db_engine, [doc])
    assert report.remapped_categories == 1
    async with AsyncSession(db_engine) as session:
        course = await session.get(Course, uuid.UUID(doc["course"]["id"]))
        assert course.category_id == existing_id
        assert len((await session.execute(select(CourseCategory))).scalars().all()) == 1


async def test_dry_run_changes_nothing(db_engine: AsyncEngine, documents: list[dict]) -> None:
    async with AsyncSession(db_engine) as session:
        report = await import_documents(session, documents)
        assert report.total("inserted") > 0
        await session.rollback()
    async with AsyncSession(db_engine) as session:
        assert (await session.execute(select(Course))).first() is None
