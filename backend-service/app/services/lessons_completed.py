"""Count of distinct lessons a learner has completed, by the activation funnel's rule."""

import uuid

from sqlalchemy import func, select, union_all
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.progress import LessonAttempt, LessonCompletion, UserProgress


async def count_completed_lessons(db: AsyncSession, user_id: uuid.UUID) -> int:
    passed = union_all(
        select(LessonCompletion.lesson_id).where(
            LessonCompletion.user_id == user_id, LessonCompletion.is_passed.is_(True)
        ),
        select(LessonAttempt.lesson_id).where(
            LessonAttempt.user_id == user_id, LessonAttempt.passed.is_(True)
        ),
        select(UserProgress.lesson_id).where(
            UserProgress.user_id == user_id, UserProgress.status == "completed"
        ),
    ).subquery()
    result = await db.execute(select(func.count(func.distinct(passed.c.lesson_id))))
    return int(result.scalar() or 0)
