"""When admin content may be deleted.

The database cascades from content into learners' rows (progress, review
schedules, badges, items bought with gems, exam attempts), so a delete that
looks like content housekeeping can erase what learners did. Content somebody
has used is never deleted; it is unpublished or hidden instead.
"""
from __future__ import annotations

from typing import Any
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import TestExam
from app.models.course import Course, Lesson
from app.models.gamification import UserAchievement, UserInventory
from app.models.ielts import IeltsAttempt
from app.models.progress import LessonAttempt, LessonCompletion, UserCourseProgress, UserProgress
from app.models.user_grammar_item import UserGrammarItem
from app.models.vocabulary import UserVocabulary

_LESSON_RECORDS = (LessonAttempt, LessonCompletion, UserProgress)


def _refuse(reason: str, message: str, usage: dict[str, int] | None = None) -> HTTPException:
    # A dict `detail` would reach the client as a Python repr.
    error = HTTPException(status_code=status.HTTP_409_CONFLICT, detail=message)
    error.details = {"reason": reason, "usage": usage or {}}
    return error


def _refuse_if_used(usage: dict[str, int]) -> None:
    used = {name: count for name, count in usage.items() if count}
    if used:
        summary = ", ".join(f"{count} {name}" for name, count in used.items())
        raise _refuse(
            "in_use",
            f"Learners depend on this ({summary}). Unpublish or hide it instead.",
            used,
        )


async def _learners(db: AsyncSession, model: Any, *where: Any) -> int:
    return await db.scalar(select(func.count(func.distinct(model.user_id))).where(*where)) or 0


async def _learners_in_lessons(db: AsyncSession, lesson_ids: list[UUID]) -> int:
    if not lesson_ids:
        return 0
    found: set[UUID] = set()
    for model in _LESSON_RECORDS:
        rows = await db.execute(select(model.user_id).where(model.lesson_id.in_(lesson_ids)).distinct())
        found.update(rows.scalars())
    return len(found)


async def _locked_lesson_ids(db: AsyncSession, *where: Any) -> list[UUID]:
    # The lock stops a learner's first record landing between the count and the delete.
    rows = await db.execute(select(Lesson.id).where(*where).with_for_update())
    return list(rows.scalars())


async def ensure_course_deletable(db: AsyncSession, course_id: UUID) -> None:
    course = await db.scalar(select(Course).where(Course.id == course_id).with_for_update())
    if course is None:
        return
    if course.is_published:
        raise _refuse("published", "Unpublish the course before deleting it.")
    lesson_ids = await _locked_lesson_ids(db, Lesson.course_id == course_id)
    _refuse_if_used({
        "enrolled_learners": await _learners(db, UserCourseProgress, UserCourseProgress.course_id == course_id),
        "learners_with_lesson_records": await _learners_in_lessons(db, lesson_ids),
    })


async def ensure_unit_deletable(db: AsyncSession, unit_id: UUID) -> None:
    lesson_ids = await _locked_lesson_ids(db, Lesson.unit_id == unit_id)
    _refuse_if_used({"learners_with_lesson_records": await _learners_in_lessons(db, lesson_ids)})


async def ensure_lesson_deletable(db: AsyncSession, lesson_id: UUID) -> None:
    lesson_ids = await _locked_lesson_ids(db, Lesson.id == lesson_id)
    _refuse_if_used({"learners_with_lesson_records": await _learners_in_lessons(db, lesson_ids)})


async def ensure_vocabulary_deletable(db: AsyncSession, vocabulary_id: UUID) -> None:
    _refuse_if_used({
        "learners_reviewing": await _learners(db, UserVocabulary, UserVocabulary.vocabulary_id == vocabulary_id),
    })


async def ensure_grammar_deletable(db: AsyncSession, grammar_id: UUID) -> None:
    _refuse_if_used({
        "learners_practising": await _learners(db, UserGrammarItem, UserGrammarItem.grammar_item_id == grammar_id),
    })


async def ensure_achievement_deletable(db: AsyncSession, achievement_id: UUID) -> None:
    _refuse_if_used({
        "learners_with_badge": await _learners(db, UserAchievement, UserAchievement.achievement_id == achievement_id),
    })


async def ensure_shop_item_deletable(db: AsyncSession, item_id: UUID) -> None:
    _refuse_if_used({
        "owners": await _learners(db, UserInventory, UserInventory.shop_item_id == item_id),
    })


async def ensure_ielts_test_deletable(db: AsyncSession, test_id: UUID) -> None:
    _refuse_if_used({"learners_with_attempts": await _learners(db, IeltsAttempt, IeltsAttempt.test_id == test_id)})


async def ensure_question_deletable(db: AsyncSession, question_id: UUID) -> None:
    # question_ids is a JSON list with no foreign key: deleting would leave a hole in the paper.
    papers = (await db.execute(select(TestExam.question_ids))).scalars()
    wanted = str(question_id)
    _refuse_if_used({
        "test_exams": sum(1 for ids in papers if ids and wanted in {str(i) for i in ids}),
    })
