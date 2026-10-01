"""GET /xp/content-activity — what the learner was actually credited for.

Read off XPTransaction, the immutable row each award already writes, so what a
learner sees here is exactly what the system counted. A source missing from the
totals is evidence the activity never registered, not a reporting gap.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.games import XPTransaction
from app.models.user import User
from app.routes.xp import CONTENT_SOURCES, get_content_activity
from app.services.xp_service import MAX_STUDY_MINUTES_PER_AWARD


@pytest.fixture
async def db_session():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection,
                tables=[User.__table__, XPTransaction.__table__],
            )
        )
    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


class _User:
    def __init__(self):
        self.id = uuid.uuid4()


async def _award(db, user_id, *, source, seconds=None, amount=10, when=None):
    db.add(
        XPTransaction(
            user_id=user_id,
            amount=amount,
            base_amount=amount,
            multiplier=1.0,
            source=source,
            source_id=str(uuid.uuid4()),
            duration_seconds=seconds,
            created_at=when or datetime.now(timezone.utc),
        )
    )
    await db.commit()


def _by_source(response):
    return {row.source: row for row in response.by_source}


async def test_lists_every_content_source_even_at_zero(db_session):
    """An absent row would read as "no data"; a zero row reads as "nothing yet"."""
    response = await get_content_activity(days=7, db=db_session, current_user=_User())

    assert {row.source for row in response.by_source} == set(CONTENT_SOURCES)
    assert response.total_sessions == 0
    assert response.total_minutes == 0


async def test_sums_minutes_and_sessions_per_source(db_session):
    user = _User()
    await _award(db_session, user.id, source="youtube", seconds=600, amount=5)
    await _award(db_session, user.id, source="youtube", seconds=300, amount=5)
    await _award(db_session, user.id, source="podcast", seconds=1200, amount=20)

    response = await get_content_activity(days=7, db=db_session, current_user=user)
    rows = _by_source(response)

    assert (rows["youtube"].sessions, rows["youtube"].minutes) == (2, 15)
    assert (rows["podcast"].sessions, rows["podcast"].minutes) == (1, 20)
    assert response.total_minutes == 35
    assert response.total_xp == 30


async def test_every_source_reports_minutes(db_session):
    """Reading was the last gap; the reader and article screen now report time.

    `tracks_minutes` must follow what the clients actually send — a source left
    False here would have its real minutes hidden by the UI.
    """
    user = _User()
    rows = _by_source(
        await get_content_activity(days=7, db=db_session, current_user=user)
    )

    assert all(row.tracks_minutes for row in rows.values())


async def test_an_award_without_a_duration_is_a_session_but_no_minutes(db_session):
    """A quiz pass carries no duration; it is still activity."""
    user = _User()
    await _award(db_session, user.id, source="news", seconds=None)

    rows = _by_source(
        await get_content_activity(days=7, db=db_session, current_user=user)
    )

    assert rows["news"].sessions == 1
    assert rows["news"].minutes == 0


async def test_reading_time_and_a_quiz_on_one_article_both_count(db_session):
    """Separate awards, separate source_ids — the reader does not replace the quiz."""
    user = _User()
    await _award(db_session, user.id, source="news", seconds=600, amount=5)
    await _award(db_session, user.id, source="news", seconds=None, amount=15)

    rows = _by_source(
        await get_content_activity(days=7, db=db_session, current_user=user)
    )

    assert rows["news"].sessions == 2
    assert rows["news"].minutes == 10
    assert rows["news"].xp_earned == 20


async def test_caps_a_forged_duration_per_activity(db_session):
    user = _User()
    await _award(db_session, user.id, source="youtube", seconds=24 * 60 * 60)

    rows = _by_source(
        await get_content_activity(days=7, db=db_session, current_user=user)
    )
    assert rows["youtube"].minutes == MAX_STUDY_MINUTES_PER_AWARD


async def test_excludes_activity_older_than_the_window(db_session):
    user = _User()
    await _award(
        db_session,
        user.id,
        source="podcast",
        seconds=600,
        when=datetime.now(timezone.utc) - timedelta(days=10),
    )

    week = await get_content_activity(days=7, db=db_session, current_user=user)
    month = await get_content_activity(days=30, db=db_session, current_user=user)

    assert week.total_sessions == 0
    assert month.total_sessions == 1


async def test_excludes_other_learners(db_session):
    user = _User()
    await _award(db_session, uuid.uuid4(), source="youtube", seconds=600)

    response = await get_content_activity(days=7, db=db_session, current_user=user)
    assert response.total_sessions == 0


async def test_ignores_non_content_sources(db_session):
    """Lesson and game XP belong to the study surfaces, not this view."""
    user = _User()
    await _award(db_session, user.id, source="lesson", seconds=600, amount=50)
    await _award(db_session, user.id, source="game", seconds=300, amount=40)

    response = await get_content_activity(days=7, db=db_session, current_user=user)
    assert response.total_sessions == 0
    assert response.total_xp == 0
