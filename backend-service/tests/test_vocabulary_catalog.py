"""Tests for vocabulary_catalog: upsert and normalization."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.course import Course, Lesson, Unit
from app.models.vocabulary import VocabularyItem
from app.services.vocabulary_catalog import normalize_word, upsert_vocabulary_batch


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
async def vocab_db():
    """In-memory SQLite session covering vocabulary and course tables."""
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [
        Course.__table__,
        Unit.__table__,
        Lesson.__table__,
        VocabularyItem.__table__,
    ]
    async with engine.begin() as conn:
        await conn.run_sync(
            lambda sync_conn: Base.metadata.create_all(sync_conn, tables=tables)
        )
    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


def _item(
    word: str,
    pos: str = "noun",
    definition: str = "A valid definition for testing purposes.",
    difficulty_level: str = "A1",
    topic: str = "general",
) -> dict:
    return {
        "word": word,
        "part_of_speech": pos,
        "definition": definition,
        "difficulty_level": difficulty_level,
        "topic": topic,
        "source_name": "generated",
        "translation": None,
        "pronunciation": None,
        "audio_url": None,
    }


# ---------------------------------------------------------------------------
# normalize_word
# ---------------------------------------------------------------------------


def test_normalize_lowercases_and_nfkc() -> None:
    assert normalize_word("HELLO") == "hello"


def test_normalize_collapses_whitespace() -> None:
    assert normalize_word("  running  fast  ") == "running fast"


def test_normalize_curly_apostrophe_replaced() -> None:
    result = normalize_word("it’s")
    assert "'" in result or result == "it's"


def test_normalize_em_dash_becomes_hyphen() -> None:
    assert normalize_word("well—being") == "well-being"


def test_normalize_en_dash_becomes_hyphen() -> None:
    assert normalize_word("mother–in–law") == "mother-in-law"


# ---------------------------------------------------------------------------
# same word / different POS = different row
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_same_word_different_pos_creates_two_rows(vocab_db: AsyncSession) -> None:
    items = [
        _item("run", pos="verb"),
        _item("run", pos="noun"),
    ]
    identity = await upsert_vocabulary_batch(vocab_db, items)
    assert len(identity) == 2
    assert identity[("run", "verb")] != identity[("run", "noun")]
    rows = (await vocab_db.scalars(select(VocabularyItem))).all()
    assert len(rows) == 2


# ---------------------------------------------------------------------------
# Duplicate words across lessons → single row
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_duplicate_words_across_lessons_produce_single_row(
    vocab_db: AsyncSession,
) -> None:
    items = [
        _item("book", pos="noun"),
        _item("BOOK", pos="noun"),  # same after normalization
        _item("book", pos="noun"),
    ]
    identity = await upsert_vocabulary_batch(vocab_db, items)
    rows = (await vocab_db.scalars(select(VocabularyItem))).all()
    assert len(rows) == 1
    assert ("book", "noun") in identity


# ---------------------------------------------------------------------------
# Placeholder definition replacement
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_blank_definition_in_db_is_replaced(vocab_db: AsyncSession) -> None:
    existing = VocabularyItem(
        word="run",
        definition="",  # blank — curated field not yet set
        part_of_speech="verb",
        difficulty_level="A1",
    )
    vocab_db.add(existing)
    await vocab_db.flush()

    items = [_item("run", pos="verb", definition="To move quickly on foot.")]
    await upsert_vocabulary_batch(vocab_db, items)
    await vocab_db.refresh(existing)
    assert existing.definition == "To move quickly on foot."


# ---------------------------------------------------------------------------
# Curated field preservation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_non_blank_definition_not_overwritten(vocab_db: AsyncSession) -> None:
    existing = VocabularyItem(
        word="book",
        definition="Curated definition that must not be overwritten.",
        part_of_speech="noun",
        difficulty_level="A1",
    )
    vocab_db.add(existing)
    await vocab_db.flush()

    items = [_item("book", pos="noun", definition="A different generated definition.")]
    await upsert_vocabulary_batch(vocab_db, items)
    await vocab_db.refresh(existing)
    assert existing.definition == "Curated definition that must not be overwritten."


@pytest.mark.asyncio
async def test_existing_translation_not_overwritten(vocab_db: AsyncSession) -> None:
    existing = VocabularyItem(
        word="hello",
        definition="A greeting expression.",
        translation={"vi": "xin chào"},
        part_of_speech="interjection",
        difficulty_level="A1",
    )
    vocab_db.add(existing)
    await vocab_db.flush()

    item = _item("hello", pos="interjection")
    item["translation"] = {"vi": "chào hỏi"}  # different translation
    await upsert_vocabulary_batch(vocab_db, [item])
    await vocab_db.refresh(existing)
    assert existing.translation == {"vi": "xin chào"}


# ---------------------------------------------------------------------------
# Repeat apply idempotency
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_repeat_apply_returns_same_ids(vocab_db: AsyncSession) -> None:
    items = [_item("water", pos="noun"), _item("fire", pos="noun")]
    first = await upsert_vocabulary_batch(vocab_db, items)
    second = await upsert_vocabulary_batch(vocab_db, items)
    assert first == second


@pytest.mark.asyncio
async def test_repeat_apply_does_not_create_duplicate_rows(
    vocab_db: AsyncSession,
) -> None:
    items = [_item("earth", pos="noun")]
    await upsert_vocabulary_batch(vocab_db, items)
    await upsert_vocabulary_batch(vocab_db, items)
    rows = (
        await vocab_db.scalars(
            select(VocabularyItem).where(VocabularyItem.word == "earth")
        )
    ).all()
    assert len(rows) == 1


# ---------------------------------------------------------------------------
# Empty batch
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_empty_batch_returns_empty_map(vocab_db: AsyncSession) -> None:
    result = await upsert_vocabulary_batch(vocab_db, [])
    assert result == {}


# ---------------------------------------------------------------------------
# All normalized forms map to the same existing row
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_unicode_variant_maps_to_same_row(vocab_db: AsyncSession) -> None:
    items = [_item("café", pos="noun")]  # café (NFC)
    first = await upsert_vocabulary_batch(vocab_db, items)

    items2 = [_item("café", pos="noun")]  # cafe + combining accent (NFD)
    second = await upsert_vocabulary_batch(vocab_db, items2)

    # After NFKC normalization both should collapse to the same row
    rows = (await vocab_db.scalars(select(VocabularyItem))).all()
    assert len(rows) == 1
