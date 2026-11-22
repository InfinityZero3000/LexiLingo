import pytest

from app.models.course import Lesson
from app.models.progress import LessonAttempt, LessonCompletion, UserProgress
from app.services.lessons_completed import count_completed_lessons

ME = "/api/v1/users/me"


async def extra_lesson(db_session, lesson, order_index: int) -> Lesson:
    other = Lesson(
        course_id=lesson.course_id, unit_id=lesson.unit_id, title=f"Lesson {order_index}",
        order_index=order_index, lesson_type="vocabulary", xp_reward=10, pass_threshold=70,
        content=lesson.content,
    )
    db_session.add(other)
    await db_session.commit()
    await db_session.refresh(other)
    return other


@pytest.mark.asyncio
async def test_new_learner_has_zero(async_client, auth_headers):
    body = (await async_client.get(ME, headers=auth_headers)).json()
    assert body["lessons_completed"] == 0


@pytest.mark.asyncio
async def test_only_passed_work_counts_and_a_lesson_counts_once(
    async_client, auth_headers, db_session, test_user, test_lesson, test_course
):
    second = await extra_lesson(db_session, test_lesson, 1)
    third = await extra_lesson(db_session, test_lesson, 2)
    uid, cid = test_user.id, test_course.id
    db_session.add_all([
        UserProgress(user_id=uid, lesson_id=test_lesson.id, course_id=cid, status="in_progress"),
        LessonAttempt(user_id=uid, lesson_id=test_lesson.id, passed=False),
        LessonCompletion(user_id=uid, lesson_id=second.id, is_passed=False),
    ])
    await db_session.commit()
    assert await count_completed_lessons(db_session, uid) == 0
    assert (await async_client.get(ME, headers=auth_headers)).json()["lessons_completed"] == 0

    db_session.add_all([
        LessonCompletion(user_id=uid, lesson_id=test_lesson.id, is_passed=True),
        LessonAttempt(user_id=uid, lesson_id=test_lesson.id, passed=True),
        UserProgress(user_id=uid, lesson_id=third.id, course_id=cid, status="completed"),
    ])
    await db_session.commit()
    assert (await async_client.get(ME, headers=auth_headers)).json()["lessons_completed"] == 2


@pytest.mark.asyncio
async def test_other_learners_work_is_not_counted(
    async_client, auth_headers, db_session, test_lesson
):
    from app.models.user import User

    other = User(email="o@example.com", username="otheruser", hashed_password="x")
    db_session.add(other)
    await db_session.commit()
    db_session.add(LessonCompletion(user_id=other.id, lesson_id=test_lesson.id, is_passed=True))
    await db_session.commit()
    assert (await async_client.get(ME, headers=auth_headers)).json()["lessons_completed"] == 0


@pytest.mark.asyncio
async def test_put_me_carries_the_count_too(
    async_client, auth_headers, db_session, test_user, test_lesson
):
    db_session.add(LessonCompletion(user_id=test_user.id, lesson_id=test_lesson.id, is_passed=True))
    await db_session.commit()
    r = await async_client.put(ME, headers=auth_headers, json={"display_name": "New Name"})
    assert r.status_code == 200, r.text
    assert r.json()["lessons_completed"] == 1
