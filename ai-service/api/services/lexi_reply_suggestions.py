"""Suggested replies a learner can tap after Lexi asks them a question."""

from __future__ import annotations

import json
import logging
import re
from typing import List

logger = logging.getLogger(__name__)

_GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
_MAX_INPUT_CHARS = 600
_MAX_OPTIONS = 3
_MAX_OPTION_CHARS = 120
_TOKEN_ESTIMATE = 220

_SYSTEM_PROMPT = (
    "You help a language learner reply to their tutor in a chat. "
    "Return ONLY a JSON array of strings, no markdown, no explanation."
)


def ends_with_question(text: str) -> bool:
    """A question mark in the last stretch — ASCII or full-width, so ja/zh/ko count."""
    return bool(re.search(r"[?？]", text[-80:]))


def build_user_prompt(tutor_text: str) -> str:
    return (
        f'Tutor said: "{tutor_text[:_MAX_INPUT_CHARS]}"\n'
        f"Write {_MAX_OPTIONS} different replies the learner could send. Each is simple, "
        "natural, under 12 words, and in the same language the tutor's question is in. "
        "Make them differ in meaning (e.g. yes / no / a detail), not just in wording.\n"
        'Example: ["I usually walk to work.","By bus, because it is cheap.","It depends on the weather."]'
    )


def parse_options(raw: str) -> List[str]:
    match = re.search(r"\[[\s\S]*\]", raw or "")
    if not match:
        return []
    try:
        items = json.loads(match.group())
    except json.JSONDecodeError:
        return []
    out: List[str] = []
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, str):
            continue
        text = item.strip()
        if text and len(text) <= _MAX_OPTION_CHARS and text not in out:
            out.append(text)
    return out[:_MAX_OPTIONS]


async def suggest_replies(tutor_text: str) -> List[str]:
    """Up to three replies; [] when the text is no question or no LLM is reachable."""
    if not ends_with_question(tutor_text):
        return []

    from api.core.groq_key_pool import (
        get_available_groq_key,
        record_groq_key_usage,
        resolve_groq_model,
    )
    from api.services.trace_cag.llm_client import _throttled_post_json

    key = await get_available_groq_key(estimated_tokens=_TOKEN_ESTIMATE)
    if not key:
        return []
    try:
        resp = await _throttled_post_json(
            provider="groq",
            url=_GROQ_URL,
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            payload={
                "model": resolve_groq_model(),
                "messages": [
                    {"role": "system", "content": _SYSTEM_PROMPT},
                    {"role": "user", "content": build_user_prompt(tutor_text)},
                ],
                "max_tokens": 160,
                "temperature": 0.7,
            },
            timeout=12.0,
        )
        if resp is None or resp.status_code != 200:
            return []
        data = resp.json()
        await record_groq_key_usage(key, data.get("usage", {}).get("total_tokens", _TOKEN_ESTIMATE))
        return parse_options(data["choices"][0]["message"]["content"])
    except Exception as exc:
        logger.warning("[lexi_suggest] failed: %s", exc)
        return []
