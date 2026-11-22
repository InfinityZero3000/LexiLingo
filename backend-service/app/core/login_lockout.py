"""Per-account lockout after repeated failed logins; Redis, with a per-process fallback."""

from __future__ import annotations

import hashlib
import logging
import time

from fastapi import HTTPException, status

from app.core.redis import RedisClient

logger = logging.getLogger(__name__)

MAX_FAILURES = 10
FAILURE_WINDOW_SECONDS = 15 * 60
LOCK_SECONDS = 15 * 60

_FAIL_PREFIX = "login:fail:"
_LOCK_PREFIX = "login:lock:"

_memory_failures: dict[str, tuple[int, float]] = {}
_memory_locks: dict[str, float] = {}

# Atomically count a failure and lock on the threshold; returns the lock's remaining seconds or 0.
_RECORD_FAILURE = """
local count = redis.call("INCR", KEYS[1])
if count == 1 then redis.call("EXPIRE", KEYS[1], ARGV[1]) end
if count >= tonumber(ARGV[2]) then
    redis.call("SET", KEYS[2], "1", "EX", ARGV[3])
    redis.call("DEL", KEYS[1])
    return tonumber(ARGV[3])
end
return 0
"""


def account_key(email: str) -> str:
    """Hash of the normalised email: what Redis keys and logs carry instead of the address."""
    return hashlib.sha256(email.strip().lower().encode("utf-8")).hexdigest()


async def _redis():
    try:
        return await RedisClient.get_instance()
    except Exception:
        return None


async def locked_for(email: str) -> int:
    """Seconds left on the account's lock, 0 when it is not locked."""
    key = account_key(email)
    redis = await _redis()
    if redis is not None:
        try:
            ttl = int(await redis.ttl(f"{_LOCK_PREFIX}{key}"))
            return ttl if ttl > 0 else 0
        except Exception:
            logger.warning("Login lockout check failed in Redis; using memory", exc_info=True)
    remaining = _memory_locks.get(key, 0) - time.time()
    if remaining <= 0:
        _memory_locks.pop(key, None)
        return 0
    return max(1, int(remaining + 0.999))


async def record_failure(email: str) -> int:
    """Count a failed login; returns the lock duration when this failure locked the account."""
    key = account_key(email)
    locked = 0
    redis = await _redis()
    used_redis = False
    if redis is not None:
        try:
            locked = int(
                await redis.eval(
                    _RECORD_FAILURE, 2, f"{_FAIL_PREFIX}{key}", f"{_LOCK_PREFIX}{key}",
                    FAILURE_WINDOW_SECONDS, MAX_FAILURES, LOCK_SECONDS,
                )
            )
            used_redis = True
        except Exception:
            logger.warning("Login failure count failed in Redis; using memory", exc_info=True)
    if not used_redis:
        now = time.time()
        count, expires_at = _memory_failures.get(key, (0, 0.0))
        if expires_at <= now:
            count, expires_at = 0, now + FAILURE_WINDOW_SECONDS
        count += 1
        if count >= MAX_FAILURES:
            _memory_locks[key] = now + LOCK_SECONDS
            _memory_failures.pop(key, None)
            locked = LOCK_SECONDS
        else:
            _memory_failures[key] = (count, expires_at)
    if locked:
        logger.warning("Login lockout: account %s locked for %ss", key[:16], locked)
    return locked


async def reset(email: str) -> None:
    key = account_key(email)
    _memory_failures.pop(key, None)
    redis = await _redis()
    if redis is not None:
        try:
            await redis.delete(f"{_FAIL_PREFIX}{key}")
        except Exception:
            logger.warning("Login failure reset failed in Redis", exc_info=True)


def locked_response(retry_after: int) -> HTTPException:
    """Identical for known and unknown emails, so a lock reveals nothing about the account."""
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Too many failed login attempts. Please try again later.",
        headers={"Retry-After": str(max(1, retry_after))},
    )


async def ensure_not_locked(email: str) -> None:
    remaining = await locked_for(email)
    if remaining:
        raise locked_response(remaining)
