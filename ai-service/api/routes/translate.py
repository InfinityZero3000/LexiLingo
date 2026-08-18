"""
Contextual Word Translation Route

GET /api/v1/ai/translate?word=run&lang=vi&context=run+a+company

Replaces MyMemory API (5k chars/day limit) with LLM-powered contextual translation.
Fallback chain: Groq qwen3-32b → Ollama qwen3:1.7b → empty string.
"""

from __future__ import annotations

import json
import logging
import os
import re
from typing import Optional

from fastapi import APIRouter, Depends, Query

from api.routes.admin import verify_admin_api_key

logger = logging.getLogger(__name__)

router = APIRouter()

_SYSTEM_PROMPT = (
    "You are a Vietnamese-English dictionary assistant. "
    "Return ONLY valid JSON, no markdown, no explanation."
)

_GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"


def _build_user_prompt(word: str, lang: str, context: str) -> str:
    context_line = f'\nContext sentence: "{context}"' if context.strip() else ""
    return (
        f'Word: "{word}"{context_line}\n'
        f'Return JSON with exactly these keys: '
        f'translation (meaning in {lang}), '
        f'phonetic (IPA notation or empty string), '
        f'part_of_speech (noun/verb/adjective/adverb/etc or empty string).\n'
        f'Example: {{"translation":"chạy","phonetic":"/rʌn/","part_of_speech":"verb"}}'
    )


def _parse_llm_json(raw: str) -> dict:
    """Extract the JSON object from LLM response, stripping any markdown fences."""
    raw = raw.strip()
    # Strip ```json ... ``` fences if present
    fenced = re.search(r"```(?:json)?\s*(\{[\s\S]*?\})\s*```", raw)
    if fenced:
        raw = fenced.group(1)
    # Find first {...} block
    match = re.search(r"\{[\s\S]*\}", raw)
    if not match:
        return {}
    try:
        return json.loads(match.group())
    except json.JSONDecodeError:
        return {}


async def _translate_via_groq(word: str, lang: str, context: str) -> Optional[dict]:
    """Try Groq qwen3-32b for contextual translation. Returns None if unavailable."""
    from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage
    from api.services.trace_cag.llm_client import _throttled_post_json

    groq_key = await get_available_groq_key(estimated_tokens=130)
    if not groq_key:
        logger.info("[translate] Groq key pool exhausted, skipping")
        return None

    # Must be a non-reasoning model: this call caps max_tokens at 80, and a
    # reasoning model spends that budget before emitting any content —
    # openai/gpt-oss-20b burns 78 reasoning tokens and returns "".
    groq_model = os.getenv("GROQ_MODEL", "groq/compound-mini")
    messages = [
        {"role": "system", "content": _SYSTEM_PROMPT},
        {"role": "user", "content": _build_user_prompt(word, lang, context)},
    ]

    try:
        resp = await _throttled_post_json(
            provider="groq",
            url=_GROQ_URL,
            headers={
                "Authorization": f"Bearer {groq_key}",
                "Content-Type": "application/json",
            },
            payload={
                "model": groq_model,
                "messages": messages,
                "max_tokens": 80,
                "temperature": 0.0,
            },
            timeout=12.0,
        )

        if resp is None or resp.status_code != 200:
            logger.warning(
                "[translate] Groq returned %s",
                getattr(resp, "status_code", "no response"),
            )
            return None

        data = resp.json()
        tokens_used = data.get("usage", {}).get("total_tokens", 130)
        await record_groq_key_usage(groq_key, tokens_used)

        content = data["choices"][0]["message"]["content"]
        parsed = _parse_llm_json(content)
        if parsed.get("translation"):
            return parsed

        logger.warning("[translate] Groq response had no translation field: %s", content[:200])
        return None

    except Exception as exc:
        logger.warning("[translate] Groq call failed: %s", exc)
        return None


async def _translate_via_ollama(word: str, lang: str, context: str) -> Optional[dict]:
    """Fallback: Ollama local model (always available, 0 cost, ~1-2s latency)."""
    try:
        from api.services.ollama_service import get_ollama_service

        ollama = get_ollama_service()
        if not await ollama.health_check():
            logger.info("[translate] Ollama unavailable, skipping")
            return None

        messages = [
            {"role": "system", "content": _SYSTEM_PROMPT},
            {"role": "user", "content": _build_user_prompt(word, lang, context)},
        ]
        raw = await ollama.chat(
            messages=messages,
            temperature=0.0,
            max_tokens=80,
        )
        parsed = _parse_llm_json(raw)
        if parsed.get("translation"):
            return parsed

        logger.info("[translate] Ollama response had no translation: %s", str(raw)[:200])
        return None

    except Exception as exc:
        logger.warning("[translate] Ollama call failed: %s", exc)
        return None


@router.get("/translate")
async def translate_word(
    word: str = Query(..., min_length=1, max_length=100, description="English word to translate"),
    lang: str = Query("vi", description="Target language code (vi, fr, ja, …)"),
    context: str = Query("", max_length=500, description="Caption sentence the word appears in"),
    _admin_key: str = Depends(verify_admin_api_key),
):
    """
    Contextual LLM-powered word translation.

    Fallback chain: Groq qwen3-32b → Ollama qwen3:1.7b → empty fields.
    Called by backend-service /youtube/translate; never hits this endpoint directly from Flutter.
    """
    clean_word = word.lower().strip()

    result = await _translate_via_groq(clean_word, lang, context)
    if result is None:
        result = await _translate_via_ollama(clean_word, lang, context)

    if result is None:
        logger.info("[translate] All backends failed for word='%s', returning empty", clean_word)
        result = {}

    return {
        "word": clean_word,
        "translation": result.get("translation", ""),
        "phonetic": result.get("phonetic", ""),
        "part_of_speech": result.get("part_of_speech", ""),
    }
