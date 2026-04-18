import pytest
from fastapi import HTTPException

from api.core import quota_guard


class _FakePipeline:
    def __init__(self, redis_client):
        self.redis_client = redis_client
        self.ops = []

    def incr(self, key):
        self.ops.append(("incr", key))
        return self

    def incrby(self, key, amount):
        self.ops.append(("incrby", key, int(amount)))
        return self

    def expire(self, key, _ttl):
        self.ops.append(("expire", key))
        return self

    async def execute(self):
        out = []
        for entry in self.ops:
            op = entry[0]
            key = entry[1]
            if op == "incr":
                self.redis_client.counters[key] = self.redis_client.counters.get(key, 0) + 1
                out.append(self.redis_client.counters[key])
            elif op == "incrby":
                amount = entry[2]
                self.redis_client.counters[key] = self.redis_client.counters.get(key, 0) + amount
                out.append(self.redis_client.counters[key])
            else:
                out.append(True)
        self.ops.clear()
        return out


class _FakeRedis:
    def __init__(self):
        self.counters = {}

    def pipeline(self):
        return _FakePipeline(self)


@pytest.mark.asyncio
async def test_enforce_user_quota_allows_under_limit(monkeypatch):
    fake_redis = _FakeRedis()

    async def _fake_get_redis():
        return fake_redis

    monkeypatch.setattr(quota_guard, "get_redis", _fake_get_redis)

    guard = quota_guard.UserQuotaGuard()
    guard.rpm_limit = 5
    guard.rpd_limit = 10
    monkeypatch.setattr(quota_guard, "_guard", guard)

    decision = await quota_guard.enforce_user_quota("u1", "lexi.chat")

    assert decision.allowed is True
    assert decision.rpm_used == 1
    assert decision.rpd_used == 1
    assert decision.tpm_used == 0
    assert decision.tpd_used == 0


@pytest.mark.asyncio
async def test_enforce_user_quota_blocks_over_limit(monkeypatch):
    fake_redis = _FakeRedis()

    async def _fake_get_redis():
        return fake_redis

    monkeypatch.setattr(quota_guard, "get_redis", _fake_get_redis)

    guard = quota_guard.UserQuotaGuard()
    guard.rpm_limit = 1
    guard.rpd_limit = 100
    monkeypatch.setattr(quota_guard, "_guard", guard)

    await quota_guard.enforce_user_quota("u2", "stt.transcribe")

    with pytest.raises(HTTPException) as exc:
        await quota_guard.enforce_user_quota("u2", "stt.transcribe")

    assert exc.value.status_code == 429


@pytest.mark.asyncio
async def test_enforce_user_quota_blocks_over_token_limit(monkeypatch):
    fake_redis = _FakeRedis()

    async def _fake_get_redis():
        return fake_redis

    monkeypatch.setattr(quota_guard, "get_redis", _fake_get_redis)

    guard = quota_guard.UserQuotaGuard()
    guard.rpm_limit = 100
    guard.rpd_limit = 1000
    guard.tpm_limit = 100
    guard.tpd_limit = 1000
    monkeypatch.setattr(quota_guard, "_guard", guard)

    await quota_guard.enforce_user_quota("u3", "lexi.chat", token_cost=80)

    with pytest.raises(HTTPException) as exc:
        await quota_guard.enforce_user_quota("u3", "lexi.chat", token_cost=30)

    assert exc.value.status_code == 429


@pytest.mark.asyncio
async def test_enforce_user_quota_fail_closed_when_redis_unavailable(monkeypatch):
    async def _fake_get_redis():
        return None

    monkeypatch.setattr(quota_guard, "get_redis", _fake_get_redis)

    guard = quota_guard.UserQuotaGuard()
    monkeypatch.setattr(quota_guard, "_guard", guard)

    with pytest.raises(HTTPException) as exc:
        await quota_guard.enforce_user_quota("u4", "lexi.chat", fail_closed=True)

    assert exc.value.status_code == 503
