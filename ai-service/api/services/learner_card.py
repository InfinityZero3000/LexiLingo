"""Learner card: the CAG half of Lexi's grounding.

The shared corpus (grammar, vocabulary, concepts) is retrieved per turn by
TRACE-CAG — that part is RAG-shaped and has to be, because the query decides
what is relevant. The learner's *own* facts are not a retrieval problem: the
answer to "what level am I" does not depend on the wording of the question.
So they are fetched once as a single aggregate, cached, and preloaded into
the prompt — CAG, one Redis GET on the hot path instead of a cross-service
join per turn.

Two things keep it cheap:
  - the card is only injected when the turn actually asks about the learner
    or about courses (see `detect_learner_intents`), so ordinary tutoring
    turns pay nothing and the tutor prompt stays undiluted;
  - a short TTL replaces an invalidation web. A learner who levels up sees
    the new level within `LEXI_LEARNER_CARD_TTL_SECONDS`.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

import httpx

from api.core.config import settings

logger = logging.getLogger(__name__)

_CACHE_PREFIX = "lexi:learner_card:"
_CACHE_TTL_SECONDS = 120
_FETCH_TIMEOUT_SECONDS = 1.5

# Vietnamese and English, because learners write in both here. Kept as plain
# substrings on a lowercased, accent-preserving haystack — a classifier call
# would cost more than the lookup it is gating.
_IDENTITY_PATTERNS = (
    "tên tôi", "tên mình", "tên em", "tôi tên", "mình tên", "tôi là ai",
    "mình là ai", "biết tôi", "biết mình", "hồ sơ", "thông tin của tôi",
    "thông tin cá nhân", "tài khoản của tôi",
    "my name", "who am i", "about me", "my profile", "my account",
)
_PROGRESS_PATTERNS = (
    "trình độ", "cấp độ", "level của", "tôi đang ở", "mình đang ở", "tiến độ",
    "điểm của tôi", "điểm của mình", "kết quả học", "streak", "chuỗi ngày",
    "xp của", "tôi học được", "mình học được", "tôi giỏi", "tôi yếu",
    "mình yếu", "điểm mạnh", "điểm yếu", "học tới đâu", "học đến đâu",
    "bao nhiêu bài", "bao nhiêu xp", "bao nhiêu điểm", "lên level", "lên trình",
    "tôi tiến bộ", "mình tiến bộ", "tôi đang học gì", "mình đang học gì",
    "my level", "my progress", "my score", "my streak", "my xp", "how am i doing",
    "my strengths", "my weaknesses", "am i improving", "how many lessons",
    "what am i studying", "what am i learning",
)
_COURSE_PATTERNS = (
    "khóa học", "khoá học", "học khóa", "học khoá", "nên học gì", "học gì tiếp",
    "học gì tiếp theo", "lộ trình", "gợi ý khóa", "gợi ý khoá", "phù hợp với tôi",
    "phù hợp với mình", "nên bắt đầu từ đâu", "bắt đầu từ đâu", "học gì bây giờ",
    "nên học cái gì", "khoá nào", "khóa nào",
    "course", "courses", "what should i learn",
    "what should i study", "recommend", "suggestion", "learning path",
    "where should i start", "what to learn next",
)

_SKILL_LABELS = {
    "listening": "listening",
    "speaking": "speaking",
    "reading": "reading",
    "writing": "writing",
    "vocabulary": "vocabulary",
    "grammar": "grammar",
}


def detect_learner_intents(text: str) -> set[str]:
    """Which slices of the learner card this turn needs, if any."""
    if not text:
        return set()
    haystack = re.sub(r"\s+", " ", text.lower())
    intents: set[str] = set()
    if any(pattern in haystack for pattern in _IDENTITY_PATTERNS):
        intents.add("identity")
    if any(pattern in haystack for pattern in _PROGRESS_PATTERNS):
        intents.add("progress")
    if any(pattern in haystack for pattern in _COURSE_PATTERNS):
        intents.add("course")
    return intents


async def _cache_get(user_id: str) -> dict[str, Any] | None:
    try:
        from api.core.redis_client import RedisClient

        redis = await RedisClient.get_instance()
        raw = await redis.get(f"{_CACHE_PREFIX}{user_id}")
        return json.loads(raw) if raw else None
    except Exception as exc:
        logger.debug("learner_card cache read skipped: %s", exc)
        return None


async def _cache_set(user_id: str, card: dict[str, Any]) -> None:
    try:
        from api.core.redis_client import RedisClient

        redis = await RedisClient.get_instance()
        await redis.set(
            f"{_CACHE_PREFIX}{user_id}", json.dumps(card), ex=_CACHE_TTL_SECONDS
        )
    except Exception as exc:
        logger.debug("learner_card cache write skipped: %s", exc)


async def invalidate(user_id: str) -> None:
    try:
        from api.core.redis_client import RedisClient

        redis = await RedisClient.get_instance()
        await redis.delete(f"{_CACHE_PREFIX}{user_id}")
    except Exception as exc:
        logger.debug("learner_card invalidate skipped: %s", exc)


async def get_learner_card(user_id: str) -> dict[str, Any] | None:
    """Cached aggregate of this learner's own facts, or None if unavailable.

    Never raises: a chat turn must still answer when the backend is down, it
    just answers without the personal facts.
    """
    if not user_id or not settings.LEARNER_STATE_INTERNAL_TOKEN:
        return None

    cached = await _cache_get(user_id)
    if cached is not None:
        return cached

    # A miss is the interesting event — steady state should be mostly hits, so
    # a flood of these in production means the cache or the TTL is not working.
    logger.info("learner_card cache miss, fetching from backend")
    base_url = settings.LEARNER_STATE_API_URL.rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=_FETCH_TIMEOUT_SECONDS) as client:
            response = await client.get(
                f"{base_url}/learner-card/{user_id}",
                headers={
                    "X-LexiLingo-Service-Token": settings.LEARNER_STATE_INTERNAL_TOKEN,
                    "X-LexiLingo-Audience": settings.LEARNER_STATE_INTERNAL_AUDIENCE,
                },
            )
        if response.status_code >= 400:
            logger.warning("learner_card fetch http_%s", response.status_code)
            return None
        card = response.json()
    except Exception as exc:
        logger.warning("learner_card fetch failed (non-fatal): %s", exc)
        return None

    if not isinstance(card, dict):
        return None
    await _cache_set(user_id, card)
    return card


def render_card_facts(card: dict[str, Any], intents: set[str]) -> str:
    """Compact, grounded fact block for the system prompt.

    Only the slices the turn asked for — a course question does not need the
    learner's streak, and every extra line is prompt the tutor persona has to
    compete with.
    """
    if not card or not intents:
        return ""

    lines: list[str] = []

    if "identity" in intents or "progress" in intents:
        name = card.get("display_name")
        if name:
            lines.append(f"Name: {name}")
        if card.get("native_language"):
            lines.append(f"Native language: {card['native_language']}")
        if card.get("member_since"):
            lines.append(f"Joined: {card['member_since']}")
        if card.get("goal"):
            lines.append(f"Learning goal: {card['goal']}")
        if card.get("interest"):
            lines.append(f"Interest: {card['interest']}")

    if "progress" in intents:
        lines.append(
            f"CEFR level: {card.get('assessed_level') or card.get('cefr_level') or 'unknown'} "
            f"(overall score {card.get('overall_score', 0)}/100)"
        )
        lines.append(
            f"XP: {card.get('total_xp', 0)} · app level {card.get('numeric_level', 1)} · "
            f"rank {card.get('rank') or 'bronze'} · streak {card.get('streak_days', 0)} days"
        )
        lines.append(
            f"Completed: {card.get('lessons_completed', 0)} lessons, "
            f"{card.get('exercises_completed', 0)} exercises"
        )
        skills = card.get("skills") or {}
        scored = [
            (name, data)
            for name, data in skills.items()
            if isinstance(data, dict) and name in _SKILL_LABELS
        ]
        if scored:
            scored.sort(key=lambda item: item[1].get("score", 0))
            rendered = ", ".join(
                f"{_SKILL_LABELS[name]} {data.get('score', 0)}" for name, data in scored
            )
            lines.append(f"Skill scores (weakest first): {rendered}")

    if "course" in intents or "progress" in intents:
        enrolled = card.get("enrolled_courses") or []
        if enrolled:
            rendered = "; ".join(
                f"{item['title']} ({item.get('level', '?')}, {item.get('progress', 0)}% done)"
                for item in enrolled[:5]
            )
            lines.append(f"Enrolled courses: {rendered}")
        else:
            lines.append("Enrolled courses: none yet")

    if "course" in intents:
        suggested = card.get("suggested_courses") or []
        if suggested:
            rendered = "; ".join(
                f"{item['title']} ({item.get('level', '?')})" for item in suggested
            )
            lines.append(f"Courses matching their level: {rendered}")

    if not lines:
        return ""

    return (
        "--- Learner Facts (from the app database, authoritative) ---\n"
        + "\n".join(lines)
        + "\nUse these facts when the learner asks about themselves. State them "
        "plainly — never invent a fact that is not listed here, and if they ask "
        "for something not listed (such as their age), say the app does not "
        "have it rather than guessing.\n"
    )


def course_suggestions(card: dict[str, Any], intents: set[str]) -> list[dict[str, Any]]:
    """Real course rows to attach to the reply, so the UI renders cards the
    learner can tap instead of course names the model typed out."""
    if not card or "course" not in intents:
        return []
    suggested = card.get("suggested_courses") or []
    return [item for item in suggested if isinstance(item, dict) and item.get("course_id")]
