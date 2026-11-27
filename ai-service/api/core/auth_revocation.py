"""Revocation signals published by backend-service, read by ai-service auth.

Both live in the backend's Redis DB (not ai-service's own DB), so this module
keeps its own short-timeout client instead of the retrying RedisClient.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Optional

import redis.asyncio as redis

from api.core.config import settings

logger = logging.getLogger(__name__)

BLACKLIST_PREFIX = "blacklist:token:"
INACTIVE_PREFIX = "user:inactive:"
SESSIONS_CUT_PREFIX = "user:sessions-cut:"
FAILURE_COUNTER = "auth_revocation_check_failed_total"
_LOG_EVERY_SECONDS = 30.0

_client: Optional[redis.Redis] = None
_last_failure_log = 0.0


def blacklist_key(token: str) -> str:
    # Must match backend-service app/core/token_blacklist.py::_get_key.
    return f"{BLACKLIST_PREFIX}{token[-32:] if len(token) > 32 else token}"


def inactive_key(user_id: str) -> str:
    return f"{INACTIVE_PREFIX}{user_id}"


def sessions_cut_key(user_id: str) -> str:
    # Must match backend-service app/core/token_blacklist.py::SessionCut.
    return f"{SESSIONS_CUT_PREFIX}{user_id}"


def _issued_before(issued_at: Optional[int], cut: Optional[str]) -> bool:
    if not cut:
        return False
    try:
        return issued_at is None or int(issued_at) < int(cut)
    except (TypeError, ValueError):
        return True


def _enabled() -> bool:
    return os.getenv("AUTH_REVOCATION_CHECK", "on").strip().lower() not in {"0", "off", "false", "no"}


def _timeout() -> float:
    try:
        return max(0.05, float(os.getenv("AUTH_REVOCATION_TIMEOUT_SECONDS", "0.3")))
    except ValueError:
        return 0.3


def _get_client() -> redis.Redis:
    global _client
    if _client is None:
        db = int(os.getenv("AUTH_REVOCATION_REDIS_DB", "0"))
        _client = redis.Redis(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            password=settings.REDIS_PASSWORD or None,
            db=db,
            decode_responses=True,
            socket_timeout=_timeout(),
            socket_connect_timeout=_timeout(),
        )
    return _client


def _record_failure(exc: Exception) -> None:
    global _last_failure_log
    try:
        from api.services.telemetry import get_telemetry

        get_telemetry().increment_counter(FAILURE_COUNTER)
    except Exception as telemetry_exc:
        logger.debug("[auth_revocation] telemetry unavailable: %s", telemetry_exc)
    now = time.monotonic()
    if now - _last_failure_log >= _LOG_EVERY_SECONDS:
        _last_failure_log = now
        logger.warning(
            "Revocation check unavailable, allowing request (fail open): %s: %s",
            type(exc).__name__,
            exc,
        )


async def revocation_reason(token: str, user_id: str, issued_at: Optional[int] = None) -> Optional[str]:
    """Return "revoked" or "inactive" when the token must be refused, else None.

    Fails open: Redis trouble must not take chat down with it.
    """
    if not _enabled():
        return None
    try:
        pipe = _get_client().pipeline(transaction=False)
        pipe.exists(blacklist_key(token))
        pipe.exists(inactive_key(user_id))
        pipe.get(sessions_cut_key(user_id))
        revoked, inactive, cut = await pipe.execute()
    except Exception as exc:
        _record_failure(exc)
        return None
    if revoked or _issued_before(issued_at, cut):
        return "revoked"
    if inactive:
        return "inactive"
    return None


async def close() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None
