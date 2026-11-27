"""An achievement advertises XP, so unlocking it must pay it through the one XP path."""

from sqlalchemy import func, select

from app.models.games import XPTransaction
from app.models.gamification import Achievement, LeaderboardEntry, UserAchievement
from app.models.progress import DailyActivity
from app.services.achievement_checker_service import AchievementCheckerService


async def _achievement(db_session, xp: int) -> Achievement:
    achievement = Achievement(
        slug=f"xp-{xp}",
        name="First lesson",
        description="Finish a lesson",
        condition_type="lesson_complete",
        condition_value=0,
        xp_reward=xp,
        gems_reward=0,
    )
    db_session.add(achievement)
    await db_session.commit()
    return achievement


async def test_unlock_pays_xp_once_and_every_ledger_agrees(db_session, test_user):
    achievement = await _achievement(db_session, 40)
    checker = AchievementCheckerService(db_session)

    first = await checker._unlock_achievement(test_user.id, achievement)
    again = await checker._unlock_achievement(test_user.id, achievement)
    await db_session.commit()

    assert first is not None and again is None
    await db_session.refresh(test_user)
    paid = (
        await db_session.execute(
            select(func.coalesce(func.sum(XPTransaction.amount), 0)).where(
                XPTransaction.user_id == test_user.id, XPTransaction.source == "achievement"
            )
        )
    ).scalar_one()
    daily = (await db_session.execute(select(DailyActivity.xp_earned).where(DailyActivity.user_id == test_user.id))).scalar_one()
    weekly = (await db_session.execute(select(LeaderboardEntry.xp_earned).where(LeaderboardEntry.user_id == test_user.id))).scalar_one()
    assert paid == daily == weekly == test_user.total_xp == 40


async def test_streak_and_daily_cap_do_not_distort_the_advertised_amount(db_session, test_user):
    from app.models.progress import Streak
    from datetime import date

    db_session.add(Streak(user_id=test_user.id, current_streak=40, longest_streak=40, last_activity_date=date.today()))
    db_session.add(XPTransaction(user_id=test_user.id, amount=490, base_amount=490, source="news", source_id="n1"))
    achievement = await _achievement(db_session, 100)
    await db_session.commit()

    await AchievementCheckerService(db_session)._unlock_achievement(test_user.id, achievement)
    await db_session.commit()

    paid = (await db_session.execute(select(XPTransaction.amount).where(XPTransaction.source == "achievement"))).scalar_one()
    assert paid == 100


async def test_zero_xp_achievement_writes_no_transaction(db_session, test_user):
    achievement = await _achievement(db_session, 0)
    await AchievementCheckerService(db_session)._unlock_achievement(test_user.id, achievement)
    await db_session.commit()

    assert (await db_session.execute(select(func.count(XPTransaction.id)))).scalar_one() == 0
    assert (await db_session.execute(select(func.count(UserAchievement.id)))).scalar_one() == 1


async def test_a_client_cannot_claim_the_achievement_source(async_client, auth_headers):
    response = await async_client.post(
        "/api/v1/xp/award",
        json={"source": "achievement", "base_xp": 100, "source_id": "x"},
        headers=auth_headers,
    )
    assert response.status_code == 400
