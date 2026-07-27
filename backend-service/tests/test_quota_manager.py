from datetime import date

import pytest

from app.services import quota_manager
from app.services.quota_manager import QuotaManager, QuotaStatus


def test_quota_key_uses_utc_date(monkeypatch):
    monkeypatch.setattr(
        quota_manager,
        "_utc_today",
        lambda: date(2026, 6, 26),
    )

    assert QuotaManager._redis_key("newsapi") == "quota:newsapi:2026-06-26"


def test_reset_time_returns_human_readable_duration():
    reset_time = QuotaManager.get_reset_time()

    assert "h" in reset_time
    assert "m" in reset_time


@pytest.mark.asyncio
async def test_unknown_api_usage_is_not_recorded(monkeypatch):
    class FakeRedis:
        def __init__(self):
            self.incrby_calls = []

        async def incrby(self, key, cost):
            self.incrby_calls.append((key, cost))
            return cost

        async def expire(self, key, ttl):
            return True

    redis = FakeRedis()

    async def fake_get_instance():
        return redis

    monkeypatch.setattr(
        quota_manager.RedisClient,
        "get_instance",
        fake_get_instance,
    )

    status = await QuotaManager.record_request("unknown-api")

    assert status == QuotaStatus.NORMAL
    assert redis.incrby_calls == []


@pytest.mark.asyncio
async def test_zero_cost_usage_is_not_recorded(monkeypatch):
    class FakeRedis:
        def __init__(self):
            self.incrby_calls = []

        async def get(self, key):
            return 0

        async def incrby(self, key, cost):
            self.incrby_calls.append((key, cost))
            return cost

    redis = FakeRedis()

    async def fake_get_instance():
        return redis

    monkeypatch.setattr(
        quota_manager.RedisClient,
        "get_instance",
        fake_get_instance,
    )

    status = await QuotaManager.record_request("youtube", cost=0)

    assert status == QuotaStatus.NORMAL
    assert redis.incrby_calls == []


@pytest.mark.asyncio
async def test_negative_quota_cost_is_rejected():
    with pytest.raises(ValueError, match="non-negative"):
        await QuotaManager.record_request("youtube", cost=-1)
