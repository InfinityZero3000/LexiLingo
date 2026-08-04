from __future__ import annotations

import json

import pytest

from api.services.trace_cag.external_request_cache import ExternalRequestCache


class FakeRedis:
    """Minimal in-memory stand-in for redis.asyncio.Redis — just get/set with TTL."""

    def __init__(self) -> None:
        self.store: dict[str, str] = {}
        self.last_ex: int | None = None

    async def get(self, key: str) -> str | None:
        return self.store.get(key)

    async def set(self, key: str, value: str, ex: int | None = None) -> None:
        self.store[key] = value
        self.last_ex = ex


@pytest.fixture
def fake_redis(monkeypatch):
    from api.core.redis_client import RedisClient
    from unittest.mock import AsyncMock

    redis = FakeRedis()
    monkeypatch.setattr(RedisClient, "get_instance", AsyncMock(return_value=redis))
    return redis


@pytest.mark.asyncio
async def test_miss_then_hit(fake_redis):
    cache = ExternalRequestCache(ttl_seconds=600)
    state, cached = await cache.get("req-1", "fp-1")
    assert (state, cached) == ("miss", None)

    await cache.put("req-1", "fp-1", {"answer": "ok"})
    state, cached = await cache.get("req-1", "fp-1")
    assert state == "hit"
    assert cached == {"answer": "ok"}


@pytest.mark.asyncio
async def test_conflict_on_fingerprint_mismatch(fake_redis):
    cache = ExternalRequestCache(ttl_seconds=600)
    await cache.put("req-1", "fp-1", {"answer": "ok"})
    state, cached = await cache.get("req-1", "fp-DIFFERENT")
    assert (state, cached) == ("conflict", None)


@pytest.mark.asyncio
async def test_put_sets_redis_ttl(fake_redis):
    cache = ExternalRequestCache(ttl_seconds=42)
    await cache.put("req-1", "fp-1", {"answer": "ok"})
    assert fake_redis.last_ex == 42
    assert json.loads(fake_redis.store["external_request:req-1"])["fingerprint"] == "fp-1"


@pytest.mark.asyncio
async def test_expired_entry_is_a_miss(fake_redis):
    """Redis EX handles real expiry; simulate it having already evicted the key."""
    cache = ExternalRequestCache(ttl_seconds=1)
    await cache.put("req-1", "fp-1", {"answer": "ok"})
    fake_redis.store.pop("external_request:req-1")
    state, cached = await cache.get("req-1", "fp-1")
    assert (state, cached) == ("miss", None)
