from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import event

from app.models.progress import DailyActivity, LessonAttempt, Streak
from app.routes.analytics import get_engagement
from app.services.user_stats_service import get_user_stats, get_weekly_activity


class _QueryCounter:
    def __init__(self, engine):
        self.engine = engine.sync_engine
        self.count = 0

    def __enter__(self):
        event.listen(self.engine, "before_cursor_execute", self._increment)
        return self

    def __exit__(self, *_args):
        event.remove(self.engine, "before_cursor_execute", self._increment)

    def _increment(self, *_args):
        self.count += 1


@pytest.mark.asyncio
async def test_engagement_query_count_is_constant_for_52_weeks(
    db_session, admin_user, test_user
):
    today = datetime.now(timezone.utc).date()
    db_session.add_all(
        [
            DailyActivity(user_id=test_user.id, activity_date=today - timedelta(days=1)),
            DailyActivity(user_id=test_user.id, activity_date=today - timedelta(days=2)),
            DailyActivity(user_id=admin_user.id, activity_date=today - timedelta(days=1)),
        ]
    )
    await db_session.commit()

    with _QueryCounter(db_session.bind) as queries:
        result = await get_engagement(weeks=52, admin=admin_user, db=db_session)

    assert len(result["data"]) == 52
    assert result["data"][-1]["dau"] == 1
    assert result["data"][-1]["wau"] == 2
    assert result["data"][-1]["mau"] == 2
    assert queries.count == 1


@pytest.mark.asyncio
async def test_user_stats_uses_one_aggregate_query(db_session, test_user):
    db_session.add(
        Streak(user_id=test_user.id, current_streak=4, longest_streak=9)
    )
    await db_session.commit()

    with _QueryCounter(db_session.bind) as queries:
        result = await get_user_stats(db_session, test_user)

    assert result.total_xp == test_user.total_xp
    assert result.current_streak == 4
    assert result.longest_streak == 9
    assert queries.count == 1


@pytest.mark.asyncio
async def test_weekly_activity_uses_one_grouped_query(
    db_session, test_user, test_lesson
):
    now = datetime.now(timezone.utc)
    db_session.add_all(
        [
            LessonAttempt(
                user_id=test_user.id,
                lesson_id=test_lesson.id,
                finished_at=now,
                passed=True,
                xp_earned=10,
                time_spent_ms=60_000,
            ),
            LessonAttempt(
                user_id=test_user.id,
                lesson_id=test_lesson.id,
                finished_at=now - timedelta(days=6),
                passed=True,
                xp_earned=20,
                time_spent_ms=120_000,
            ),
        ]
    )
    await db_session.commit()

    with _QueryCounter(db_session.bind) as queries:
        result = await get_weekly_activity(db_session, test_user)

    assert len(result.week_data) == 7
    assert result.total_xp == 30
    assert result.total_lessons == 2
    assert result.total_study_time == 3
    assert queries.count == 1
