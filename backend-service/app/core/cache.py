"""
Redis Response Cache

Utility functions for caching API responses in Redis.
Falls back gracefully (no caching) when Redis is unavailable.
"""

import json
import hashlib
import logging
import os
from typing import Any, Optional

from app.core.redis import RedisClient

logger = logging.getLogger(__name__)


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
    if _cache_disabled():
        return None

    redis = await RedisClient.get_instance()
    if redis is None:
        return None
    try:
        data = await redis.get(key)
        if data is not None:
            return json.loads(data)
    except Exception as exc:
        logger.debug(f"Cache read error: {exc}")
    return None


async def set_cached(key: str, value: Any, ttl: int = 60) -> None:
    """Store a value in Redis with TTL. Silently ignores errors."""
    if _cache_disabled():
        return

    redis = await RedisClient.get_instance()
    if redis is None:
        return
    try:
        await redis.set(key, json.dumps(value, default=str), ex=ttl)
    except Exception as exc:
        logger.debug(f"Cache write error: {exc}")


async def delete_cached(key: str) -> None:
    """Delete a single cache entry by exact key. Silently ignores errors."""
    if _cache_disabled():
        return

    redis = await RedisClient.get_instance()
    if redis is None:
        return
    try:
        await redis.delete(key)
    except Exception as exc:
        logger.debug(f"Cache delete error: {exc}")


async def invalidate_cache(prefix: str) -> int:
    """
    Delete all cache keys matching a prefix.
    Returns the number of keys deleted, or 0 if Redis is unavailable.
    """
    redis = await RedisClient.get_instance()
    if redis is None:
        return 0
    try:
        keys = []
        async for key in redis.scan_iter(match=f"{prefix}:*", count=200):
            keys.append(key)
        if keys:
            return await redis.delete(*keys)
        return 0
    except Exception as exc:
        logger.debug(f"Cache invalidation error: {exc}")
        return 0
