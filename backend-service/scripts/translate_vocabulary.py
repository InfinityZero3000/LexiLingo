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

# Own knob, not EXERCISE_GEN_MODEL: local envs still pin decommissioned models there.
MODEL = os.getenv("VOCAB_TRANSLATE_MODEL", "qwen/qwen3.8-27b")
LOCALES = ("vi", "es", "fr", "ja", "ko", "zh")
LOCALE_NAMES = {
    "vi": "Vietnamese",
    "es": "Spanish",
    "fr": "French",
    "ja": "Japanese",
    "ko": "Korean",
    "zh": "Simplified Chinese",
}
# A Latin-only ja/ko/zh value is an untranslated copy.
NON_LATIN_LOCALES = {"ja", "ko", "zh"}
# Groq caps qwen at 1,000 *output* tokens per minute per key (8k TPM, 1k RPD).
# A word costs ~200 output tokens, so 3 words keep one request under the cap.
BATCH_SIZE = 3
# Each key is reused at most every KEY_COOLDOWN_S seconds. Chat answers out of
# the same keys, so this leaves it half of every key's minute.
KEY_COOLDOWN_S = 120
MAX_GLOSS_CHARS = 80
# Stand-ins for a definition: the news crawler's, and the one a word gets when a
# learner saves it from the app (USER_SAVED_PLACEHOLDER in app/crud/vocabulary.py).
CRAWL_DEFINITION_PREFIX = "Seeded from crawled lesson context"
PLACEHOLDER_DEFINITION_PREFIXES = (CRAWL_DEFINITION_PREFIX, "A user-saved word:")
PLACEHOLDER_VALUES = {"(auto)"}
# es/fr share many words with English, so "opposition" is a fair gloss for a
# one-word definition; vi has no such overlap, and a sentence is never a cognate.
COGNATE_LOCALES = {"es", "fr"}


def real_definition(definition: str | None) -> str:
    d = (definition or "").strip()
    return "" if d.startswith(PLACEHOLDER_DEFINITION_PREFIXES) else d


MAX_DAILY_WAIT_S = 900


def retry_after_seconds(message: str) -> float | None:
    """Seconds from Groq's "Please try again in 1h2m3.5s", or None."""
    m = re.search(r"try again in (?:(\d+)h)?(?:(\d+)m)?(?:([\d.]+)s)?", message)
    if not m or not any(m.groups()):
        return None
    h, mi, sec = (float(g) if g else 0.0 for g in m.groups())
    return h * 3600 + mi * 60 + sec


def _same(a: str, b: str) -> bool:
    # Ignoring punctuation so "NextSTEP" matches the headword "NextSTEP-".
    return re.sub(r"\W+", "", a.casefold()) == re.sub(r"\W+", "", b.casefold())


def valid_text(
    locale: str, text: Any, definition: str, max_chars: int = 600, word: str = ""
) -> bool:
    if not isinstance(text, str) or not text.strip() or len(text) > max_chars:
        return False
    if text.strip() in PLACEHOLDER_VALUES:
        return False
    if definition.strip() and _same(text, definition):
        if not (locale in COGNATE_LOCALES and len(definition.split()) <= 2):
            return False
    # Brand names (BMW) stay Latin in ja/ko/zh; anything else Latin is a copy.
    if locale in NON_LATIN_LOCALES and text.isascii() and not (word and _same(text, word)):
        return False
    return True


def script_done(definition: str, translation: dict | None) -> bool:
    """Every definition translation exists, so this script already wrote the word."""
    defs = (translation or {}).get("definitions")
    return isinstance(defs, dict) and all(
        valid_text(loc, defs.get(loc), definition) for loc in LOCALES
    )


