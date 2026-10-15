"""Raw score to IELTS band, and the answer matching that produces the raw score.

The conversion tables are the published band boundaries for a 40-question
paper. Reading has two of them because General Training is the easier paper and
demands more correct answers for the same band — using the Academic table for a
GT paper inflates every result by roughly half a band in the middle of the range.
"""

from __future__ import annotations

import re
from decimal import Decimal, ROUND_HALF_UP

# (minimum raw score, band). Ordered high to low; first match wins.
_LISTENING_BANDS: tuple[tuple[int, float], ...] = (
    (39, 9.0), (37, 8.5), (35, 8.0), (32, 7.5), (30, 7.0), (26, 6.5),
    (23, 6.0), (18, 5.5), (16, 5.0), (13, 4.5), (10, 4.0), (8, 3.5),
    (6, 3.0), (4, 2.5), (3, 2.0), (2, 1.5), (1, 1.0),
)

_READING_ACADEMIC_BANDS: tuple[tuple[int, float], ...] = (
    (39, 9.0), (37, 8.5), (35, 8.0), (33, 7.5), (30, 7.0), (27, 6.5),
    (23, 6.0), (19, 5.5), (15, 5.0), (13, 4.5), (10, 4.0), (8, 3.5),
    (6, 3.0), (4, 2.5), (3, 2.0), (2, 1.5), (1, 1.0),
)

_READING_GENERAL_BANDS: tuple[tuple[int, float], ...] = (
    (40, 9.0), (39, 8.5), (37, 8.0), (36, 7.5), (34, 7.0), (32, 6.5),
    (30, 6.0), (27, 5.5), (23, 5.0), (19, 4.5), (15, 4.0), (12, 3.5),
    (9, 3.0), (6, 2.5), (4, 2.0), (2, 1.5), (1, 1.0),
)

# A paper does not always carry the full 40 questions — a single-part practice
# set is common. The tables are defined on 40, so a shorter paper is scaled up
# to the 40-question equivalent before lookup.
_STANDARD_QUESTION_COUNT = 40


def _band_from_table(
    raw: int, total: int, table: tuple[tuple[int, float], ...]
) -> float:
    if total <= 0:
        return 0.0
    raw = max(0, min(raw, total))
    scaled = round(raw * _STANDARD_QUESTION_COUNT / total)
    for minimum, band in table:
        if scaled >= minimum:
            return band
    return 0.0


def listening_band(raw: int, total: int = _STANDARD_QUESTION_COUNT) -> float:
    return _band_from_table(raw, total, _LISTENING_BANDS)


def reading_band(
    raw: int, total: int = _STANDARD_QUESTION_COUNT, test_type: str = "academic"
) -> float:
    table = (
        _READING_GENERAL_BANDS
        if (test_type or "").strip().lower() == "general_training"
        else _READING_ACADEMIC_BANDS
    )
    return _band_from_table(raw, total, table)


def round_to_half_band(value: float | Decimal) -> float:
    """Round to the nearest half band, with .25 and .75 going up.

    This is the published overall-band rule: 6.375 reports as 6.5, 6.125 as 6.0.
    Doing it with plain floats gets 6.25 wrong, because banker's rounding sends
    it down to 6.0 while IELTS sends it up to 6.5.
    """
    doubled = Decimal(str(value)) * 2
    return float(doubled.quantize(Decimal("1"), rounding=ROUND_HALF_UP) / 2)


def overall_band(bands: dict[str, float | None]) -> float | None:
    """Mean of the four skill bands, rounded the IELTS way.

    Returns None unless all four skills are present: an overall band computed
    from two skills is not an IELTS score, and reporting one would let a
    Reading-only sitting look like a full result.
    """
    required = ("listening", "reading", "writing", "speaking")
    values = [bands.get(skill) for skill in required]
    if any(value is None for value in values):
        return None
    return round_to_half_band(sum(float(v) for v in values) / 4)


_PUNCTUATION = re.compile(r"[^\w\s'/-]")
_WHITESPACE = re.compile(r"\s+")
_ARTICLES = ("a ", "an ", "the ")


def normalize_answer(value: str) -> str:
    """Case, spacing and punctuation are never marked in IELTS."""
    text = _PUNCTUATION.sub(" ", str(value or "").strip().lower())
    return _WHITESPACE.sub(" ", text).strip()


def answer_matches(user_answer: str, accepted: list[str] | str | None) -> bool:
    """True when the learner's answer matches any accepted form.

    A leading article is ignored on both sides. IELTS mark schemes write the
    accepted answer as "(the) library", meaning both forms score — spelling out
    every variant in the content would be the alternative, and authors forget.
    """
    if accepted is None:
        return False
    candidates = accepted if isinstance(accepted, list) else [accepted]
    given = normalize_answer(user_answer)
    if not given:
        return False

    def strip_article(text: str) -> str:
        for article in _ARTICLES:
            if text.startswith(article):
                return text[len(article):]
        return text

    given_bare = strip_article(given)
    for candidate in candidates:
        expected = normalize_answer(candidate)
        if not expected:
            continue
        if given == expected or given_bare == strip_article(expected):
            return True
    return False
