"""Feature Processor: content_interaction events fanned out into the
recommender's insights — topic_affinity, vocabulary_weakness,
difficulty_preference."""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Course
from app.models.product_event import ProductEvent
from app.models.user import User
from app.models.vocabulary import DifficultyLevel, PartOfSpeech, VocabularyItem
from app.services.feature_processor import (
    EVENT_RETENTION_DAYS,
    EVENT_WINDOW_DAYS,
    build_topic_affinity,
    compute_insights,
    prune_product_events,
)

pytestmark = pytest.mark.asyncio


async def _event(
    db: AsyncSession,
    user: User,
    *,
    topic: str | None = None,
    action: str = "open",
    item_type: str = "course",
    item_id: str = "x",
    days_ago: float = 0.0,
    name: str = "content_interaction",
) -> None:
    created = datetime.now(UTC) - timedelta(days=days_ago)
    properties = {"item_type": item_type, "item_id": item_id, "action": action}
    if topic is not None:
        properties["topic"] = topic
    db.add(
        ProductEvent(
            event_id=uuid.uuid4(),
            user_id=user.id,
            event_name=name,
            source="test",
            properties=properties,
            client_timestamp=created,
            created_at=created,
        )
    )
    await db.flush()


# -- topic_affinity ----------------------------------------------------------


async def test_most_picked_topic_wins(db_session: AsyncSession, test_user: User):
    for _ in range(3):
        await _event(db_session, test_user, topic="travel", action="complete")
    await _event(db_session, test_user, topic="business", action="open")

    affinity = await build_topic_affinity(db_session, test_user.id)

    assert affinity["travel"] == 1.0  # normalized to the peak
    assert affinity["business"] < affinity["travel"]


async def test_recent_interest_outweighs_old(db_session: AsyncSession, test_user: User):
    # Same action, same count — only age differs.
    for _ in range(2):
        await _event(db_session, test_user, topic="music", action="complete", days_ago=45)
        await _event(db_session, test_user, topic="cooking", action="complete", days_ago=1)

    affinity = await build_topic_affinity(db_session, test_user.id)

    assert affinity["cooking"] > affinity["music"]


async def test_skips_do_not_earn_affinity(db_session: AsyncSession, test_user: User):
    await _event(db_session, test_user, topic="sports", action="skip")
    await _event(db_session, test_user, topic="travel", action="complete")

    affinity = await build_topic_affinity(db_session, test_user.id)

    # A negative signal must drop out entirely, never rank as mild interest.
    assert "sports" not in affinity
    assert affinity["travel"] == 1.0


async def test_ignores_other_event_names(db_session: AsyncSession, test_user: User):
    await _event(db_session, test_user, topic="travel", action="open", name="srs_reminder_shown")

    assert await build_topic_affinity(db_session, test_user.id) == {}


# -- vocabulary_weakness ------------------------------------------------------


async def test_wrong_reviews_build_weakness_by_topic(db_session: AsyncSession, test_user: User):
    for _ in range(3):
        await _event(
            db_session, test_user, topic="grammar", action="review_incorrect", item_type="vocab"
        )
    await _event(
        db_session, test_user, topic="food", action="review_correct", item_type="vocab"
    )

    insights = await compute_insights(db_session, test_user.id, level="A2")

    assert insights["vocabulary_weakness"]["grammar"] == 1.0
    assert "food" not in insights["vocabulary_weakness"]


async def test_vocabulary_weakness_ignores_non_vocab_and_non_review(
    db_session: AsyncSession, test_user: User
):
    # A course completion and a plain vocab "open" must not count as a
    # right/wrong review outcome.
    await _event(db_session, test_user, topic="grammar", action="complete", item_type="course")
    await _event(db_session, test_user, topic="grammar", action="open", item_type="vocab")

    insights = await compute_insights(db_session, test_user.id, level="A2")

    assert insights["vocabulary_weakness"] == {}


# -- difficulty_preference ----------------------------------------------------


