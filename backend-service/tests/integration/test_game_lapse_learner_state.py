"""Integration test: game lapses schedule through the same engine as reviews.

Game answers used to run their own SM-2 + FSRS-lite pass and write
next_review_date directly, so a word answered in a game and reviewed in the
vocabulary screen was scheduled by two different algorithms — whichever ran
last won. These tests pin the single-owner property against a real database.
"""

import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import GrammarItem
from app.models.games import GameWord
from app.models.learner_state import LearnerConceptState
from app.models.user_grammar_item import UserGrammarItem
from app.models.vocabulary import UserVocabulary, VocabularyItem
from app.services.game_fsrs_service import (
    record_game_grammar_lapse,
    record_game_vocab_lapse,
)
from app.services.learner_state import ALGORITHM_VERSION


async def _seed_game_word(db_session: AsyncSession, word: str) -> tuple[GameWord, VocabularyItem]:
    game_word = GameWord(
        word=word.upper(),
        definition=f"Definition of {word}",
        cefr_level="A1",
        category="test",
        letter_count=len(word),
    )
    vocabulary = VocabularyItem(
        word=word,
        definition="A greeting.",
        part_of_speech="noun",
        difficulty_level="A1",
    )
    db_session.add_all([game_word, vocabulary])
    await db_session.commit()
    return game_word, vocabulary


@pytest.mark.asyncio
async def test_vocab_lapse_schedules_through_learner_concept_state(
    db_session: AsyncSession, test_user
):
    game_word, vocabulary = await _seed_game_word(db_session, "hello")

    await record_game_vocab_lapse(
        db_session, user_id=test_user.id, game_word_id=str(game_word.id)
    )

    concept_state = await db_session.scalar(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == test_user.id,
            LearnerConceptState.concept_id == "vocab:hello",
        )
    )
    assert concept_state is not None
    assert concept_state.error_count == 1
    assert concept_state.correct_count == 0
    assert concept_state.algorithm_version == ALGORITHM_VERSION

    user_vocab = await db_session.scalar(
        select(UserVocabulary).where(
            UserVocabulary.user_id == test_user.id,
            UserVocabulary.vocabulary_id == vocabulary.id,
        )
    )
    assert user_vocab is not None
    assert user_vocab.total_reviews == 1
    # The row is a read-cache of the engine's schedule, not a second opinion.
    assert user_vocab.next_review_date == concept_state.next_review_at


@pytest.mark.asyncio
async def test_repeated_vocab_lapses_accumulate_on_one_concept(
    db_session: AsyncSession, test_user
):
    game_word, _ = await _seed_game_word(db_session, "hello")

    await record_game_vocab_lapse(
        db_session, user_id=test_user.id, game_word_id=str(game_word.id)
    )
    await record_game_vocab_lapse(
        db_session, user_id=test_user.id, game_word_id=str(game_word.id)
    )

    states = (
        await db_session.scalars(
            select(LearnerConceptState).where(
                LearnerConceptState.user_id == test_user.id,
                LearnerConceptState.concept_id == "vocab:hello",
            )
        )
    ).all()
    assert len(states) == 1
    assert states[0].attempt_count == 2
    assert states[0].error_count == 2


@pytest.mark.asyncio
async def test_grammar_lapse_schedules_through_learner_concept_state(
    db_session: AsyncSession, test_user
):
    grammar = GrammarItem(
        title="Present simple",
        level="A1",
        topic="present_simple",
        content="Present simple rules.",
    )
    db_session.add(grammar)
    await db_session.commit()

    await record_game_grammar_lapse(
        db_session, user_id=test_user.id, topic="PRESENT_SIMPLE"
    )

    concept_state = await db_session.scalar(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == test_user.id,
            LearnerConceptState.concept_id == "grammar:present_simple",
        )
    )
    assert concept_state is not None
    assert concept_state.error_count == 1

    user_grammar = await db_session.scalar(
        select(UserGrammarItem).where(
            UserGrammarItem.user_id == test_user.id,
            UserGrammarItem.grammar_item_id == grammar.id,
        )
    )
    assert user_grammar is not None
    assert user_grammar.total_reviews == 1
    assert user_grammar.next_review_date == concept_state.next_review_at


@pytest.mark.asyncio
async def test_unresolvable_game_word_touches_no_learner_state(
    db_session: AsyncSession, test_user
):
    await record_game_vocab_lapse(
        db_session, user_id=test_user.id, game_word_id=str(uuid.uuid4())
    )

    states = (
        await db_session.scalars(
            select(LearnerConceptState).where(
                LearnerConceptState.user_id == test_user.id
            )
        )
    ).all()
    assert states == []
