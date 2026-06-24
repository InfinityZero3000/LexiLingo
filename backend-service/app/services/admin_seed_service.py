"""Seeding logic for the dev-only /admin/seed endpoint, split by data type."""

import copy
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.sample_data_catalog import (
    SAMPLE_ACHIEVEMENTS,
    SAMPLE_COURSE_CATEGORIES,
    SAMPLE_COURSES,
)
from app.core.shop_catalog import SHOP_CATALOG
from app.models.course import Course, Lesson, Unit
from app.models.course_category import CourseCategory
from app.models.gamification import Achievement, ShopItem


async def seed_achievements(db: AsyncSession) -> int:
    created = 0
    for ach_data in SAMPLE_ACHIEVEMENTS:
        result = await db.execute(
            select(Achievement).where(Achievement.name == ach_data["name"])
        )
        if not result.scalar_one_or_none():
            db.add(Achievement(**ach_data))
            created += 1
    return created


async def seed_shop_items(db: AsyncSession) -> int:
    created = 0
    for item_data in SHOP_CATALOG:
        result = await db.execute(
            select(ShopItem).where(ShopItem.name == item_data["name"])
        )
        existing_item = result.scalar_one_or_none()
        if not existing_item:
            db.add(ShopItem(**item_data))
            created += 1
        else:
            for field, value in item_data.items():
                setattr(existing_item, field, value)
    return created


async def seed_course_categories(db: AsyncSession) -> tuple[int, dict[str, UUID]]:
    created = 0
    category_ids: dict[str, UUID] = {}
    for category_data in SAMPLE_COURSE_CATEGORIES:
        result = await db.execute(
            select(CourseCategory).where(CourseCategory.slug == category_data["slug"])
        )
        category = result.scalar_one_or_none()
        if not category:
            category = CourseCategory(**category_data)
            db.add(category)
            await db.flush()
            created += 1
        category_ids[category_data["slug"]] = category.id
    return created, category_ids


async def seed_courses(
    db: AsyncSession, category_ids: dict[str, UUID]
) -> tuple[int, int, int]:
    """Returns (courses_created, units_created, lessons_created)."""
    courses_created = 0
    units_created = 0
    lessons_created = 0

    # SAMPLE_COURSES is a module-level constant mutated in place below
    # (.pop on units/exercises) — deep-copy so repeated calls stay idempotent.
    for course_data in copy.deepcopy(SAMPLE_COURSES):
        result = await db.execute(
            select(Course).where(Course.title == course_data["title"])
        )
        existing_course = result.scalar_one_or_none()
        if existing_course:
            await db.delete(existing_course)
            await db.flush()

        unit_seed = course_data.pop("units")
        category_slug = course_data.pop("category_slug")

        course = Course(
            **course_data,
            category_id=category_ids.get(category_slug),
            total_lessons=sum(len(unit["lessons"]) for unit in unit_seed),
            is_published=True,
        )
        db.add(course)
        await db.flush()
        courses_created += 1

        for unit_data in unit_seed:
            lesson_seed = unit_data.pop("lessons")
            unit = Unit(
                **unit_data,
                course_id=course.id,
                total_lessons=len(lesson_seed),
            )
            db.add(unit)
            await db.flush()
            units_created += 1

            for lesson_data in lesson_seed:
                exercises = lesson_data.pop("exercises", [])
                lesson = Lesson(
                    **lesson_data,
                    course_id=course.id,
                    unit_id=unit.id,
                    content={"exercises": exercises, "version": 1},
                    pass_threshold=70,
                    lesson_type="lesson",
                )
                db.add(lesson)
                lessons_created += 1

    return courses_created, units_created, lessons_created
