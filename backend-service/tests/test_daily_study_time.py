"""Study time on DailyActivity.

Every creator of this row used to pass `study_time_minutes=0` and nothing ever
added to it, so the progress page reported zero study time however much anyone
practised. These lock in that a finished activity contributes real minutes.
"""

import uuid
from datetime import date

import pytest

from app.models.gamification import LeaderboardEntry
from app.models.progress import DailyActivity
from app.services.streak_service import record_daily_activity
from app.services.xp_service import (
    MAX_STUDY_MINUTES_PER_AWARD,
    _clamped_study_minutes,
)


class _FakeSession:
    """Enough of AsyncSession for record_daily_activity's staged-row path.

    `record_daily_activity` also credits the weekly leaderboard, and that row is
    not pre-staged here, so the query it runs must answer "no entry yet".
    """

    def __init__(self, staged=()):
        self.new = list(staged)

    def add(self, obj):
        if obj not in self.new:
            self.new.append(obj)

    async def execute(self, _stmt):
        class _Empty:
            @staticmethod
            def scalar_one_or_none():
                return None

        return _Empty()

    @property
    def leaderboard(self):
        return [r for r in self.new if isinstance(r, LeaderboardEntry)]


def _row(user_id, **kw):
    defaults = dict(
        user_id=user_id,
        activity_date=date.today(),
        xp_earned=0,
        lessons_completed=0,
        study_time_minutes=0,
        vocabulary_reviewed=0,
        daily_goal_xp=20,
    )
    defaults.update(kw)
    return DailyActivity(**defaults)


@pytest.mark.asyncio
async def test_minutes_accumulate_across_activities():
    user_id = uuid.uuid4()
    row = _row(user_id)
    db = _FakeSession([row])

    await record_daily_activity(db, user_id, study_time_minutes=7, today=date.today())
    await record_daily_activity(db, user_id, study_time_minutes=5, today=date.today())

    assert row.study_time_minutes == 12


@pytest.mark.asyncio
async def test_every_counter_is_additive():
    user_id = uuid.uuid4()
    row = _row(user_id, xp_earned=5, lessons_completed=1, vocabulary_reviewed=2)
    db = _FakeSession([row])

    await record_daily_activity(
        db,
        user_id,
        xp_earned=10,
        lessons_completed=1,
        vocabulary_reviewed=3,
        today=date.today(),
    )

    assert (row.xp_earned, row.lessons_completed, row.vocabulary_reviewed) == (15, 2, 5)


@pytest.mark.asyncio
async def test_daily_goal_flips_once_xp_reaches_the_target():
    user_id = uuid.uuid4()
    row = _row(user_id, xp_earned=15, daily_goal_xp=20)
    db = _FakeSession([row])

    await record_daily_activity(db, user_id, xp_earned=5, today=date.today())

    assert row.daily_goal_met is True


@pytest.mark.parametrize(
    "seconds, expected",
    [
        (None, 0),
        (0, 0),
        (-30, 0),
        (59, 0),
        (60, 1),
        (600, 10),
    ],
)
def test_clamped_study_minutes_converts_seconds(seconds, expected):
    assert _clamped_study_minutes(seconds) == expected


def test_a_forged_duration_cannot_inflate_the_stat():
    """duration_seconds on /xp/award is client-supplied and unverified."""
    assert _clamped_study_minutes(24 * 60 * 60) == MAX_STUDY_MINUTES_PER_AWARD


@pytest.mark.asyncio
async def test_xp_also_credits_the_weekly_leaderboard():
    """Only 2 of 8 XP writers updated it, so lesson+vocab learners ranked at 0."""
    user_id = uuid.uuid4()
    db = _FakeSession([_row(user_id)])

    await record_daily_activity(db, user_id, xp_earned=30, today=date.today())

    assert [e.xp_earned for e in db.leaderboard] == [30]
    assert db.leaderboard[0].user_id == user_id


@pytest.mark.asyncio
async def test_an_activity_worth_no_xp_creates_no_leaderboard_row():
    user_id = uuid.uuid4()
    db = _FakeSession([_row(user_id)])

    await record_daily_activity(db, user_id, study_time_minutes=5, today=date.today())

    assert db.leaderboard == []
