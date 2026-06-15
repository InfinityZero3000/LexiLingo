"""Concurrency-safe vocabulary upsert for the content-agent ETL pipeline.

Design:
* Never loads the full vocabulary table — only queries keys present in the
  current artifact.
* Uses SELECT … FOR UPDATE to lock matching rows before any write, preventing
  lost-update races between concurrent apply jobs.
* INSERT … ON CONFLICT DO NOTHING handles duplicate inserts from concurrent
  transactions; a follow-up SELECT re-fetches rows inserted by others.
* Curated fields (non-blank definition, non-null translation, pronunciation,
  audio_url) are never overwritten by content-agent data.
"""

from __future__ import annotations

import re
import unicodedata
import uuid
from typing import Any

from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.vocabulary import VocabularyItem


def normalize_word(word: str) -> str:
    """Canonical form for matching: NFKC → casefold → strip apostrophes/hyphens → collapse whitespace."""
    normalized = unicodedata.normalize("NFKC", word)
    normalized = (
        normalized.casefold()
        .replace("’", "'")  # right single quotation mark → apostrophe
        .replace("‘", "'")  # left single quotation mark → apostrophe
        .replace("–", "-")       # en dash → hyphen
        .replace("—", "-")       # em dash → hyphen
        .replace("‑", "-")       # non-breaking hyphen → hyphen
    )
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


async def upsert_vocabulary_batch(
    session: AsyncSession,
    vocab_items: list[dict[str, Any]],
) -> dict[tuple[str, str], uuid.UUID]:
    """Batch-upsert vocabulary items and return a stable ``(word_key, pos) → id`` map.

    Parameters
    ----------
    session:
        Active async SQLAlchemy session (must be inside an open transaction).
    vocab_items:
        Each dict must have ``word`` (raw), ``part_of_speech``, ``definition``,
        and optionally ``translation``, ``pronunciation``, ``audio_url``,
        ``difficulty_level``, ``topic``, ``source_name``.

    Returns
    -------
    dict mapping ``(normalized_word, part_of_speech)`` → ``vocabulary_item.id``.
    """
    if not vocab_items:
        return {}

    # --- Step 1: Build canonical key set (de-duplicate within batch) ----------
    seen: dict[tuple[str, str], dict[str, Any]] = {}
    for item in vocab_items:
        key = (normalize_word(item["word"]), item["part_of_speech"])
        if key not in seen:
            seen[key] = item

    keys = list(seen.keys())
    norm_words = [k[0] for k in keys]
    pos_values = [k[1] for k in keys]

    # --- Step 2: Lock existing rows (FOR UPDATE) so concurrent writers wait ---
    # SQLite doesn't support FOR UPDATE; skip locking for test environments.
    dialect = session.bind.dialect.name if session.bind else "postgresql"  # type: ignore[union-attr]

    if dialect == "postgresql":
        lock_q = (
            select(VocabularyItem)
            .where(
                VocabularyItem.word.in_(norm_words),
                VocabularyItem.part_of_speech.in_(pos_values),
            )
            .with_for_update()
            .execution_options(populate_existing=True)
        )
    else:
        lock_q = select(VocabularyItem).where(
            VocabularyItem.word.in_(norm_words),
            VocabularyItem.part_of_speech.in_(pos_values),
        )

    existing_rows = (await session.scalars(lock_q)).all()
    existing: dict[tuple[str, str], VocabularyItem] = {
        (normalize_word(row.word), row.part_of_speech): row for row in existing_rows
    }

    # --- Step 3: Update curated fields on existing rows (never overwrite non-blank) ---
    for key, item in seen.items():
        row = existing.get(key)
        if row is None:
            continue
        if not (row.definition or "").strip():
            row.definition = item.get("definition") or ""
        if row.translation is None:
            translation = item.get("translation")
            if translation:
                row.translation = translation
        if not row.pronunciation:
            row.pronunciation = item.get("pronunciation")
        if not row.audio_url:
            row.audio_url = item.get("audio_url")
    await session.flush()

    # --- Step 4: Insert missing rows (ON CONFLICT DO NOTHING on PostgreSQL) ---
    missing_keys = [k for k in keys if k not in existing]
    if missing_keys:
        if dialect == "postgresql":
            rows_to_insert = []
            for key in missing_keys:
                item = seen[key]
                rows_to_insert.append(
                    {
                        "id": uuid.uuid4(),
                        "word": key[0],
                        "definition": item.get("definition") or "",
                        "translation": item.get("translation"),
                        "pronunciation": item.get("pronunciation"),
                        "audio_url": item.get("audio_url"),
                        "part_of_speech": key[1],
                        "difficulty_level": item.get("difficulty_level") or "A1",
                        "tags": {
                            "source": ["content-agent", item.get("source_name", "generated")],
                            "topic": [item.get("topic", "general")],
                        },
                    }
                )
            stmt = pg_insert(VocabularyItem).values(rows_to_insert)
            stmt = stmt.on_conflict_do_nothing(
                index_elements=["word", "part_of_speech"]
            )
            await session.execute(stmt)
            await session.flush()
        else:
            # SQLite fallback (tests): insert one by one, ignore IntegrityError
            from sqlalchemy.exc import IntegrityError

            for key in missing_keys:
                item = seen[key]
                new_row = VocabularyItem(
                    word=key[0],
                    definition=item.get("definition") or "",
                    translation=item.get("translation"),
                    pronunciation=item.get("pronunciation"),
                    audio_url=item.get("audio_url"),
                    part_of_speech=key[1],
                    difficulty_level=item.get("difficulty_level") or "A1",
                    tags={
                        "source": ["content-agent", item.get("source_name", "generated")],
                        "topic": [item.get("topic", "general")],
                    },
                )
                session.add(new_row)
                try:
                    await session.flush()
                except IntegrityError:
                    await session.rollback()

    # --- Step 5: Re-select to get stable IDs for all keys --------------------
    final_rows = (
        await session.scalars(
            select(VocabularyItem).where(
                VocabularyItem.word.in_(norm_words),
                VocabularyItem.part_of_speech.in_(pos_values),
            )
        )
    ).all()

    identity: dict[tuple[str, str], uuid.UUID] = {
        (normalize_word(row.word), row.part_of_speech): row.id
        for row in final_rows
    }
    return identity
