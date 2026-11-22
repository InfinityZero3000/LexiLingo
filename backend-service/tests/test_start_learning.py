"""POST /users/me/start-learning on a real database."""
import uuid

import pytest
from sqlalchemy import func, select

from app.models.course import Course, Lesson, Unit
from app.models.progress import LessonCompletion, UserCourseProgress

URL = "/api/v1/users/me/start-learning"
EXERCISES = {"exercises": [{"id": "e1", "ui_type": "multiple_choice", "question": "q",
                            "options": ["a", "b"], "correct_answer": "a"}]}


async def _course(db, title, level, lessons=(True,), published=True):
    course = Course(id=uuid.uuid4(), title=title, language="en", level=level, is_published=published)
    unit = Unit(id=uuid.uuid4(), course_id=course.id, title="U", order_index=0)
    db.add_all([course, unit])
    await db.flush()
    ids = []
    for i, playable in enumerate(lessons):
        lesson = Lesson(
            id=uuid.uuid4(), course_id=course.id, unit_id=unit.id, title=f"L{i}",
            order_index=i, content=EXERCISES if playable else {"exercises": []},
        )
        db.add(lesson)
        ids.append(lesson.id)
    await db.commit()
    return course, ids


async def _enrollments(db, user):
    return (await db.execute(
        select(func.count()).select_from(UserCourseProgress).where(UserCourseProgress.user_id == user.id)
    )).scalar_one()


@pytest.mark.asyncio
async def test_picks_course_matching_working_level(async_client, db_session, test_user, auth_headers):
    test_user.level = "B1"
    await db_session.commit()
    await _course(db_session, "A1 course", "A1")
    b1, lessons = await _course(db_session, "B1 course", "B1")
    await _course(db_session, "C1 course", "C1")

    res = await async_client.post(URL, headers=auth_headers)

    assert res.status_code == 200, res.text
    data = res.json()["data"]
    assert data["course_id"] == str(b1.id)
    assert data["first_lesson_id"] == str(lessons[0])
    assert data["already_enrolled"] is False
    assert await _enrollments(db_session, test_user) == 1


@pytest.mark.asyncio
async def test_nearest_level_when_none_at_level(async_client, db_session, test_user, auth_headers):
    test_user.level = "B2"
    await db_session.commit()
    await _course(db_session, "A1 course", "A1")
    c1, _ = await _course(db_session, "C1 course", "C1")

    res = await async_client.post(URL, headers=auth_headers)

    assert res.json()["data"]["course_id"] == str(c1.id)


@pytest.mark.asyncio
async def test_legacy_level_falls_back_to_beginner_course(async_client, db_session, test_user, auth_headers):
    test_user.level = "beginner"
    await db_session.commit()
    a1, _ = await _course(db_session, "A1 course", "A1")
    await _course(db_session, "B2 course", "B2")

    res = await async_client.post(URL, headers=auth_headers)

    assert res.json()["data"]["course_id"] == str(a1.id)


@pytest.mark.asyncio
async def test_unplayable_lessons_and_courses_are_skipped(async_client, db_session, test_user, auth_headers):
    test_user.level = "A2"
    await db_session.commit()
    await _course(db_session, "Empty A2", "A2", lessons=(False, False))
    await _course(db_session, "Draft A2", "A2", published=False)
    mixed, lessons = await _course(db_session, "Mixed A1", "A1", lessons=(False, True))

    res = await async_client.post(URL, headers=auth_headers)

    data = res.json()["data"]
    assert data["course_id"] == str(mixed.id)
    assert data["first_lesson_id"] == str(lessons[1])


@pytest.mark.asyncio
async def test_idempotent(async_client, db_session, test_user, auth_headers):
    await _course(db_session, "A1 course", "A1")

    first = (await async_client.post(URL, headers=auth_headers)).json()["data"]
    second = (await async_client.post(URL, headers=auth_headers)).json()["data"]

    assert first["already_enrolled"] is False
    assert second["already_enrolled"] is True
    assert second["course_id"] == first["course_id"]
    assert second["first_lesson_id"] == first["first_lesson_id"]
    assert await _enrollments(db_session, test_user) == 1


@pytest.mark.asyncio
async def test_completed_first_lesson_moves_to_next(async_client, db_session, test_user, auth_headers):
    _, lessons = await _course(db_session, "A1 course", "A1", lessons=(True, True, True))
    db_session.add(LessonCompletion(user_id=test_user.id, lesson_id=lessons[0], is_passed=True, best_score=90))
    await db_session.commit()

    res = await async_client.post(URL, headers=auth_headers)

    assert res.json()["data"]["first_lesson_id"] == str(lessons[1])


@pytest.mark.asyncio
async def test_explicit_course_id(async_client, db_session, test_user, auth_headers):
    await _course(db_session, "A1 course", "A1")
    other, lessons = await _course(db_session, "C2 course", "C2")

    res = await async_client.post(URL, headers=auth_headers, json={"course_id": str(other.id)})

    data = res.json()["data"]
    assert data["course_id"] == str(other.id)
    assert data["first_lesson_id"] == str(lessons[0])


@pytest.mark.asyncio
async def test_nothing_playable_is_404_and_auth_required(async_client, db_session, auth_headers):
    await _course(db_session, "Empty", "A1", lessons=(False,))

    assert (await async_client.post(URL, headers=auth_headers)).status_code == 404
    assert (await async_client.post(URL)).status_code in (401, 403)
