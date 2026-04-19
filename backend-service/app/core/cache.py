"""
Redis Response Cache

Utility functions for caching API responses in Redis.
Falls back gracefully (no caching) when Redis is unavailable.
"""

import json
import hashlib
import logging
import os
import time
from typing import Any, Optional

from app.core.redis import RedisClient

logger = logging.getLogger(__name__)

# Fallback cache used when Redis is unavailable (tests/local dev).
_memory_cache: dict[str, tuple[float, Any]] = {}


def _memory_get(key: str) -> Optional[Any]:
    entry = _memory_cache.get(key)
    if not entry:
        return None
    expires_at, value = entry
    if expires_at <= time.time():
        _memory_cache.pop(key, None)
        return None
    return value


def _memory_set(key: str, value: Any, ttl: int) -> None:
    _memory_cache[key] = (time.time() + max(ttl, 1), value)


def _memory_delete(key: str) -> None:
    _memory_cache.pop(key, None)


def _cache_disabled() -> bool:
    """Disable cache in test runs to avoid cross-test state leakage."""
    if os.getenv("DISABLE_RESPONSE_CACHE") == "1":
        return True
    # Pytest sets this for each test item while executing.
    if os.getenv("PYTEST_CURRENT_TEST"):
        return True
    # Common test env convention.
    if os.getenv("APP_ENV", "").lower() == "test":
        return True
    return False

def _allow_cache_when_disabled(key: str) -> bool:
    """Allow select stateful keys in tests even when response-cache is disabled."""
    # Social location sharing relies on cache as source-of-truth for nearby users.
    return key.startswith("social_location:")

def compute_cache_version(value: Any) -> str:
    """Compute a stable cache-version hash for any JSON-serializable payload."""
    raw = json.dumps(value, sort_keys=True, default=str, separators=(",", ":"))
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def build_cache_key(prefix: str, **params) -> str:
    """Build a deterministic Redis key from prefix + keyword params."""
    safe = {k: str(v) for k, v in sorted(params.items()) if v is not None}
    raw = f"{prefix}:{json.dumps(safe, sort_keys=True)}"
    digest = hashlib.sha256(raw.encode()).hexdigest()[:16]
    return f"{prefix}:{digest}"


async def get_cached(key: str) -> Optional[Any]:
    """Get a cached value from Redis. Returns None on miss or error."""
    if _cache_disabled() and not _allow_cache_when_disabled(key):
        return None

    redis = await RedisClient.get_instance()
    if redis is None:
        return _memory_get(key)
    try:
        data = await redis.get(key)
        if data is not None:
            return json.loads(data)
    except Exception as exc:
        logger.debug(f"Cache read error: {exc}")
        return _memory_get(key)
    return _memory_get(key)


async def set_cached(key: str, value: Any, ttl: int = 60) -> None:
    """Store a value in Redis with TTL. Silently ignores errors."""
    if _cache_disabled() and not _allow_cache_when_disabled(key):
        return

    redis = await RedisClient.get_instance()
    if redis is None:
        _memory_set(key, value, ttl)
        return
    try:
        await redis.set(key, json.dumps(value, default=str), ex=ttl)
    except Exception as exc:
        logger.debug(f"Cache write error: {exc}")
        _memory_set(key, value, ttl)


async def delete_cached(key: str) -> None:
    """Delete a single cache entry by exact key. Silently ignores errors."""
    if _cache_disabled() and not _allow_cache_when_disabled(key):
        return

    redis = await RedisClient.get_instance()
    if redis is None:
        _memory_delete(key)
        return
    try:
        await redis.delete(key)
    except Exception as exc:
        logger.debug(f"Cache delete error: {exc}")
        _memory_delete(key)


async def invalidate_cache(prefix: str) -> int:
    """
    Delete all cache keys matching a prefix.
    Returns the number of keys deleted, or 0 if Redis is unavailable.
    """
    redis = await RedisClient.get_instance()
    if redis is None:
        keys = [k for k in _memory_cache.keys() if k.startswith(f"{prefix}:")]
        for key in keys:
            _memory_cache.pop(key, None)
        return len(keys)
    try:
        keys = []
        async for key in redis.scan_iter(match=f"{prefix}:*", count=200):
            keys.append(key)
        if keys:
            return await redis.delete(*keys)
        memory_keys = [k for k in _memory_cache.keys() if k.startswith(f"{prefix}:")]
        for key in memory_keys:
            _memory_cache.pop(key, None)
        return len(memory_keys)
    except Exception as exc:
        logger.debug(f"Cache invalidation error: {exc}")
        keys = [k for k in _memory_cache.keys() if k.startswith(f"{prefix}:")]
        for key in keys:
            _memory_cache.pop(key, None)
        return len(keys)
