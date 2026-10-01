"""Daily content quests, measured off the XPTransaction rows already written.

The library, podcast, video and news surfaces awarded XP but counted toward
nothing, so a day spent reading looked idle beside one finished lesson.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.games import XPTransaction
from app.models.user import User
from app.routes.challenges import (
    CONTENT_QUEST_SOURCES,
    DAILY_CHALLENGE_TEMPLATES,
    calculate_challenge_progress,
)
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


@pytest.fixture
def user_id():
    return uuid.uuid4()


def _quest(quest_id: str, target: int = 10) -> dict:
    template = next(t for t in DAILY_CHALLENGE_TEMPLATES if t["id"] == quest_id)
    return {**template, "target": target}


async def _award(
    db,
    user_id,
    *,
    source,
    seconds=None,
    detail=None,
    when=None,
    amount=10,
):
    db.add(
        XPTransaction(
            user_id=user_id,
            amount=amount,
            base_amount=amount,
            multiplier=1.0,
            source=source,
            source_id=str(uuid.uuid4()),
            source_detail=detail,
            duration_seconds=seconds,
            created_at=when or datetime.now(timezone.utc),
        )
    )
    await db.commit()


def _today():
    return datetime.now(timezone.utc).date()


class TestMinuteQuests:
    async def test_counts_reported_minutes(self, db_session, user_id):
        await _award(db_session, user_id, source="youtube", seconds=600)
        await _award(db_session, user_id, source="youtube", seconds=300)

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("watch_youtube", 15), _today()
        )
        assert progress == 15

    async def test_rounds_down_a_partial_minute(self, db_session, user_id):
        await _award(db_session, user_id, source="youtube", seconds=119)

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("watch_youtube", 5), _today()
        )
        assert progress == 1

    async def test_a_forged_duration_cannot_finish_the_quest_alone(
        self, db_session, user_id
    ):
        """duration_seconds is a client claim; one award is capped like study time."""
        await _award(db_session, user_id, source="youtube", seconds=24 * 60 * 60)

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("watch_youtube", 30), _today()
        )
        assert progress == MAX_STUDY_MINUTES_PER_AWARD

    async def test_ignores_awards_with_no_duration(self, db_session, user_id):
        await _award(db_session, user_id, source="podcast", seconds=None)

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("listen_podcast", 5), _today()
        )
        assert progress == 0

    async def test_does_not_count_another_source(self, db_session, user_id):
        await _award(db_session, user_id, source="podcast", seconds=1200)

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("watch_youtube", 15), _today()
        )
        assert progress == 0

    async def test_does_not_count_another_user(self, db_session, user_id):
        await _award(db_session, uuid.uuid4(), source="youtube", seconds=1200)

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("watch_youtube", 15), _today()
        )
        assert progress == 0

    async def test_does_not_count_yesterday(self, db_session, user_id):
        await _award(
            db_session,
            user_id,
            source="youtube",
            seconds=1200,
            when=datetime.now(timezone.utc) - timedelta(days=1, hours=2),
        )

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("watch_youtube", 15), _today()
        )
        assert progress == 0


class TestReadingQuest:
    """`read_minutes` spans both reading surfaces: an article and a chapter are
    the same twenty minutes to a learner."""

    async def test_sums_article_and_book_reading(self, db_session, user_id):
        await _award(
            db_session, user_id, source="news", seconds=600, detail="reading_time"
        )
        await _award(
            db_session, user_id, source="book", seconds=300, detail="reading_time"
        )

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("read_minutes", 15), _today()
        )
        assert progress == 15

    async def test_a_quiz_pass_is_not_reading_time(self, db_session, user_id):
        """Three kinds of book award share one source; only reading time counts."""
        await _award(
            db_session, user_id, source="book", seconds=None, detail="chapter_quiz"
        )
        await _award(
            db_session, user_id, source="book", seconds=600, detail="reading_50pct"
        )

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("read_minutes", 5), _today()
        )
        assert progress == 0

    async def test_reading_time_does_not_tick_the_quiz_quest(self, db_session, user_id):
        await _award(
            db_session, user_id, source="book", seconds=900, detail="reading_time"
        )

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("read_book", 1), _today()
        )
        assert progress == 0

    async def test_watching_is_not_reading(self, db_session, user_id):
        await _award(
            db_session, user_id, source="youtube", seconds=900, detail="video_watch"
        )

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("read_minutes", 5), _today()
        )
        assert progress == 0


class TestEventQuests:
    async def test_counts_news_quizzes(self, db_session, user_id):
        await _award(db_session, user_id, source="news", detail="news_quiz")
        await _award(db_session, user_id, source="news", detail="news_quiz")

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("read_news", 2), _today()
        )
        assert progress == 2

    async def test_a_reading_milestone_is_not_a_chapter_quiz(self, db_session, user_id):
        """A book awards XP for both; "finish a chapter quiz" must only see one."""
        await _award(db_session, user_id, source="book", detail="reading_50pct")
        await _award(db_session, user_id, source="book", detail="reading_complete")
        await _award(db_session, user_id, source="book", detail="chapter_quiz")

        progress = await calculate_challenge_progress(
            db_session, user_id, _quest("read_book", 2), _today()
        )
        assert progress == 1


class TestQuestSetComposition:
    def test_exactly_one_content_quest_per_day(self):
        """Every challenge must be completable for the all-done bonus to be fair.

        Drawing from one pool let a day come up mostly content, which would cost
        a lessons-only learner the bonus through no fault of their own.
        """
        from datetime import date

        from app.routes.challenges import get_challenges_for_user

        for _ in range(200):
            quests = get_challenges_for_user(uuid.uuid4(), date(2026, 10, 1))
            content = [q for q in quests if q["category"] == "content"]
            assert len(content) == 1
            assert 4 <= len(quests) <= 5
            assert len({q["id"] for q in quests}) == len(quests)

    def test_the_same_user_and_day_always_gets_the_same_set(self):
        from datetime import date

        from app.routes.challenges import get_challenges_for_user

        uid = uuid.uuid4()
        first = get_challenges_for_user(uid, date(2026, 10, 1))
        second = get_challenges_for_user(uid, date(2026, 10, 1))
        assert [q["id"] for q in first] == [q["id"] for q in second]

    def test_content_quest_ids_match_their_progress_spec(self):
        content_ids = {
            t["id"] for t in DAILY_CHALLENGE_TEMPLATES if t["category"] == "content"
        }
        assert content_ids == set(CONTENT_QUEST_SOURCES)
