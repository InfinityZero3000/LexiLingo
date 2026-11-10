"""A course may be uncategorised, but never filed under a category that does not exist."""
from uuid import uuid4

import pytest
import pytest_asyncio
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.database import Base
from app.models.course_category import CourseCategory
from app.routes.admin_courses import _require_category
from app.schemas.course import CourseCreate, CourseUpdate


@pytest_asyncio.fixture
async def db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(lambda c: Base.metadata.create_all(c, tables=[CourseCategory.__table__]))
    async with async_sessionmaker(engine, expire_on_commit=False)() as session:
        yield session
    await engine.dispose()


@pytest.mark.asyncio
async def test_uncategorised_is_allowed(db):
    await _require_category(db, None)


@pytest.mark.asyncio
async def test_an_existing_category_is_allowed(db):
    category = CourseCategory(id=uuid4(), name="Travel", slug="travel")
    db.add(category)
    await db.commit()

    await _require_category(db, category.id)


@pytest.mark.asyncio
async def test_an_unknown_category_is_a_404(db):
    with pytest.raises(HTTPException) as err:
        await _require_category(db, uuid4())
    assert err.value.status_code == 404


def test_update_distinguishes_clearing_the_category_from_not_mentioning_it():
    assert "category_id" in CourseUpdate(category_id=None).model_fields_set
    assert "category_id" not in CourseUpdate(title="x").model_fields_set


def test_create_accepts_a_category_id():
    category_id = uuid4()
    course = CourseCreate(title="t", language="en", level="A1", category_id=category_id)
    assert course.model_dump()["category_id"] == category_id
