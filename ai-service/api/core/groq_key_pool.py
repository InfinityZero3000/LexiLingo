"""Round-robin Groq API key pool with per-key Redis rate limiting."""
from __future__ import annotations

import asyncio
import logging
import os
import time
import uuid
from typing import List, Optional, Tuple

import redis.asyncio as redis

from api.core.rate_limiter import RedisRateLimiter

logger = logging.getLogger(__name__)

_GROQ_FREE_RPM = 30
_GROQ_FREE_TPM = 6_000
_GROQ_FREE_RPD = 14_400
_VOICE_LEASE_MS = 45_000


def parse_groq_keys(raw: str, *, require_seven: bool = False) -> List[str]:
    """Parse configured keys without ever logging their values."""
    if not raw.strip():
        keys: List[str] = []
    else:
        parts = raw.split(",")
        if any(not part.strip() for part in parts):
            raise ValueError("GROQ_API_KEYS contains a blank entry")
        keys = [part.strip() for part in parts]
    if len(set(keys)) != len(keys):
        raise ValueError("GROQ_API_KEYS contains a duplicate entry")
    if require_seven and len(keys) != 7:
        raise ValueError("GROQ_API_KEYS must contain exactly seven unique keys")
    return keys


class GroqKeyLease(str):
    """String-compatible API key carrying its per-acquisition Redis token."""

    lease_token: str

    def __new__(cls, api_key: str, lease_token: str) -> "GroqKeyLease":
        value = super().__new__(cls, api_key)
        value.lease_token = lease_token
        return value


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
        self._acquire_lock = asyncio.Lock()

    @staticmethod
    def _log_slot(index: int) -> None:
        if os.getenv("GROQ_SLOT_TELEMETRY", "false").lower() == "true":
            logger.info("groq_slot_acquired slot_id=%d", index)

    async def try_acquire_voice(self, estimated_tokens: int = 600) -> Optional[str]:
        """Atomically reserve provider RPM and one in-flight voice lease."""
        now = time.time()
        for offset in range(len(self._keys)):
            idx = (self._cursor + offset) % len(self._keys)
            limiter = self._limiters[idx]
            if not await limiter.can_request(estimated_tokens):
                continue
            api_key = self._keys[idx]
            token = uuid.uuid4().hex
            script = """
            redis.call('ZREMRANGEBYSCORE', KEYS[2], 0, ARGV[1] - 60)
            if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
            if redis.call('ZCARD', KEYS[2]) >= tonumber(ARGV[3]) then return 0 end
            if not redis.call('SET', KEYS[1], ARGV[2], 'NX', 'PX', ARGV[4]) then return 0 end
            redis.call('ZADD', KEYS[2], ARGV[1], ARGV[2])
            redis.call('EXPIRE', KEYS[2], 65)
            return 1
            """
            try:
                admitted = await limiter.redis.eval(
                    script,
                    2,
                    f"{limiter.prefix}:voice:lease",
                    f"{limiter.prefix}:voice:rpm",
                    now,
                    token,
                    max(1, int(limiter.rpm_limit * limiter.safety)),
                    _VOICE_LEASE_MS,
                )
            except Exception as exc:
                logger.error("Groq voice admission failed closed: %s", exc)
                return None
            if admitted:
                self._cursor = (idx + 1) % len(self._keys)
                self._log_slot(idx)
                return GroqKeyLease(api_key, token)
        return None

    async def release_voice(self, api_key: str) -> None:
        """Release only the lease token issued to this process."""
        token = getattr(api_key, "lease_token", None)
        if not token:
            return
        try:
            idx = self._keys.index(api_key)
            limiter = self._limiters[idx]
            await limiter.redis.eval(
                "if redis.call('GET', KEYS[1]) == ARGV[1] then "
                "return redis.call('DEL', KEYS[1]) else return 0 end",
                1,
                f"{limiter.prefix}:voice:lease",
                token,
            )
        except Exception as exc:
            logger.error("Groq voice lease release failed: %s", exc)

    async def get_available(
        self, estimated_tokens: int = 600
    ) -> Optional[Tuple[str, RedisRateLimiter]]:
        """Return (api_key, limiter) for the next available key, or None if all exhausted."""
        # ponytail: process-local admission matches the one-worker deployment;
        # switch these callers to Redis leases before scaling AI replicas.
        async with self._acquire_lock:
            n = len(self._keys)
            start = self._cursor
            for i in range(n):
                idx = (start + i) % n
                limiter = self._limiters[idx]
                if await limiter.can_request(estimated_tokens):
                    self._cursor = (idx + 1) % n
                    self._log_slot(idx)
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
_fallback_keys: Optional[List[str]] = None
_fallback_cursor = 0
_fallback_in_flight: set[int] = set()
_fallback_next_at: List[float] = []
_fallback_lock = asyncio.Lock()


