"""Groq-powered insights for Ranking Agent job previews."""

from __future__ import annotations

import logging
import os
from typing import Any, Optional

import httpx

logger = logging.getLogger(__name__)

_GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
_ESTIMATED_TOKENS = 480

_VALID_JOB_TYPES = frozenset({"league_reset", "xp_event", "achievement_batch"})

# Hard limits to prevent huge prompts or oversized API payloads
_MAX_LEAGUES_IN_PROMPT = 5   # max league entries in summary
_MAX_SLUGS_IN_PROMPT = 5     # max achievement slugs
_MAX_FIELD_STR_LEN = 120     # max chars for any single string field


def _trunc(value: object, max_len: int = _MAX_FIELD_STR_LEN) -> str:
    s = str(value)
    return s if len(s) <= max_len else s[:max_len] + "…"


def _build_prompt(job_type: str, artifact: dict[str, Any]) -> str:
    if job_type == "league_reset":
        promotions = len(artifact.get("promotions", []))
        demotions = len(artifact.get("demotions", []))
        total = artifact.get("total_participants", 0)
        week = _trunc(artifact.get("week", "unknown week"))
        summary = artifact.get("league_summary", {})
        top_leagues = ", ".join(
            f"{lg}: {v.get('promoted', 0)} promoted"
            for lg, v in list(summary.items())[:_MAX_LEAGUES_IN_PROMPT]
            if v.get("promoted", 0) > 0
        ) or "none promoted yet"
        return (
            f"/no_think\n"
            f"You are a gamification analyst for LexiLingo, a language learning app.\n"
            f"A weekly league reset preview shows: week={week}, total_participants={total}, "
            f"promotions={promotions}, demotions={demotions}. Top leagues: {top_leagues}.\n"
            f"Write a 2-sentence admin insight: highlight what the numbers mean for learner engagement "
            f"and suggest one action the admin could take based on this data. Be concise and factual."
        )

    if job_type == "xp_event":
        count = artifact.get("target_user_count", 0)
        multiplier = artifact.get("multiplier", 1.0)
        hours = artifact.get("duration_hours", 0)
        delta = _trunc(artifact.get("estimated_total_xp_delta", ""))
        return (
            f"/no_think\n"
            f"You are a gamification analyst for LexiLingo.\n"
            f"An XP boost event preview: {count} users targeted, {multiplier}× multiplier for {hours}h, "
            f"estimated XP delta={delta}.\n"
            f"Write a 2-sentence admin insight: assess the expected engagement impact and flag any risk "
            f"(e.g. event too short, too few users). Be concise."
        )

    if job_type == "achievement_batch":
        total_affected = artifact.get("total_users_affected", 0)
        total_xp = artifact.get("total_xp_to_award", 0)
        achievements = artifact.get("achievements", [])
        slugs = ", ".join(
            _trunc(a.get("slug", ""), 40)
            for a in achievements[:_MAX_SLUGS_IN_PROMPT]
        )
        return (
            f"/no_think\n"
            f"You are a gamification analyst for LexiLingo.\n"
            f"An achievement batch preview: {total_affected} users will receive achievements "
            f"({slugs}), total XP to award={total_xp}.\n"
            f"Write a 2-sentence admin insight: comment on whether the batch size looks healthy "
            f"and what retention effect this might have. Be concise."
        )

    # Should never reach here because job_type is validated before calling
    raise ValueError(f"Unknown job_type: {job_type!r}")


async def get_ranking_insights(
    job_type: str,
    artifact: dict[str, Any],
    groq_pool,
) -> Optional[str]:
    """
    Generate a short Groq-powered insight for a ranking agent preview.
    Returns None gracefully if the key pool is exhausted or Groq is unavailable.
    """
    if job_type not in _VALID_JOB_TYPES:
        logger.warning("ranking_agent_insights: unknown job_type=%r, skipping", job_type)
        return None

    if groq_pool is None:
        return None

    slot = await groq_pool.get_available(estimated_tokens=_ESTIMATED_TOKENS)
    if slot is None:
        logger.warning("ranking_agent_insights: all Groq keys rate-limited, skipping AI insights")
        return None

    api_key, limiter = slot
    model = os.getenv("GROQ_MODEL", "openai/gpt-oss-20b")

    try:
        prompt = _build_prompt(job_type, artifact)
    except ValueError:
        return None

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                _GROQ_URL,
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": model,
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 200,
                    "temperature": 0.3,
                },
            )
        if response.status_code != 200:
            logger.warning(
                "ranking_agent_insights: Groq returned %d", response.status_code
            )
            return None

        data = response.json()
        content = data["choices"][0]["message"]["content"].strip()
        tokens_used = data.get("usage", {}).get("total_tokens", _ESTIMATED_TOKENS)
        await limiter.record(tokens_used)
        return content

    except Exception:
        logger.exception("ranking_agent_insights: Groq call failed")
        return None
