"""The Progress screen's totals must match the account's."""

from datetime import date

from httpx import AsyncClient

from app.models.gamification import Achievement, UserAchievement
from app.models.progress import Streak


async def test_summary_reports_account_xp_streaks_and_achievements(
    async_client: AsyncClient, auth_headers: dict, test_user, db_session
):
    test_user.total_xp = 304  # lessons, reviews and quests; no course rows
    achievement = Achievement(
        name="First Steps",
        description="d",
        condition_type="lessons_completed",
        condition_value=1,
    )
    db_session.add_all(
        [
            achievement,
            Streak(
                user_id=test_user.id,
                current_streak=4,
                longest_streak=9,
                total_days_active=12,
                last_activity_date=date.today(),
            ),
        ]
    )
    await db_session.flush()
    db_session.add(
        UserAchievement(user_id=test_user.id, achievement_id=achievement.id)
    )
    await db_session.commit()

    response = await async_client.get("/api/v1/progress/me", headers=auth_headers)

    assert response.status_code == 200, response.text
    summary = response.json()["data"]["summary"]
    assert (
        summary["total_xp"],
        summary["current_streak"],
        summary["longest_streak"],
        summary["achievements_unlocked"],
    ) == (304, 4, 9, 1)
