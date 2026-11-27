"""POST /progress/streak/update must not credit a day with nothing done in it."""

from datetime import datetime, timezone

from sqlalchemy import select

from app.models.progress import DailyActivity, Streak

URL = "/api/v1/progress/streak/update"


async def test_a_day_with_no_activity_does_not_start_a_streak(async_client, auth_headers, test_user, db_session):
    response = await async_client.post(URL, headers=auth_headers)

    assert response.status_code == 200
    data = response.json()["data"]
    assert (data["current_streak"], data["streak_increased"]) == (0, False)
    assert (await db_session.execute(select(Streak).where(Streak.user_id == test_user.id))).scalar_one_or_none() is None


async def test_a_day_with_xp_or_a_passed_lesson_counts(async_client, auth_headers, test_user, db_session):
    db_session.add(
        DailyActivity(user_id=test_user.id, activity_date=datetime.now(timezone.utc).date(), lessons_completed=1)
    )
    await db_session.commit()

    data = (await async_client.post(URL, headers=auth_headers)).json()["data"]

    assert (data["current_streak"], data["streak_increased"]) == (1, True)
