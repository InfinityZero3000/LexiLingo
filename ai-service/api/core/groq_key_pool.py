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

    async def record_usage(self, api_key: str, tokens_used: int) -> None:
        """Record usage for a specific API key."""
        try:
            idx = self._keys.index(api_key)
            await self._limiters[idx].record(tokens_used)
        except ValueError:
            pass


_pool_instance: Optional[GroqKeyPool] = None


def get_groq_key_pool() -> Optional[GroqKeyPool]:
    """Retrieve the global GroqKeyPool instance."""
    return _pool_instance


async def get_available_groq_key(estimated_tokens: int = 600) -> Optional[str]:
    """
    Get the next available Groq API key from the pool.
    Falls back to the single GROQ_API_KEY environment variable if pool is empty/disabled.
    """
    pool = get_groq_key_pool()
    if pool:
        slot = await pool.get_available(estimated_tokens)
        if slot:
            api_key, _ = slot
            return api_key
    return os.getenv("GROQ_API_KEY", "").strip() or None


async def record_groq_key_usage(api_key: str, tokens_used: int) -> None:
    """Record token usage for a specific Groq key in the rate limiter pool."""
    pool = get_groq_key_pool()
    if pool:
        await pool.record_usage(api_key, tokens_used)


def build_groq_key_pool(redis_client: redis.Redis) -> Optional[GroqKeyPool]:
    """
    Build a GroqKeyPool from env vars.
    Reads GROQ_API_KEYS (comma-separated) first; falls back to GROQ_API_KEY.
    Returns None if no keys are configured.
    """
    global _pool_instance
    raw = os.getenv("GROQ_API_KEYS", "").strip() or os.getenv("GROQ_API_KEY", "").strip()
    keys = [k.strip() for k in raw.split(",") if k.strip()] if raw else []

    if not keys:
        return None

    logger.info("GroqKeyPool initialized with %d key(s)", len(keys))
    _pool_instance = GroqKeyPool(keys=keys, redis_client=redis_client)
    return _pool_instance
