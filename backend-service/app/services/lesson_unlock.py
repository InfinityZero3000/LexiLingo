"""Sequential lesson unlock: a lesson opens once the one before it in the course is passed."""
from __future__ import annotations

import uuid
from typing import Iterable, Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.crud.course import LessonCRUD
from app.models.course import Lesson, Unit

LOCKED_DETAIL = "Lesson is locked: complete the previous lesson first"


def playable_in_order(units: Iterable[Unit]) -> list[Lesson]:
    """Playable lessons of a course, unit by unit, in learning order."""
    ordered: list[Lesson] = []
    for unit in sorted(units, key=lambda u: u.order_index):
        ordered.extend(
            sorted(
                (l for l in unit.lessons if l.exercise_count > 0),
                key=lambda l: l.order_index,
            )
        )
    return ordered


def sequence_locked_ids(
    ordered: Sequence[Lesson], passed_ids: set[uuid.UUID]
) -> set[uuid.UUID]:
    """A lesson is locked when its predecessor is not passed; a passed lesson never is."""
    locked: set[uuid.UUID] = set()
    for index, lesson in enumerate(ordered):
        if index == 0 or lesson.id in passed_ids:
            continue
        if ordered[index - 1].id not in passed_ids:
            locked.add(lesson.id)
    return locked


async def is_lesson_locked(
    db: AsyncSession, user_id: uuid.UUID, lesson: Lesson
) -> bool:
    """Whether the learner may not open this lesson yet."""
    unit = await db.get(Unit, lesson.unit_id)
    if unit is None:
        return False
    rows = await db.execute(
        select(Unit)
        .options(selectinload(Unit.lessons))
        .where(Unit.course_id == unit.course_id)
    )
    ordered = playable_in_order(rows.scalars().all())
    ids = [l.id for l in ordered]
    if lesson.id not in ids:
        return False
    passed = await LessonCRUD.get_completed_lesson_ids(db, user_id, ids)
    return lesson.id in sequence_locked_ids(ordered, passed)
