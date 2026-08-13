"""Integration test: vocabulary review is unified with learner_concept_state."""

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.vocabulary import vocabulary_crud
from app.models.learner_state import LearnerConceptState
from app.models.vocabulary import UserVocabulary, VocabularyItem, VocabularyStatus
from app.services.learner_state import ALGORITHM_VERSION


async def _seed_user_vocab(db_session: AsyncSession, user_id) -> UserVocabulary:
    vocab_item = VocabularyItem(
        word="Hotel Room",
        definition="a place to stay",
        part_of_speech="noun",
        difficulty_level="A1",
    )
    db_session.add(vocab_item)
    await db_session.flush()

    user_vocab = UserVocabulary(
        user_id=user_id,
        vocabulary_id=vocab_item.id,
        status=VocabularyStatus.LEARNING,
        next_review_date=datetime.now(UTC) + timedelta(days=1),
    )
    db_session.add(user_vocab)
    await db_session.commit()
    await db_session.refresh(user_vocab)
    return user_vocab


@pytest.mark.asyncio
async def test_submit_review_writes_through_learner_concept_state(
    db_session: AsyncSession, test_user
):
    user_vocab = await _seed_user_vocab(db_session, test_user.id)

    updated = await vocabulary_crud.submit_review(
        db_session, user_vocab.id, quality=5, time_spent_ms=1200
    )

    concept_state = await db_session.scalar(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == test_user.id,
            LearnerConceptState.concept_id == "vocab:hotel_room",
        )
    )
    assert concept_state is not None
    assert concept_state.attempt_count == 1
    assert concept_state.correct_count == 1
    assert concept_state.algorithm_version == ALGORITHM_VERSION

    # UserVocabulary.next_review_date is a synced read-cache of the same value
    assert updated.next_review_date == concept_state.next_review_at
    assert updated.total_reviews == 1
    assert updated.correct_reviews == 1
    assert updated.streak == 1


@pytest.mark.asyncio
async def test_submit_review_reuses_same_concept_across_reviews(
    db_session: AsyncSession, test_user
):
    user_vocab = await _seed_user_vocab(db_session, test_user.id)

    await vocabulary_crud.submit_review(db_session, user_vocab.id, quality=2)
    await vocabulary_crud.submit_review(db_session, user_vocab.id, quality=5)

    states = (
        await db_session.scalars(
            select(LearnerConceptState).where(
                LearnerConceptState.user_id == test_user.id,
                LearnerConceptState.concept_id == "vocab:hotel_room",
            )
        )
    ).all()
    assert len(states) == 1
    assert states[0].attempt_count == 2
    assert states[0].correct_count == 1
    assert states[0].error_count == 1


@pytest.mark.asyncio
async def test_submit_review_incorrect_answer_resets_streak_and_stays_learning(
    db_session: AsyncSession, test_user
):
    user_vocab = await _seed_user_vocab(db_session, test_user.id)

    updated = await vocabulary_crud.submit_review(db_session, user_vocab.id, quality=1)

    assert updated.streak == 0
    assert updated.status == VocabularyStatus.LEARNING