def get_groq_key_pool() -> Optional[GroqKeyPool]:
    """Retrieve the global GroqKeyPool instance."""
    return _pool_instance


def _get_fallback_keys() -> List[str]:
    """All configured Groq keys, used when the Redis-backed pool isn't built
    (e.g. standalone scripts that never call build_groq_key_pool)."""
    global _fallback_keys
    if _fallback_keys is None:
        raw = os.getenv("GROQ_API_KEYS", "").strip() or os.getenv("GROQ_API_KEY", "").strip()
        _fallback_keys = parse_groq_keys(raw)
    return _fallback_keys


def get_configured_key_count() -> int:
    """Number of usable Groq keys, whether or not the Redis pool is initialized."""
    pool = get_groq_key_pool()
    return pool.count if pool else len(_get_fallback_keys())


async def get_available_groq_key(estimated_tokens: int = 600) -> Optional[str]:
    """
    Get the next available Groq API key from the pool.
    Falls back to round-robin over all configured GROQ_API_KEYS when the
    Redis-backed pool isn't initialized — without this, callers like the
    standalone benchmark CLI always got the same single key back and burned
    through one account's daily quota while the rest of the pool sat idle.
    """
    global _fallback_cursor
    pool = get_groq_key_pool()
    if pool:
        slot = await pool.get_available(estimated_tokens)
        if slot:
            api_key, _ = slot
            return api_key
        return None

    keys = _get_fallback_keys()
    if not keys:
        return None
    key = keys[_fallback_cursor % len(keys)]
    _fallback_cursor += 1
    return key


async def try_acquire_groq_key(estimated_tokens: int = 600) -> Optional[str]:
    """Reserve one voice key without waiting; caller must release it."""
    global _fallback_cursor
    pool = get_groq_key_pool()
    if pool:
        return await pool.try_acquire_voice(estimated_tokens)

    keys = _get_fallback_keys()
    if not keys:
        return None
    try:
        rpm = max(1, int(os.getenv("GROQ_FALLBACK_RPM", str(_GROQ_FREE_RPM))))
    except ValueError:
        rpm = _GROQ_FREE_RPM

    async with _fallback_lock:
        if len(_fallback_next_at) != len(keys):
            _fallback_next_at[:] = [0.0] * len(keys)
        now = time.monotonic()
        for offset in range(len(keys)):
            index = (_fallback_cursor + offset) % len(keys)
            if index not in _fallback_in_flight and _fallback_next_at[index] <= now:
                _fallback_in_flight.add(index)
                _fallback_next_at[index] = now + 60.0 / rpm
                _fallback_cursor = (index + 1) % len(keys)
                return keys[index]
    return None


async def release_groq_key(api_key: str) -> None:
    if get_groq_key_pool():
        await get_groq_key_pool().release_voice(api_key)
        return
    keys = _get_fallback_keys()
    try:
        index = keys.index(api_key)
    except ValueError:
        return
    async with _fallback_lock:
        _fallback_in_flight.discard(index)


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
    require_seven = os.getenv("GROQ_REQUIRE_SEVEN_KEYS", "false").lower() == "true"
    keys = parse_groq_keys(raw, require_seven=require_seven)

    if not keys:
        return None

    logger.info("GroqKeyPool initialized with %d key(s)", len(keys))
    _pool_instance = GroqKeyPool(keys=keys, redis_client=redis_client)
    return _pool_instance
