"""The category page must list what the course list groups under that category."""
from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.database import Base
from app.crud.course_category import CourseCategoryCRUD
from app.models.course import Course
from app.models.course_category import CourseCategory


@pytest_asyncio.fixture
async def db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(
            lambda c: Base.metadata.create_all(
                c, tables=[CourseCategory.__table__, Course.__table__]
            )
        )
    async with async_sessionmaker(engine, expire_on_commit=False)() as session:
        yield session
    await engine.dispose()


def _course(title: str, **kwargs) -> Course:
    return Course(
        id=uuid4(), title=title, language="en", level="A1", is_published=True, **kwargs
    )


@pytest.mark.asyncio
async def test_courses_are_found_by_tag_as_well_as_by_link(db):
    ielts = CourseCategory(id=uuid4(), name="IELTS Preparation", slug="test-prep")
    db.add_all(
        [
            ielts,
            _course("Linked", category_id=ielts.id, tags=["grammar"]),
            _course("Tagged by slug", tags=["ielts", "test-prep"]),
            _course("Tagged by name", tags=["ielts preparation"]),
            _course("Other", tags=["grammar"]),
            _course("Untagged"),
            Course(
                id=uuid4(),
                title="Draft",
                language="en",
                level="A1",
                is_published=False,
                tags=["test-prep"],
            ),
        ]
    )
    await db.commit()

    courses, total = await CourseCategoryCRUD.get_courses_by_category(db, ielts.id)

    assert total == 3
    assert {c.title for c in courses} == {"Linked", "Tagged by slug", "Tagged by name"}


@pytest.mark.asyncio
async def test_paging_counts_every_match(db):
    grammar = CourseCategory(id=uuid4(), name="Grammar", slug="grammar")
    db.add_all([grammar, *[_course(f"G{i}", tags=["grammar"]) for i in range(5)]])
    await db.commit()

    page, total = await CourseCategoryCRUD.get_courses_by_category(
        db, grammar.id, skip=4, limit=2
    )

    assert (len(page), total) == (1, 5)