async def test_engaging_with_harder_content_signals_positive_preference(
    db_session: AsyncSession, test_user: User
):
    course = Course(
        id=uuid.uuid4(),
        title="Advanced Business",
        description="",
        language="en",
        level="C1",
        is_published=True,
    )
    db_session.add(course)
    await db_session.flush()

    await _event(
        db_session, test_user, action="complete", item_type="course", item_id=str(course.id)
    )

    insights = await compute_insights(db_session, test_user.id, level="A2")

    assert insights["difficulty_preference"] > 0


async def test_skipping_harder_content_signals_negative_preference(
    db_session: AsyncSession, test_user: User
):
    course = Course(
        id=uuid.uuid4(),
        title="Advanced Business",
        description="",
        language="en",
        level="C1",
        is_published=True,
    )
    db_session.add(course)
    await db_session.flush()

    await _event(
        db_session, test_user, action="skip", item_type="course", item_id=str(course.id)
    )

    insights = await compute_insights(db_session, test_user.id, level="A2")

    assert insights["difficulty_preference"] < 0


async def test_no_level_bearing_events_is_neutral(db_session: AsyncSession, test_user: User):
    # item_id "x" from _event()'s default resolves to nothing in the DB.
    await _event(db_session, test_user, action="open", item_type="course")

    insights = await compute_insights(db_session, test_user.id, level="A2")

    assert insights["difficulty_preference"] == 0.0


async def test_difficulty_preference_reads_vocab_levels_too(
    db_session: AsyncSession, test_user: User
):
    word = VocabularyItem(
        id=uuid.uuid4(),
        word="ubiquitous",
        definition="present everywhere",
        part_of_speech=PartOfSpeech.ADJECTIVE,
        difficulty_level=DifficultyLevel.C1,
    )
    db_session.add(word)
    await db_session.flush()

    await _event(
        db_session,
        test_user,
        action="review_correct",
        item_type="vocab",
        item_id=str(word.id),
    )

    insights = await compute_insights(db_session, test_user.id, level="A2")

    assert insights["difficulty_preference"] > 0


# -- compute_insights fans one event type into all three ---------------------


async def test_compute_insights_returns_all_three_keys(
    db_session: AsyncSession, test_user: User
):
    insights = await compute_insights(db_session, test_user.id, level="A1")

    assert set(insights) == {"topic_affinity", "vocabulary_weakness", "difficulty_preference"}


# -- retention ----------------------------------------------------------------


async def test_prune_deletes_only_events_past_retention(
    db_session: AsyncSession, test_user: User
):
    from sqlalchemy import select as sa_select

    await _event(db_session, test_user, topic="fresh", days_ago=1)
    await _event(db_session, test_user, topic="recent", days_ago=EVENT_WINDOW_DAYS - 1)
    await _event(db_session, test_user, topic="ancient", days_ago=EVENT_RETENTION_DAYS + 10)

    result = await prune_product_events(db_session)

    assert result.deleted == 1
    remaining = (await db_session.scalars(sa_select(ProductEvent))).all()
    topics = {row.properties.get("topic") for row in remaining}
    assert topics == {"fresh", "recent"}


async def test_prune_never_touches_what_the_processors_still_read(
    db_session: AsyncSession, test_user: User
):
    """Retention must stay wider than the read window, or pruning would
    silently amputate the history topic_affinity is computed from."""
    assert EVENT_RETENTION_DAYS > EVENT_WINDOW_DAYS

    await _event(db_session, test_user, topic="travel", days_ago=EVENT_WINDOW_DAYS - 1)
    await prune_product_events(db_session)

    assert await build_topic_affinity(db_session, test_user.id) == {"travel": 1.0}


async def test_prune_is_idempotent_on_a_clean_table(
    db_session: AsyncSession, test_user: User
):
    await _event(db_session, test_user, topic="fresh", days_ago=1)

    assert (await prune_product_events(db_session)).deleted == 0
    assert (await prune_product_events(db_session)).deleted == 0
