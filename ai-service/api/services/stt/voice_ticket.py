"""Single-use WebSocket tickets; Redis in production, memory in development."""

from __future__ import annotations

import asyncio
import hashlib
import secrets
import time

from api.core.config import settings
from api.core.redis_client import get_redis

_TTL_SECONDS = 30
_local: dict[str, tuple[str, float]] = {}
_lock = asyncio.Lock()


def _key(ticket: str) -> str:
    return f"voice:ticket:{hashlib.sha256(ticket.encode()).hexdigest()}"


async def issue_voice_ticket(user_id: str) -> tuple[str, int]:
    ticket = secrets.token_urlsafe(32)
    key = _key(ticket)
    try:
        redis = await get_redis()
        if not await redis.set(key, user_id, ex=_TTL_SECONDS, nx=True):
            raise RuntimeError("ticket collision")
    except Exception:
        if settings.ENVIRONMENT == "production":
            raise
        async with _lock:
            _local[key] = (user_id, time.monotonic() + _TTL_SECONDS)
    return ticket, _TTL_SECONDS


async def consume_voice_ticket(ticket: str) -> str | None:
    if not ticket:
        return None
    key = _key(ticket)
    try:
        redis = await get_redis()
        value = await redis.getdel(key)
        return str(value) if value else None
    except Exception:
        if settings.ENVIRONMENT == "production":
            return None
        async with _lock:
            value = _local.pop(key, None)
        if not value or value[1] < time.monotonic():
            return None
        return value[0]
