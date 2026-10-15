import uuid

import pytest
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.content import GrammarItem
from app.models.games import GameWord
from app.models.user_grammar_item import UserGrammarItem
from app.models.vocabulary import UserVocabulary, VocabularyItem
from app.services.game_fsrs_service import (
    record_game_grammar_lapse,
    record_game_vocab_lapse,
)


@pytest.fixture
async def game_fsrs_db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [
        GrammarItem.__table__,
        GameWord.__table__,
        VocabularyItem.__table__,
        UserVocabulary.__table__,
        UserGrammarItem.__table__,
    ]
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection,
                tables=tables,
            )
        )
    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


def _game_word(word: str) -> GameWord:
    return GameWord(
        word=word,
        definition=f"Definition of {word}",
        cefr_level="A1",
        category="test",
        letter_count=len(word),
    )


# Lapses that actually reach the scheduler now go through the unified
# learner-state engine, which is PostgreSQL-only by design (see
# ingest_observations). Those paths are covered against a real database in
# tests/integration/test_game_lapse_learner_state.py; what stays here is the
# resolution and no-op behaviour, which needs no engine.


@pytest.mark.asyncio
async def test_vocab_lapse_noops_when_game_word_does_not_exist(
    game_fsrs_db: AsyncSession,
) -> None:
    await record_game_vocab_lapse(
        game_fsrs_db,
        user_id=uuid.uuid4(),
        game_word_id=str(uuid.uuid4()),
    )

    assert (await game_fsrs_db.scalars(select(UserVocabulary))).all() == []


@pytest.mark.asyncio
async def test_vocab_lapse_noops_for_invalid_game_word_id(
    game_fsrs_db: AsyncSession,
) -> None:
    await record_game_vocab_lapse(
        game_fsrs_db,
        user_id=uuid.uuid4(),
        game_word_id="hangman-fallback-id",
    )

    assert (await game_fsrs_db.scalars(select(UserVocabulary))).all() == []


@pytest.mark.asyncio
async def test_vocab_lapse_noops_without_vocabulary_match(
    game_fsrs_db: AsyncSession,
) -> None:
    game_word = _game_word("not-in-vocabulary")
    game_fsrs_db.add(game_word)
    await game_fsrs_db.commit()

    await record_game_vocab_lapse(
        game_fsrs_db,
        user_id=uuid.uuid4(),
        game_word_id=str(game_word.id),
    )

    assert (await game_fsrs_db.scalars(select(UserVocabulary))).all() == []


@pytest.mark.asyncio
async def test_vocab_lapse_swallows_database_failure(
    game_fsrs_db: AsyncSession,
) -> None:
    await game_fsrs_db.execute(text("DROP TABLE game_words"))

    await record_game_vocab_lapse(
        game_fsrs_db,
        user_id=uuid.uuid4(),
        game_word_id=str(uuid.uuid4()),
    )

    assert (await game_fsrs_db.scalars(select(UserVocabulary))).all() == []


@pytest.mark.asyncio
async def test_grammar_lapse_noops_without_topic_match(
    game_fsrs_db: AsyncSession,
) -> None:
    await record_game_grammar_lapse(
        game_fsrs_db,
        user_id=uuid.uuid4(),
        topic="not_seeded",
    )

    assert (await game_fsrs_db.scalars(select(UserGrammarItem))).all() == []
