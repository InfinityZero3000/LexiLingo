"""The "XP today" a learner sees is the XP they earned today, from every source."""

from datetime import datetime, timezone

from app.models.progress import DailyActivity


async def _lesson_xp_today(db_session, user, xp: int) -> None:
    user.total_xp = xp
    db_session.add(
        DailyActivity(user_id=user.id, activity_date=datetime.now(timezone.utc).date(), xp_earned=xp)
    )
    await db_session.commit()


async def test_profile_counts_lesson_xp_not_only_transactions(
    async_client, auth_headers, test_user, db_session
):
    await _lesson_xp_today(db_session, test_user, 80)

    response = await async_client.get("/api/v1/xp/profile", headers=auth_headers)

    assert response.json()["daily_xp_today"] == 80


async def test_award_response_adds_to_the_real_total(
    async_client, auth_headers, test_user, db_session
):
    await _lesson_xp_today(db_session, test_user, 80)

    response = await async_client.post(
        "/api/v1/xp/award",
        json={"source": "news", "base_xp": 10, "source_id": "article-1"},
        headers=auth_headers,
    )

    body = response.json()
    assert body["daily_xp_today"] == 80 + body["xp_awarded"]
