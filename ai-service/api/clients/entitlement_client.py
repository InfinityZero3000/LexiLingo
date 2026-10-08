"""Checks whether a user has an active premium entitlement.

Unlike LearnerStateClient this sits outside the TRACE-CAG hot path — it is
called once per chat message, not per reasoning step — so it skips the
circuit-breaker/bulkhead machinery and just fails open (treat as free tier)
on any error. A missed premium check costs one user a free-tier chat cap for
a moment; it must never block or fail a chat request. It does reuse one
pooled client rather than opening a new connection per call, since this runs
on every chat turn.
"""

from __future__ import annotations

import logging

import httpx

from api.core.config import settings

logger = logging.getLogger(__name__)

_TIMEOUT_SECONDS = 1.5

_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=_TIMEOUT_SECONDS)
    return _client


async def close_entitlement_client() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


async def is_premium(user_id: str, *, entitlement_id: str = "premium") -> bool:
    if not settings.LEARNER_STATE_INTERNAL_TOKEN:
        return False
    try:
        response = await _get_client().get(
            f"{settings.LEARNER_STATE_API_URL}/entitlements/{user_id}",
            params={"entitlement_id": entitlement_id},
            headers={
                "X-LexiLingo-Service-Token": settings.LEARNER_STATE_INTERNAL_TOKEN,
                "X-LexiLingo-Audience": settings.LEARNER_STATE_INTERNAL_AUDIENCE,
            },
        )
        if response.status_code != 200:
            return False
        return bool(response.json().get("active"))
    except (httpx.HTTPError, ValueError):
        logger.warning("Entitlement check failed for user=%s; treating as free tier", user_id)
        return False
