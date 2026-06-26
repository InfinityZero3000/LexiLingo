"""Conservative transcript normalization."""

from __future__ import annotations

import re

_WHITESPACE = re.compile(r"\s+")
_FILLER_ONLY = re.compile(
    r"^(um+|uh+|hmm+|mm+|hm+|ah+|er+|eh+|mhm+)\.?$",
    re.IGNORECASE,
)


def normalize_transcript(
    text: str, preserve_exact: bool = False
) -> tuple[str, list[str]]:
    """Return (normalized_text, rules_applied).

    Returns ("", ["filler_removed"]) or ("", ["hallucination_removed"]) when the
    input is pure noise so callers can discard it without additional checks.
    preserve_exact=True skips noise removal and punctuation (pronunciation scoring).
    """
    rules: list[str] = []

    trimmed = _WHITESPACE.sub(" ", text).strip()
    if trimmed != text:
        rules.append("trim")
    text = trimmed

    if not preserve_exact:
        if _FILLER_ONLY.match(text):
            return "", ["filler_removed"]

        deduped = _deduplicate_repetitions(text)
        if deduped != text:
            if not deduped:
                return "", ["hallucination_removed"]
            text = deduped
            rules.append("deduplication")

        if text and text[-1] not in ".?!":
            text += "."
            rules.append("punctuation")

    return text, rules


def _deduplicate_repetitions(text: str) -> str:
    """Remove leading repeated n-grams (Moonshine hallucination artifact).

    "hello world hello world hello world" → "hello world"
    "I want to I want to I want to" → "I want to"
    "can can can you help me" → "can you help me"
    """
    words = text.split()
    if len(words) < 3:
        return text
    for n in (3, 2, 1):
        result = _strip_leading_ngram_repeat(words, n)
        if result is not None:
            return " ".join(result)
    return text


def _strip_leading_ngram_repeat(words: list[str], n: int) -> list[str] | None:
    """Return deduplicated word list if the leading n-gram repeats ≥3 times, else None."""
    if len(words) < n * 3:
        return None
    seed = words[:n]
    pos = 0
    reps = 0
    while pos + n <= len(words) and words[pos : pos + n] == seed:
        reps += 1
        pos += n
    if reps < 3:
        return None
    return seed + words[pos:]
