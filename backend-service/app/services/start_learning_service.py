"""Pick a course for a learner and find the first lesson they can play."""
import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Course, Lesson, Unit
from app.models.progress import LessonCompletion, UserCourseProgress
from app.models.user import User

CEFR_ORDER = ("A1", "A2", "B1", "B2", "C1", "C2")


@dataclass(frozen=True)
class StartTarget:
    course: Course
    lesson_id: uuid.UUID


def _level_rank(level: str | None) -> int:
    text = (level or "").strip().upper()
    return CEFR_ORDER.index(text) if text in CEFR_ORDER else 0


async def _first_open_lesson(
    db: AsyncSession, user_id: uuid.UUID, course_id: uuid.UUID
) -> uuid.UUID | None:
    rows = (
        await db.execute(
            select(Lesson)
            .join(Unit, Lesson.unit_id == Unit.id)
            .where(Lesson.course_id == course_id)
            .order_by(Unit.order_index, Lesson.order_index, Lesson.id)
        )
    ).scalars().all()
    playable = [lesson for lesson in rows if lesson.exercise_count > 0]
    if not playable:
        return None
    done = set(
        (
            await db.execute(
                select(LessonCompletion.lesson_id).where(
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.is_passed.is_(True),
                    LessonCompletion.lesson_id.in_([lesson.id for lesson in playable]),
                )
            )
        ).scalars().all()
    )
    return next((lesson.id for lesson in playable if lesson.id not in done), None)


async def find_start_target(
    db: AsyncSession, user: User, course_id: uuid.UUID | None = None
) -> StartTarget | None:
    if course_id is not None:
        course = (
            await db.execute(
                select(Course).where(Course.id == course_id, Course.is_published.is_(True))
            )
        ).scalar_one_or_none()
        if course is None:
            return None
        lesson_id = await _first_open_lesson(db, user.id, course.id)
        return StartTarget(course, lesson_id) if lesson_id else None

    courses = list(
        (await db.execute(select(Course).where(Course.is_published.is_(True)))).scalars().all()
    )
    target_language = (getattr(user, "target_language", None) or "").strip().lower()
    same_language = [c for c in courses if (c.language or "").lower() == target_language]
    courses = same_language or courses

    enrolled = set(
        (
            await db.execute(
                select(UserCourseProgress.course_id).where(UserCourseProgress.user_id == user.id)
            )
        ).scalars().all()
    )
    want = _level_rank(user.level)
    courses.sort(
        key=lambda c: (
            abs(_level_rank(c.level) - want),
            _level_rank(c.level),
            c.id not in enrolled,
            c.created_at,
            str(c.id),
        )
    )
    for course in courses:
        lesson_id = await _first_open_lesson(db, user.id, course.id)
        if lesson_id:
            return StartTarget(course, lesson_id)
    return None
