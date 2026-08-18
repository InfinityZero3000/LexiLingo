"""LangGraph node functions for the Notification Agent pipeline."""

from __future__ import annotations

import json
import logging
import os
import re
from typing import Any

import httpx

from api.services.notification_agent.state import NotificationAgentState, NotificationVariant

logger = logging.getLogger(__name__)

_GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
_MAX_RETRIES = 2
_QUALITY_THRESHOLD = 0.70


def analyze_audience_node(state: NotificationAgentState) -> dict:
    """Build a natural-language audience profile summary from structured filters."""
    profile = state["audience_profile"]
    parts: list[str] = []

    size = profile.get("size", 0)
    parts.append(f"{size} users")

    if cefr := profile.get("cefr_levels"):
        parts.append(f"CEFR levels {', '.join(cefr)}")

    if leagues := profile.get("leagues"):
        parts.append(f"leagues: {', '.join(leagues)}")

    if inactive := profile.get("inactive_days"):
        parts.append(f"inactive for {inactive}+ days")

    summary = "; ".join(parts) if parts else "all active users"
    return {"audience_summary": summary}


async def generate_variants_node(state: NotificationAgentState) -> dict:
    """Call Groq to generate 3 notification copy variants."""
    groq_key = await _get_groq_key()
    if not groq_key:
        logger.warning("No Groq API key available — skipping AI copy generation")
        return {
            "variants": [],
            "generation_skipped": True,
            "retries": state.get("retries", 0),
        }

    model = os.getenv("GROQ_MODEL", "openai/gpt-oss-20b")
    audience = state["audience_summary"]
    orig_title = state["original_title"]
    orig_body = state["original_body"]
    notif_type = state.get("notification_type", "campaign")

    prompt = (
        f"/no_think\n"
        f"You are a mobile push notification copywriter for LexiLingo, a language learning app.\n\n"
        f"Target audience: {audience}\n"
        f"Notification type: {notif_type}\n"
        f"Original title: {orig_title}\n"
        f"Original body: {orig_body}\n\n"
        f"Generate exactly 3 notification variants. Each must have:\n"
        f"- title: max 50 chars, attention-grabbing\n"
        f"- body: max 120 chars, clear CTA or benefit\n"
        f"- rationale: 1 sentence explaining the approach\n\n"
        f"Respond ONLY with valid JSON array:\n"
        f'[{{"title":"...","body":"...","rationale":"..."}}, ...]'
    )

    try:
        async with httpx.AsyncClient(timeout=25.0) as client:
            resp = await client.post(
                _GROQ_URL,
                headers={"Authorization": f"Bearer {groq_key}"},
                json={
                    "model": model,
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 600,
                    "temperature": 0.7,
                },
            )
        if resp.status_code != 200:
            logger.warning("Groq returned %d for notification copy generation", resp.status_code)
            return {"variants": [], "generation_skipped": True, "retries": state.get("retries", 0)}

        payload = resp.json()
        from api.core.groq_key_pool import record_groq_key_usage

        await record_groq_key_usage(
            groq_key, payload.get("usage", {}).get("total_tokens", 600)
        )

        content = payload["choices"][0]["message"]["content"].strip()
        # Strip markdown code fences if present (handles ```json ... ``` or ``` ... ```)
        content = re.sub(r"^```[a-zA-Z]*\s*", "", content)
        content = re.sub(r"\s*```$", "", content).strip()
        variants = json.loads(content)
        if not isinstance(variants, list):
            raise ValueError("Expected JSON array")

        parsed: list[NotificationVariant] = []
        for v in variants[:3]:
            parsed.append(
                NotificationVariant(
                    title=str(v.get("title", ""))[:50],
                    body=str(v.get("body", ""))[:120],
                    rationale=str(v.get("rationale", "")),
                )
            )
        return {
            "variants": parsed,
            "generation_skipped": False,
            "retries": state.get("retries", 0),
        }

    except Exception as exc:
        logger.exception("Groq notification copy generation failed: %s", exc)
        return {"variants": [], "generation_skipped": True, "retries": state.get("retries", 0)}


def evaluate_variants_node(state: NotificationAgentState) -> dict:
    """Score variants and pick the best. Returns generation_skipped=True if no variants."""
    variants = state.get("variants", [])
    if not variants:
        return {
            "best_variant": None,
            "best_score": 0.0,
            "retries": state.get("retries", 0) + 1,
            "generation_skipped": state.get("generation_skipped", False),
        }

    best: NotificationVariant | None = None
    best_score = 0.0

    for v in variants:
        score = _score_variant(v, state)
        if score > best_score:
            best_score = score
            best = v

    return {
        "best_variant": best,
        "best_score": best_score,
        "retries": state.get("retries", 0) + 1,
    }


def finalize_node(state: NotificationAgentState) -> dict:
    """Set final_title/body from best variant or fall back to original."""
    best = state.get("best_variant")
    if best and state.get("best_score", 0.0) >= _QUALITY_THRESHOLD:
        return {"final_title": best["title"], "final_body": best["body"]}
    return {
        "final_title": state["original_title"],
        "final_body": state["original_body"],
    }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _score_variant(variant: NotificationVariant, state: NotificationAgentState) -> float:
    title = variant.get("title", "")
    body = variant.get("body", "")

    score = 0.0

    # Length checks (ideal ranges)
    if 10 <= len(title) <= 50:
        score += 0.3
    elif len(title) > 0:
        score += 0.1

    if 20 <= len(body) <= 120:
        score += 0.3
    elif len(body) > 0:
        score += 0.1

    # Has rationale
    if variant.get("rationale"):
        score += 0.1

    # Not identical to original
    if title != state["original_title"]:
        score += 0.15
    if body != state["original_body"]:
        score += 0.15

    return min(score, 1.0)


async def _get_groq_key() -> str | None:
    """Next key from the shared rotating pool.

    This used to read GROQ_API_KEY_1..9 — a naming scheme configured nowhere —
    and then fall back to the single GROQ_API_KEY, so every notification job
    hammered one key while the other six sat idle.
    """
    from api.core.groq_key_pool import get_available_groq_key

    return await get_available_groq_key(estimated_tokens=600)


def should_regenerate(state: NotificationAgentState) -> str:
    """Conditional edge: regenerate if quality below threshold and retries remain."""
    if state.get("generation_skipped"):
        return "finalize"
    score = state.get("best_score", 0.0)
    retries = state.get("retries", 0)
    if score < _QUALITY_THRESHOLD and retries < _MAX_RETRIES:
        return "generate_variants"
    return "finalize"
