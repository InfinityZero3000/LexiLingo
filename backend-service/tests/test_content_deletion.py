"""Deleting admin content must never erase what learners did."""
from uuid import uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import QuestionItem, TestExam
from app.models.course import Course, Lesson, Unit
from app.models.gamification import Achievement, ShopItem, UserAchievement, UserInventory
from app.models.progress import LessonCompletion, UserCourseProgress
from app.models.user import User
from app.models.vocabulary import DifficultyLevel, PartOfSpeech, UserVocabulary, VocabularyItem


async def _save(db: AsyncSession, *rows: object) -> None:
    for row in rows:
        db.add(row)
        await db.flush()
    await db.commit()


async def _learner(db: AsyncSession) -> User:
    name = f"learner{uuid4().hex[:8]}"
    user = User(email=f"{name}@example.com", username=name, hashed_password="x")
    await _save(db, user)
    return user


async def _course(db: AsyncSession, *, published: bool = False) -> tuple[Course, Unit, Lesson]:
    course = Course(title=f"C {uuid4().hex[:6]}", language="en", level="A1", is_published=published)
    await _save(db, course)
    unit = Unit(course_id=course.id, title="U", order_index=0)
    await _save(db, unit)
    lesson = Lesson(course_id=course.id, unit_id=unit.id, title="L", order_index=0, lesson_type="lesson")
    await _save(db, lesson)
    return course, unit, lesson


async def _exists(db: AsyncSession, model: type, row_id: object) -> bool:
    return await db.scalar(select(model.id).where(model.id == row_id)) is not None


def _refusal(response) -> dict:
    assert response.status_code == 409, response.text
    return response.json()["error"]["details"]


@pytest.mark.asyncio
async def test_unused_draft_course_is_removed_with_its_lessons(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    course, unit, lesson = await _course(db_session)
    ids = (course.id, unit.id, lesson.id)

    response = await async_client.delete(f"/api/v1/admin/courses/{ids[0]}", headers=admin_headers)

    assert response.status_code == 200, response.text
    db_session.expire_all()
    for model, row_id in zip((Course, Unit, Lesson), ids):
        assert not await _exists(db_session, model, row_id)


@pytest.mark.asyncio
async def test_published_course_must_be_unpublished_first(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    course, _, _ = await _course(db_session, published=True)
    course_id = course.id

    response = await async_client.delete(f"/api/v1/admin/courses/{course_id}", headers=admin_headers)

    assert _refusal(response)["reason"] == "published"
    assert await _exists(db_session, Course, course_id)


@pytest.mark.asyncio
async def test_enrolment_keeps_a_course(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    course, _, _ = await _course(db_session)
    learner = await _learner(db_session)
    course_id = course.id
    await _save(db_session, UserCourseProgress(user_id=learner.id, course_id=course_id))

    response = await async_client.delete(f"/api/v1/admin/courses/{course_id}", headers=admin_headers)

    assert _refusal(response) == {"reason": "in_use", "usage": {"enrolled_learners": 1}}
    assert await _exists(db_session, Course, course_id)


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["courses", "units", "lessons"])
async def test_a_lesson_record_keeps_everything_above_it(
    kind: str, async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    course, unit, lesson = await _course(db_session)
    learner = await _learner(db_session)
    ids = {"courses": course.id, "units": unit.id, "lessons": lesson.id}
    await _save(db_session, LessonCompletion(user_id=learner.id, lesson_id=lesson.id))

    response = await async_client.delete(f"/api/v1/admin/{kind}/{ids[kind]}", headers=admin_headers)

    assert _refusal(response)["usage"] == {"learners_with_lesson_records": 1}
    assert await _exists(db_session, Lesson, ids["lessons"])


@pytest.mark.asyncio
async def test_used_vocabulary_badge_and_shop_item_are_kept(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    learner = await _learner(db_session)
    word = VocabularyItem(word=f"w{uuid4().hex[:6]}", definition="d",
                          part_of_speech=PartOfSpeech.NOUN, difficulty_level=DifficultyLevel.A1)
    badge = Achievement(name=f"B {uuid4().hex[:6]}", description="d", condition_type="xp",
                        condition_value=1, category="xp")
    item = ShopItem(name=f"I {uuid4().hex[:6]}", description="d", item_type="hint", price_gems=5)
    await _save(db_session, word, badge, item)
    cases = [("vocabulary", VocabularyItem, word.id), ("achievements", Achievement, badge.id),
             ("shop", ShopItem, item.id)]
    await _save(
        db_session,
        UserVocabulary(user_id=learner.id, vocabulary_id=word.id),
        UserAchievement(user_id=learner.id, achievement_id=badge.id),
        UserInventory(user_id=learner.id, shop_item_id=item.id),
    )

    for path, model, row_id in cases:
        response = await async_client.delete(f"/api/v1/admin/{path}/{row_id}", headers=admin_headers)
        assert _refusal(response)["reason"] == "in_use", path
        assert await _exists(db_session, model, row_id), path


@pytest.mark.asyncio
async def test_a_question_on_a_paper_is_kept_until_the_paper_drops_it(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    question = QuestionItem(prompt="p?", question_type="multiple_choice", difficulty_level="A1",
                            options=["a", "b"], answer={"value": "a"})
    await _save(db_session, question)
    question_id = question.id
    exam = TestExam(title="T", question_ids=[str(question_id)])
    await _save(db_session, exam)

    url = f"/api/v1/admin/questions/{question_id}"
    assert _refusal(await async_client.delete(url, headers=admin_headers))["usage"] == {"test_exams": 1}

    exam.question_ids = []
    await db_session.commit()
    assert (await async_client.delete(url, headers=admin_headers)).status_code == 200
