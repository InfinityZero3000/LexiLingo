"""The result screen and the daily quests must agree with what was awarded."""

from datetime import date

from httpx import AsyncClient

from app.routes.challenges import calculate_challenge_progress

QUEST = {"id": "complete_lessons", "category": "lesson"}


async def _complete(client, headers, attempt_id) -> dict:
    response = await client.post(
        f"/api/v1/learning/attempts/{attempt_id}/complete", headers=headers
    )
    assert response.status_code == 200, response.text
    return response.json()["data"]


async def test_failed_lesson_pays_nothing_and_completes_no_quest(
    async_client: AsyncClient,
    auth_headers: dict,
    test_user,
    test_lesson_attempt,
    db_session,
):
    test_lesson_attempt.score = 60
    test_lesson_attempt.xp_earned = 48  # per-answer tally of the right answers
    await db_session.commit()
    attempt_id, user_id = test_lesson_attempt.id, test_user.id

    first = await _complete(async_client, auth_headers, attempt_id)
    replay = await _complete(async_client, auth_headers, attempt_id)

    assert first["passed"] is False
    assert (first["total_xp_earned"], replay["total_xp_earned"]) == (0, 0)
    assert await calculate_challenge_progress(db_session, user_id, QUEST, date.today()) == 0


async def test_passed_lesson_reports_its_xp_and_completes_the_quest(
    async_client: AsyncClient,
    auth_headers: dict,
    test_user,
    test_lesson_attempt,
    db_session,
):
    test_lesson_attempt.score = 100
    test_lesson_attempt.xp_earned = 24
    await db_session.commit()
    attempt_id, user_id = test_lesson_attempt.id, test_user.id

    result = await _complete(async_client, auth_headers, attempt_id)

    await db_session.refresh(test_user)
    assert result["total_xp_earned"] == 24 == test_user.total_xp
    assert await calculate_challenge_progress(db_session, user_id, QUEST, date.today()) == 1


async def test_failed_lesson_does_not_start_a_streak_or_an_active_day(
    async_client: AsyncClient,
    auth_headers: dict,
    test_user,
    test_lesson_attempt,
    db_session,
):
    from sqlalchemy import select

    from app.models.progress import DailyActivity, Streak

    test_lesson_attempt.score = 60
    await db_session.commit()
    user_id = test_user.id

    await _complete(async_client, auth_headers, test_lesson_attempt.id)

    streak = (await db_session.execute(select(Streak).where(Streak.user_id == user_id))).scalar_one_or_none()
    days = (await db_session.execute(select(DailyActivity).where(DailyActivity.user_id == user_id))).scalars().all()
    assert streak is None or streak.current_streak == 0
    assert days == []


async def test_result_carries_the_lessons_own_pass_threshold(
    async_client: AsyncClient,
    auth_headers: dict,
    test_lesson_attempt,
    db_session,
):
    from app.models.course import Lesson

    lesson = await db_session.get(Lesson, test_lesson_attempt.lesson_id)
    lesson.pass_threshold = 65.0
    test_lesson_attempt.score = 70
    await db_session.commit()

    result = await _complete(async_client, auth_headers, test_lesson_attempt.id)

    assert result["pass_threshold"] == 65
    assert result["passed"] is True


async def test_a_failed_lesson_unlocks_no_achievement(
    async_client: AsyncClient,
    auth_headers: dict,
    test_user,
    test_lesson_attempt,
    db_session,
):
    from sqlalchemy import func, select

    from app.models.gamification import Achievement, UserAchievement

    db_session.add(
        Achievement(
            slug="any-lesson", name="Any", description="d", condition_type="lesson_complete",
            condition_value=0, xp_reward=0, gems_reward=0,
        )
    )
    test_lesson_attempt.score = 60
    await db_session.commit()

    result = await _complete(async_client, auth_headers, test_lesson_attempt.id)

    assert result["achievements_unlocked"] == []
    assert (await db_session.execute(select(func.count(UserAchievement.id)))).scalar_one() == 0
