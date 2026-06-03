"""Round-robin Groq API key pool with per-key Redis rate limiting."""
from __future__ import annotations

import logging
import os
from typing import List, Optional, Tuple

import redis.asyncio as redis

from api.core.rate_limiter import RedisRateLimiter

logger = logging.getLogger(__name__)

_GROQ_FREE_RPM = 30
_GROQ_FREE_TPM = 12_000
_GROQ_FREE_RPD = 14_400


class GroqKeyPool:
    """
    Round-robin pool over multiple Groq API keys.
    Each key has its own RedisRateLimiter; requests are routed to the first
    available key (not rate-limited). The cursor advances after each pick so
    load is distributed evenly across keys.
    """

    def __init__(self, keys: List[str], redis_client: redis.Redis) -> None:
        if not keys:
            raise ValueError("GroqKeyPool requires at least one key")
        self._keys = keys
        self._limiters: List[RedisRateLimiter] = [
            RedisRateLimiter(
                redis_client=redis_client,
                prefix=f"groq:key{i}",
                rpm_limit=_GROQ_FREE_RPM,
                tpm_limit=_GROQ_FREE_TPM,
                rpd_limit=_GROQ_FREE_RPD,
            )
            for i in range(len(keys))
        ]
        self._cursor = 0

    async def get_available(
        self, estimated_tokens: int = 600
    ) -> Optional[Tuple[str, RedisRateLimiter]]:
        """Return (api_key, limiter) for the next available key, or None if all exhausted."""
        n = len(self._keys)
        start = self._cursor
        for i in range(n):
            idx = (start + i) % n
            limiter = self._limiters[idx]
            if await limiter.can_request(estimated_tokens):
                self._cursor = (idx + 1) % n
                return self._keys[idx], limiter
        logger.warning("GroqKeyPool: all %d keys are rate-limited", n)
        return None

    @property
    def count(self) -> int:
        return len(self._keys)


def build_groq_key_pool(redis_client: redis.Redis) -> Optional[GroqKeyPool]:
    """
    Build a GroqKeyPool from env vars.
    Reads GROQ_API_KEYS (comma-separated) first; falls back to GROQ_API_KEY.
    Returns None if no keys are configured.
    """
    raw = os.getenv("GROQ_API_KEYS", "").strip()
    keys = [k.strip() for k in raw.split(",") if k.strip()] if raw else []

    if not keys:
        single = os.getenv("GROQ_API_KEY", "").strip()
        if single:
            keys = [single]

    if not keys:
        return None

    logger.info("GroqKeyPool initialized with %d key(s)", len(keys))
    return GroqKeyPool(keys=keys, redis_client=redis_client)
