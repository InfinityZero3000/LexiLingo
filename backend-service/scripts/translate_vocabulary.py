"""
Translate the vocabulary catalogue into every UI language via Groq.

Per word it fills what is missing or broken:
  - definition                       English learner definition, if blank
  - translation["examples"]          one example sentence, if there is none
  - translation[<locale>]            short gloss — what the flashcard shows
  - translation["definitions"][<l>]  the definition in that language

English needs no gloss (it is the word itself), so only the six other UI
locales are written. A value that merely repeats the English definition, or a
ja/ko/zh value with no CJK/Hangul in it, counts as broken and is redone.

Default touches only words with something missing or broken, so a rerun after
the content agent lands new words costs only those words. --all also replaces
every old gloss (Wiktionary lists, admin entries) on words this script has not
finished; rerunning it after an interruption resumes rather than restarts. --dry-run writes nothing and
prints old → new for review.

    cd backend-service
    venv/bin/python3 scripts/translate_vocabulary.py --dry-run --limit=30
    venv/bin/python3 scripts/translate_vocabulary.py

Pace: 3 words per request, each Groq key reused every 2 minutes, so 7 keys do
~10 words/min (1,000 words ≈ 1.6 h). Run it off-peak: chat uses the same keys.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import sys
import time
import uuid
from pathlib import Path
from typing import Any

import os

import httpx

sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from generate_exercises_ai import GROQ_API_KEYS, GROQ_URL, next_groq_key
from sqlalchemy import select, update

from app.core.database import AsyncSessionLocal
from app.models.vocabulary import VocabularyItem
from app.services.vocabulary_translation import (  # noqa: F401 - re-exported for tests
    BATCH_SIZE,
    COGNATE_LOCALES,
    KEY_COOLDOWN_S,
    LOCALE_NAMES,
    LOCALES,
    MAX_DAILY_WAIT_S,
    MAX_GLOSS_CHARS,
    MODEL,
    NON_LATIN_LOCALES,
    build_payload,
    build_prompt,
    merge_result,
    missing_parts,
    real_definition,
    retry_after_seconds,
    script_done,
    valid_text,
)

_429_seen: list[str] = []
_spent_keys: dict[str, float] = {}  # key -> monotonic time its daily cap lifts


async def pick_key() -> str:
    """Next key from the rotation, skipping ones whose daily cap is spent."""
    now = time.monotonic()
    for _ in range(len(GROQ_API_KEYS)):
        key = await next_groq_key()
        if _spent_keys.get(key, 0) <= now:
            return key
    raise _AllSpent(min(_spent_keys.values()) - now)


class _AllSpent(Exception):
    def __init__(self, wait: float):
        self.wait = max(wait, 1.0)


async def translate_batch(client: httpx.AsyncClient, rows: list[dict]) -> dict[str, dict]:
    payload = build_payload(rows)
    for attempt in range(max(3, len(GROQ_API_KEYS))):
        try:
            key = await pick_key()
        except _AllSpent as spent:
            if spent.wait > MAX_DAILY_WAIT_S:
                raise SystemExit("Every Groq key has spent its daily limit, resume later")
            print(f"    [daily limit] every key spent, waiting {spent.wait:.0f}s")
            await asyncio.sleep(spent.wait + 1)
            continue
        try:
            resp = await client.post(
                GROQ_URL,
                json=payload,
                headers={"Authorization": f"Bearer {key}"},
                timeout=90.0,
            )
        except httpx.HTTPError as exc:
            print(f"    [network] {exc} — retrying")
            await asyncio.sleep(5)
            continue
        if resp.status_code == 200:
            try:
                data = json.loads(resp.json()["choices"][0]["message"]["content"])
                ids = {r["id"] for r in rows}
                return {
                    str(it["id"]): it
                    for it in data.get("items", [])
                    if isinstance(it, dict) and str(it.get("id")) in ids
                }
            except (KeyError, ValueError, TypeError) as exc:
                print(f"    [bad JSON] {exc} — retrying")
                continue
        if resp.status_code in (401, 403) or (
            resp.status_code == 400 and "json_validate_failed" not in resp.text
        ):
            raise SystemExit(f"Groq rejected the request: {resp.status_code} {resp.text[:300]}")
        if resp.status_code == 429:
            message = resp.text
            if "per day" in message.lower():
                # The daily window rolls, so a short "try again in 5m24s" is worth
                # waiting out; a long one means the run should stop and resume later.
                wait = retry_after_seconds(message)
                if wait is None:
                    raise SystemExit(f"Groq daily limit reached, resume later: {message[:300]}")
                _spent_keys[key] = time.monotonic() + wait
                continue
            if not _429_seen:
                _429_seen.append(message)
                print(f"    [HTTP 429, first seen] {message[:300]}")
        wait = 1 if resp.status_code == 429 and len(GROQ_API_KEYS) > 1 else 10 * (attempt + 1)
        print(f"    [HTTP {resp.status_code}] retrying in {wait}s")
        await asyncio.sleep(wait)
    return {}


async def load_rows(redo_all: bool, limit: int | None) -> list[dict]:
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(
                VocabularyItem.id,
                VocabularyItem.word,
                VocabularyItem.part_of_speech,
                VocabularyItem.definition,
                VocabularyItem.translation,
            ).order_by(VocabularyItem.word)
        )
        rows = [
            {
                "id": str(r.id),
                "word": r.word,
                "part_of_speech": str(getattr(r.part_of_speech, "value", r.part_of_speech)),
                "stored_definition": r.definition or "",
                "definition": real_definition(r.definition),
                "translation": r.translation if isinstance(r.translation, dict) else {},
            }
            for r in result
        ]
    for r in rows:
        # --all replaces old glosses, but only on words this script has not
        # finished yet, so an interrupted run resumes instead of restarting.
        r["overwrite"] = redo_all and not script_done(r["definition"], r["translation"])
    todo = [
        r for r in rows
        if r["overwrite"] or missing_parts(r["definition"], r["translation"], r["word"])
    ]
    print(f"{len(rows)} words in the catalogue, {len(todo)} to translate")
    return todo[:limit] if limit else todo


async def save(items: list[tuple[dict, dict]]) -> None:
    """Merge into the row as it is now: a run takes hours, admins and learners edit meanwhile."""
    async with AsyncSessionLocal() as db:
        for row, result in items:
            current = (
                await db.execute(
                    select(VocabularyItem.definition, VocabularyItem.translation)
                    .where(VocabularyItem.id == uuid.UUID(row["id"]))
                    .with_for_update()
                )
            ).one_or_none()
            if current is None:
                continue
            stored = current.definition or ""
            translation = current.translation if isinstance(current.translation, dict) else {}
            definition, merged = merge_result(
                real_definition(stored), translation, result, row["overwrite"], row["word"]
            )
            await db.execute(
                update(VocabularyItem)
                .where(VocabularyItem.id == uuid.UUID(row["id"]))
                .values(definition=definition or stored, translation=merged)
            )
        await db.commit()


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true", help="redo every word")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument(
        "--delay", type=float, help="seconds between requests (default: key cooldown / keys)"
    )
    args = parser.parse_args()
    if not GROQ_API_KEYS:
        raise SystemExit("Set GROQ_API_KEYS (or GROQ_API_KEY) in backend-service/.env")
    if args.delay is None:
        args.delay = KEY_COOLDOWN_S / len(GROQ_API_KEYS)

    rows = await load_rows(args.all, args.limit)
    batches = [rows[i : i + BATCH_SIZE] for i in range(0, len(rows), BATCH_SIZE)]
    sem = asyncio.Semaphore(args.concurrency)
    stats = {"words": 0, "complete": 0, "still_missing": 0}

    async def run(idx: int, batch: list[dict], client: httpx.AsyncClient) -> None:
        async with sem:
            results = await translate_batch(client, batch)
            await asyncio.sleep(args.delay)
        updates = []
        for row in batch:
            result = results.get(row["id"], {})
            definition, translation = merge_result(
                row["definition"], row["translation"], result, row["overwrite"], row["word"],
            )
            definition = definition or row["stored_definition"]
            gaps = missing_parts(real_definition(definition), translation, row["word"])
            stats["words"] += 1
            stats["still_missing" if gaps else "complete"] += 1
            if args.dry_run:
                print(
                    f"  {row['word']} ({row['part_of_speech']}): "
                    + json.dumps({k: translation.get(k) for k in LOCALES}, ensure_ascii=False)
                    + (f"  MISSING {gaps}" if gaps else "")
                )
            if (definition, translation) != (row["stored_definition"], row["translation"]):
                updates.append((row, result))
        if updates and not args.dry_run:
            await save(updates)
        print(f"[{idx + 1}/{len(batches)}] {len(updates)} words updated")

    async with httpx.AsyncClient() as client:
        await asyncio.gather(*(run(i, b, client) for i, b in enumerate(batches)))

    print(
        f"Done: {stats['words']} words, {stats['complete']} complete, "
        f"{stats['still_missing']} still missing something (rerun to retry)"
        + (" — DRY RUN, nothing written" if args.dry_run else "")
    )


if __name__ == "__main__":
    asyncio.run(main())
