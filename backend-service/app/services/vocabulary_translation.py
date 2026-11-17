"""Vocabulary translation core: what is missing, the Groq prompt, validation, merge, per-item enrichment."""

from __future__ import annotations

import json
import logging
import os
import re
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.vocabulary import VocabularyItem

logger = logging.getLogger(__name__)

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"

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


def build_payload(rows: list[dict]) -> dict[str, Any]:
    """Groq request body; qwen needs reasoning_effort none or it writes <think> prose into content."""
    payload: dict[str, Any] = {
        "model": MODEL,
        "messages": [{"role": "user", "content": build_prompt(rows)}],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
        "max_tokens": 1000,
    }
    if "qwen" in MODEL:
        payload["reasoning_effort"] = "none"
    return payload


def parse_response(body: dict[str, Any], rows: list[dict]) -> dict[str, dict]:
    """Items of a Groq chat response keyed by id; raises ValueError/KeyError/TypeError on a bad shape."""
    data = json.loads(body["choices"][0]["message"]["content"])
    ids = {r["id"] for r in rows}
    return {
        str(it["id"]): it
        for it in data.get("items", [])
        if isinstance(it, dict) and str(it.get("id")) in ids
    }


class GroqRetryable(Exception):
    """Rate limit, timeout, 5xx or unreadable answer: try again later."""

    def __init__(self, message: str, retry_after: float | None = None):
        super().__init__(message)
        self.retry_after = retry_after


class GroqFatal(Exception):
    """Key or request rejected: retrying the same call cannot help."""


def groq_keys() -> list[str]:
    raw = settings.GROQ_API_KEYS or settings.GROQ_API_KEY or ""
    return [k.strip() for k in raw.split(",") if k.strip()]


_key_cursor = 0
_key_cooldown: dict[str, float] = {}  # key -> monotonic time it may be used again


def _next_key(keys: list[str]) -> str | None:
    global _key_cursor
    now = time.monotonic()
    for _ in range(len(keys)):
        key = keys[_key_cursor % len(keys)]
        _key_cursor += 1
        if _key_cooldown.get(key, 0) <= now:
            return key
    return None


async def request_translations(
    client: httpx.AsyncClient, rows: list[dict], keys: list[str] | None = None
) -> dict[str, dict]:
    """One Groq call, rotating past keys that answer 429; raises GroqRetryable / GroqFatal."""
    keys = keys if keys is not None else groq_keys()
    if not keys:
        raise GroqFatal("no Groq key configured")
    payload = build_payload(rows)
    last_wait: float | None = None
    for _ in range(len(keys)):
        key = _next_key(keys)
        if key is None:
            break
        try:
            resp = await client.post(
                GROQ_URL, json=payload, headers={"Authorization": f"Bearer {key}"}, timeout=90.0
            )
        except httpx.HTTPError as exc:
            raise GroqRetryable(f"network: {type(exc).__name__}") from exc
        if resp.status_code == 200:
            try:
                return parse_response(resp.json(), rows)
            except (KeyError, ValueError, TypeError) as exc:
                raise GroqRetryable(f"unreadable answer: {exc}") from exc
        if resp.status_code == 429:
            last_wait = retry_after_seconds(resp.text)
            _key_cooldown[key] = time.monotonic() + (last_wait or 60.0)
            continue
        if resp.status_code in (401, 403) or (
            resp.status_code == 400 and "json_validate_failed" not in resp.text
        ):
            raise GroqFatal(f"Groq rejected the request: {resp.status_code} {resp.text[:200]}")
        raise GroqRetryable(f"HTTP {resp.status_code}")
    raise GroqRetryable("every Groq key is rate limited", retry_after=last_wait)


def row_for(item: Any) -> dict:
    stored = item.definition or ""
    return {
        "id": str(item.id),
        "word": item.word,
        "part_of_speech": str(getattr(item.part_of_speech, "value", item.part_of_speech)),
        "stored_definition": stored,
        "definition": real_definition(stored),
        "translation": item.translation if isinstance(item.translation, dict) else {},
        "overwrite": False,
    }


def item_gaps(item: Any) -> list[str]:
    row = row_for(item)
    return missing_parts(row["definition"], row["translation"], row["word"])


@dataclass
class EnrichOutcome:
    status: str  # "missing" | "complete" | "enriched" | "partial"
    gaps: list[str]


async def enrich_item(
    db: AsyncSession, item_id: uuid.UUID, client: httpx.AsyncClient | None = None
) -> EnrichOutcome:
    """Fill what one item lacks; no-op when complete. Groq failures propagate as GroqRetryable/GroqFatal."""
    item = (await db.execute(select(VocabularyItem).where(VocabularyItem.id == item_id))).scalar_one_or_none()
    if item is None:
        return EnrichOutcome("missing", [])
    row = row_for(item)
    if not missing_parts(row["definition"], row["translation"], row["word"]):
        return EnrichOutcome("complete", [])

    if client is None:
        async with httpx.AsyncClient() as own:
            results = await request_translations(own, [row])
    else:
        results = await request_translations(client, [row])

    # Re-read under lock: admins and learners edit while Groq thinks.
    current = (
        await db.execute(
            select(VocabularyItem.definition, VocabularyItem.translation)
            .where(VocabularyItem.id == item_id)
            .with_for_update()
        )
    ).one_or_none()
    if current is None:
        return EnrichOutcome("missing", [])
    stored = current.definition or ""
    translation = current.translation if isinstance(current.translation, dict) else {}
    definition, merged = merge_result(
        real_definition(stored), translation, results.get(row["id"], {}), False, row["word"]
    )
    definition = definition or stored
    gaps = missing_parts(real_definition(definition), merged, row["word"])
    values: dict[str, Any] = {"definition": definition, "translation": merged}
    if (definition, merged) == (stored, translation):
        # Nothing usable came back: bump updated_at so the sweep tries other words first.
        values = {"updated_at": datetime.now(timezone.utc)}
    await db.execute(update(VocabularyItem).where(VocabularyItem.id == item_id).values(**values))
    await db.commit()
    return EnrichOutcome("partial" if gaps else "enriched", gaps)


async def find_incomplete_ids(db: AsyncSession, limit: int, chunk: int = 500) -> list[uuid.UUID]:
    """Oldest-touched incomplete items first; scans in chunks and stops once `limit` are found."""
    found: list[uuid.UUID] = []
    offset = 0
    while len(found) < limit:
        rows = (
            await db.execute(
                select(
                    VocabularyItem.id,
                    VocabularyItem.word,
                    VocabularyItem.part_of_speech,
                    VocabularyItem.definition,
                    VocabularyItem.translation,
                )
                .order_by(VocabularyItem.updated_at, VocabularyItem.id)
                .offset(offset)
                .limit(chunk)
            )
        ).all()
        if not rows:
            break
        for r in rows:
            if item_gaps(r):
                found.append(r.id)
                if len(found) >= limit:
                    break
        offset += chunk
    return found


def schedule_enrichment(item: Any) -> bool:
    """Queue enrichment for an incomplete item; never raises, so a broker outage cannot fail a save."""
    if not settings.VOCAB_AUTO_TRANSLATE_ENABLED or not item_gaps(item):
        return False
    try:
        from app.tasks.vocabulary_enrichment import enrich_vocabulary_item

        enrich_vocabulary_item.apply_async(args=[str(item.id)], retry=False)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Could not queue vocabulary enrichment for %s: %s", item.id, type(exc).__name__)
        return False
    return True
