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
