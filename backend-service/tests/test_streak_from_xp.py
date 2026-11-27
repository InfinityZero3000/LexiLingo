"""Where activity is recorded is where the day is credited."""

from sqlalchemy import select

from app.models.progress import Streak
from app.services.xp_service import award_xp_transaction


async def _streak(db_session, user):
    return (await db_session.execute(select(Streak).where(Streak.user_id == user.id))).scalar_one_or_none()


async def test_xp_from_a_youtube_chunk_credits_the_streak(db_session, test_user):
    await award_xp_transaction(db=db_session, user=test_user, source="youtube", base_xp=5, source_id="v:0")

    streak = await _streak(db_session, test_user)
    assert streak is not None and streak.current_streak == 1


async def test_a_second_award_the_same_day_does_not_count_twice(db_session, test_user):
    await award_xp_transaction(db=db_session, user=test_user, source="youtube", base_xp=5, source_id="v:0")
    await award_xp_transaction(db=db_session, user=test_user, source="youtube", base_xp=5, source_id="v:1")

    assert (await _streak(db_session, test_user)).current_streak == 1


async def test_an_award_that_earns_nothing_credits_nothing(db_session, test_user):
    await award_xp_transaction(db=db_session, user=test_user, source="news", base_xp=0, source_id="n:0")

    assert await _streak(db_session, test_user) is None


async def test_an_achievement_is_not_activity(db_session, test_user):
    await award_xp_transaction(
        db=db_session, user=test_user, source="achievement", base_xp=50, source_id="a-1", commit=False
    )

    assert await _streak(db_session, test_user) is None
