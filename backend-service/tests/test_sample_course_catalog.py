"""Quality checks for courses inserted by the development seed endpoint."""

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.sample_data_catalog import SAMPLE_COURSE_CATEGORIES, SAMPLE_COURSES
from app.models.course import Course, Lesson, Unit, exercise_shape_problems
from app.models.course_category import CourseCategory


def test_sample_course_catalog_is_consistent_and_playable():
    category_slugs = [category["slug"] for category in SAMPLE_COURSE_CATEGORIES]
    course_titles = [course["title"] for course in SAMPLE_COURSES]
    exercise_ids: list[str] = []

    assert len(category_slugs) == len(set(category_slugs))
    assert len(course_titles) == len(set(course_titles))

    for course in SAMPLE_COURSES:
        assert course["category_slug"] in category_slugs
        lessons = [lesson for unit in course["units"] for lesson in unit["lessons"]]
        assert lessons
        assert course["total_xp"] > 0
        assert course["estimated_duration"] > 0

        for lesson in lessons:
            exercises = lesson["exercises"]
            assert exercises
            for exercise in exercises:
                assert exercise_shape_problems(exercise) == [], exercise["id"]
                exercise_ids.append(exercise["id"])

    assert len(exercise_ids) == len(set(exercise_ids))


def test_travel_course_seed_has_complete_learning_path():
    travel_course = next(
        course for course in SAMPLE_COURSES if course["title"] == "English for Travel"
    )
    lessons = travel_course["units"][0]["lessons"]

    assert travel_course["level"] == "A2"
    assert travel_course["skill"] == "speaking"
    assert len(lessons) == 3
    assert all(lesson["outcome"] for lesson in lessons)
    assert travel_course["total_xp"] == sum(lesson["xp_reward"] for lesson in lessons)
    assert sum(len(lesson["exercises"]) for lesson in lessons) == 18


@pytest.mark.asyncio
async def test_admin_seed_is_idempotent_for_travel_course(
    async_client: AsyncClient,
    super_admin_headers: dict,
    db_session: AsyncSession,
    monkeypatch,
):
    from app.routes import admin_system

    monkeypatch.setattr(admin_system.settings, "APP_ENV", "development")

    for _ in range(2):
        response = await async_client.post("/api/v1/admin/seed", headers=super_admin_headers)
        assert response.status_code == 200

    categories = list(
        (
            await db_session.execute(
                select(CourseCategory).where(CourseCategory.slug == "conversation")
            )
        ).scalars()
    )
    course_count = await db_session.scalar(
        select(func.count(Course.id)).where(Course.title == "English for Travel")
    )
    unit_count = await db_session.scalar(
        select(func.count(Unit.id))
        .join(Course, Course.id == Unit.course_id)
        .where(Course.title == "English for Travel")
    )
    lesson_count = await db_session.scalar(
        select(func.count(Lesson.id))
        .join(Unit, Unit.id == Lesson.unit_id)
        .join(Course, Course.id == Unit.course_id)
        .where(Course.title == "English for Travel")
    )

    assert len(categories) == 1
    assert categories[0].course_count == 1
    assert (course_count, unit_count, lesson_count) == (1, 1, 3)