def missing_parts(definition: str, translation: dict | None, word: str = "") -> list[str]:
    tr = translation if isinstance(translation, dict) else {}
    defs = tr.get("definitions") if isinstance(tr.get("definitions"), dict) else {}
    gaps = []
    if not (definition or "").strip():
        gaps.append("definition")
    if not tr.get("examples"):
        gaps.append("example")
    for loc in LOCALES:
        if not valid_text(loc, tr.get(loc), definition or "", MAX_GLOSS_CHARS, word):
            gaps.append(f"gloss.{loc}")
        if not valid_text(loc, defs.get(loc), definition or "", word=word):
            gaps.append(f"definition.{loc}")
    return gaps


def merge_result(
    definition: str, translation: dict | None, result: dict, overwrite: bool, word: str = ""
) -> tuple[str, dict]:
    """Return (definition, translation) with every valid new value applied."""
    tr = dict(translation) if isinstance(translation, dict) else {}
    defs = dict(tr.get("definitions")) if isinstance(tr.get("definitions"), dict) else {}

    new_definition = definition or ""
    proposed = result.get("definition")
    if not new_definition.strip() and isinstance(proposed, str) and proposed.strip():
        new_definition = proposed.strip()

    example = result.get("example")
    if not tr.get("examples") and isinstance(example, str) and example.strip():
        tr["examples"] = [example.strip()]

    glosses = result.get("gloss") if isinstance(result.get("gloss"), dict) else {}
    def_tr = (
        result.get("definition_translation")
        if isinstance(result.get("definition_translation"), dict)
        else {}
    )
    for loc in LOCALES:
        if overwrite or not valid_text(loc, tr.get(loc), new_definition, MAX_GLOSS_CHARS, word):
            if valid_text(loc, glosses.get(loc), new_definition, MAX_GLOSS_CHARS, word):
                tr[loc] = glosses[loc].strip()
        if overwrite or not valid_text(loc, defs.get(loc), new_definition, word=word):
            if valid_text(loc, def_tr.get(loc), new_definition, word=word):
                defs[loc] = def_tr[loc].strip()
    if defs:
        tr["definitions"] = defs
    return new_definition, tr


def build_prompt(rows: list[dict]) -> str:
    items = [
        {
            "id": r["id"],
            "word": r["word"],
            "part_of_speech": r["part_of_speech"],
            "definition": r["definition"] or "",
            "example": ((r["translation"] or {}).get("examples") or [""])[0],
        }
        for r in rows
    ]
    langs = ", ".join(f'"{k}" = {v}' for k, v in LOCALE_NAMES.items())
    return (
        "You are a professional lexicographer writing a bilingual learner's "
        "dictionary for English learners.\n"
        f"Target languages: {langs}.\n"
        "For EVERY input item return an object with:\n"
        '  "id": the same id,\n'
        '  "definition": a short English learner definition — ONLY if the input '
        "definition is empty, else \"\",\n"
        '  "example": one natural English sentence using the word in this sense — '
        "ONLY if the input example is empty, else \"\",\n"
        '  "gloss": {lang: the word\'s meaning in that language, 1-4 words, '
        "exactly what a bilingual dictionary lists as the headword translation — "
        "no explanation, no English, no quotes},\n"
        '  "definition_translation": {lang: the English definition translated '
        "naturally and faithfully}.\n"
        "Use the part of speech and definition to pick the right sense. "
        "Chinese must be Simplified. Do not transliterate English. "
        "A gloss must be a native word of that language: never copy the English "
        "word or use an anglicism or false friend (reluctant -> fr \"réticent\", "
        "es \"reacio\"); keep an identical spelling only when that language "
        "really uses it (hotel -> es \"hotel\").\n"
        'Answer with JSON only: {"items": [...]}\n\n'
        f"Input:\n{json.dumps(items, ensure_ascii=False)}"
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
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": build_prompt(rows)}],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
        "max_tokens": 1000,
    }
    if "qwen" in MODEL:
        # Without it qwen writes <think> prose into content (CLAUDE.md, Groq notes).
        payload["reasoning_effort"] = "none"
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
