import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.content import GrammarItem
from app.models.games import GameWord
from app.models.user_grammar_item import UserGrammarItem
from app.models.vocabulary import UserVocabulary, VocabularyItem, VocabularyStatus
from app.services import game_fsrs_service as fsrs_service
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


@pytest.mark.asyncio
async def test_vocab_lapse_resolves_word_and_creates_or_updates_schedule(
    game_fsrs_db: AsyncSession,
) -> None:
    user_id = uuid.uuid4()
    game_word = _game_word("HELLO")
    vocabulary = VocabularyItem(
        word="hello",
        definition="A greeting.",
        part_of_speech="noun",
        difficulty_level="A1",
    )
    game_fsrs_db.add_all([game_word, vocabulary])
    await game_fsrs_db.commit()

    with patch.object(game_fsrs_db, "commit", new_callable=AsyncMock) as commit_mock:
        await record_game_vocab_lapse(
            game_fsrs_db,
            user_id=user_id,
            game_word_id=str(game_word.id),
        )
        await record_game_vocab_lapse(
            game_fsrs_db,
            user_id=user_id,
            game_word_id=str(game_word.id),
        )

    rows = (await game_fsrs_db.scalars(select(UserVocabulary))).all()
    assert len(rows) == 1
    assert rows[0].user_id == user_id
    assert rows[0].vocabulary_id == vocabulary.id
    assert rows[0].total_reviews == 2
    assert rows[0].correct_reviews == 0
    assert rows[0].fsrs_reps == 2
    assert rows[0].fsrs_lapses == 2
    commit_mock.assert_not_awaited()


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
async def test_vocab_lapse_retries_once_on_concurrent_insert_race(
    game_fsrs_db: AsyncSession,
) -> None:
    """Two concurrent wrong answers on the same word can both see 'no row yet' and
    both attempt to insert; the second must recover by retrying, not silently no-op."""
    user_id = uuid.uuid4()
    game_word = _game_word("HELLO")
    vocabulary = VocabularyItem(
        word="hello",
        definition="A greeting.",
        part_of_speech="noun",
        difficulty_level="A1",
    )
    game_fsrs_db.add_all([game_word, vocabulary])
    await game_fsrs_db.commit()

    # Simulate a concurrent request that already created the row.
    now = datetime.now(timezone.utc)
    existing = UserVocabulary(
        user_id=user_id,
        vocabulary_id=vocabulary.id,
        status=VocabularyStatus.LEARNING,
        ease_factor=2.5,
        interval=1,
        repetitions=0,
        next_review_date=now,
        fsrs_stability=0.0,
        fsrs_difficulty=0.0,
        fsrs_elapsed_days=0,
        fsrs_scheduled_days=0,
        fsrs_reps=0,
        fsrs_lapses=0,
        fsrs_state=0,
        total_reviews=0,
        correct_reviews=0,
        streak=0,
        longest_streak=0,
        total_xp_earned=0,
        added_at=now,
    )
    game_fsrs_db.add(existing)
    await game_fsrs_db.commit()

    real_get_or_create = fsrs_service._get_or_create_vocabulary_row
    calls = {"n": 0}

    async def flaky_get_or_create(db, **kwargs):
        calls["n"] += 1
        if calls["n"] == 1:
            raise IntegrityError("insert", {}, Exception("unique violation"))
        return await real_get_or_create(db, **kwargs)

    with patch.object(
        fsrs_service,
        "_get_or_create_vocabulary_row",
        side_effect=flaky_get_or_create,
    ):
        await record_game_vocab_lapse(
            game_fsrs_db,
            user_id=user_id,
            game_word_id=str(game_word.id),
        )

    rows = (await game_fsrs_db.scalars(select(UserVocabulary))).all()
    assert len(rows) == 1  # retry updated the existing row, no duplicate
    assert rows[0].total_reviews == 1
    assert calls["n"] == 2


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
async def test_grammar_lapse_resolves_topic_and_updates_schedule(
    game_fsrs_db: AsyncSession,
) -> None:
    user_id = uuid.uuid4()
    grammar = GrammarItem(
        title="Present simple",
        level="A1",
        topic="present_simple",
        content="Present simple rules.",
    )
    game_fsrs_db.add(grammar)
    await game_fsrs_db.commit()

    with patch.object(game_fsrs_db, "commit", new_callable=AsyncMock) as commit_mock:
        await record_game_grammar_lapse(
            game_fsrs_db,
            user_id=user_id,
            topic="PRESENT_SIMPLE",
        )

    row = (await game_fsrs_db.scalars(select(UserGrammarItem))).one()
    assert row.user_id == user_id
    assert row.grammar_item_id == grammar.id
    assert row.total_reviews == 1
    assert row.correct_reviews == 0
    assert row.fsrs_reps == 1
    assert row.fsrs_lapses == 1
    commit_mock.assert_not_awaited()


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
