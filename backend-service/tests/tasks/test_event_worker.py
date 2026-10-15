"""Event Worker: drains the content_interaction Redis Stream and recomputes
each affected user's insights. Uses a minimal in-memory fake of the Redis
Streams commands this module actually calls (xadd/xgroup_create/xreadgroup/
xack) rather than a real Redis — there is no Redis connected in this test
environment (see RedisClient in conftest/test_quota_manager for the same
pattern with plain get/set commands)."""

import json
from unittest.mock import AsyncMock

import pytest

from app.tasks import event_worker as worker_module

pytestmark = pytest.mark.asyncio


class _SessionContext:
    def __init__(self, session):
        self.session = session

    async def __aenter__(self):
        return self.session

    async def __aexit__(self, *_args):
        return None


class FakeStreamRedis:
    """Just enough of redis.asyncio's Streams API to exercise _drain().

    Models the consumer-group semantics the worker actually depends on: a
    message read with ">" moves into the pending list (PEL) and is only
    removed by an ack, and XREADGROUP ">" never returns it again. That
    distinction is the whole reason _reclaim_stale exists, so the fake has
    to honour it rather than re-serving unacked messages.
    """

    def __init__(self):
        self._next_id = 1
        self.messages: dict[str, dict] = {}
        self.delivered: dict[str, float] = {}  # message_id -> idle seconds
        self.acked: list[str] = []
        self.groups: set[str] = set()
        self.insights: dict[str, str] = {}

    async def xadd(self, key, fields, **_kwargs):
        message_id = f"{self._next_id}-0"
        self._next_id += 1
        self.messages[message_id] = dict(fields)
        return message_id

    async def xgroup_create(self, _key, group, id="0", mkstream=False):  # noqa: A002
        if group in self.groups:
            raise Exception("BUSYGROUP Consumer Group name already exists")
        self.groups.add(group)

    async def xreadgroup(self, _group, _consumer, _streams, count=None):
        fresh = [
            (mid, fields)
            for mid, fields in self.messages.items()
            if mid not in self.delivered and mid not in self.acked
        ]
        if count:
            fresh = fresh[:count]
        if not fresh:
            return []
        for mid, _fields in fresh:
            self.delivered[mid] = 0.0  # just delivered: zero idle time
        return [(worker_module.STREAM_KEY, fresh)]

    async def xautoclaim(
        self, _key, _group, _consumer, min_idle_time=0, start_id="0-0", count=None
    ):
        idle_threshold = min_idle_time / 1000.0
        stale = [
            (mid, self.messages[mid])
            for mid, idle in self.delivered.items()
            if mid not in self.acked and idle >= idle_threshold
        ]
        if count:
            stale = stale[:count]
        for mid, _fields in stale:
            self.delivered[mid] = 0.0  # reclaiming resets the idle clock
        return ["0-0", stale, []]

    async def xack(self, _key, _group, *ids):
        self.acked.extend(ids)

    async def setex(self, key, _ttl, value):
        self.insights[key] = value

    def simulate_crash_before_ack(self, idle_seconds: float) -> None:
        """Age every delivered-but-unacked message, as if the worker that
        read them died before acking."""
        for mid in self.delivered:
            if mid not in self.acked:
                self.delivered[mid] = idle_seconds


@pytest.fixture
def fake_redis(monkeypatch):
    fake = FakeStreamRedis()

    async def fake_get_redis():
        return fake

    monkeypatch.setattr(worker_module, "get_redis", fake_get_redis)
    return fake


@pytest.fixture(autouse=True)
def fake_session(monkeypatch):
    session = object()  # never touched directly; compute_insights is mocked
    monkeypatch.setattr(
        worker_module, "AsyncSessionLocal", lambda: _SessionContext(session)
    )
    monkeypatch.setattr(worker_module, "close_db", AsyncMock())
    return session


async def test_drain_is_noop_when_stream_empty(fake_redis):
    result = await worker_module._drain()

    assert result == {"drained": 0}


async def test_drain_skips_when_redis_unavailable(monkeypatch, fake_session):
    monkeypatch.setattr(worker_module, "get_redis", AsyncMock(return_value=None))

    result = await worker_module._drain()

    assert result == {"drained": 0, "skipped": "redis unavailable"}


async def test_drain_recomputes_and_caches_per_user(monkeypatch, fake_redis):
    user_a = "11111111-1111-4111-8111-111111111111"
    user_b = "22222222-2222-4222-8222-222222222222"
    await fake_redis.xadd(worker_module.STREAM_KEY, {"user_id": user_a})
    await fake_redis.xadd(worker_module.STREAM_KEY, {"user_id": user_b})

    monkeypatch.setattr(worker_module, "get_assessed_level", AsyncMock(return_value="A2"))
    compute = AsyncMock(return_value={"topic_affinity": {"travel": 1.0}})
    monkeypatch.setattr(worker_module, "compute_insights", compute)

    result = await worker_module._drain()

    assert result == {"drained": 2, "reclaimed": 0, "users_recomputed": 2}
    assert set(fake_redis.acked) == {"1-0", "2-0"}
    assert json.loads(fake_redis.insights[f"{worker_module.INSIGHTS_CACHE_PREFIX}{user_a}"]) == {
        "topic_affinity": {"travel": 1.0}
    }
    assert compute.await_count == 2


async def test_drain_dedupes_multiple_events_for_same_user(monkeypatch, fake_redis):
    user_id = "33333333-3333-4333-8333-333333333333"
    for _ in range(3):
        await fake_redis.xadd(worker_module.STREAM_KEY, {"user_id": user_id})

    monkeypatch.setattr(worker_module, "get_assessed_level", AsyncMock(return_value="A1"))
    compute = AsyncMock(return_value={"topic_affinity": {}})
    monkeypatch.setattr(worker_module, "compute_insights", compute)

    result = await worker_module._drain()

    assert result == {"drained": 3, "reclaimed": 0, "users_recomputed": 1}
    assert compute.await_count == 1
    assert len(fake_redis.acked) == 3


async def test_drain_acks_everything_even_when_one_user_fails(monkeypatch, fake_redis):
    good_user = "44444444-4444-4444-8444-444444444444"
    await fake_redis.xadd(worker_module.STREAM_KEY, {"user_id": "not-a-uuid"})
    await fake_redis.xadd(worker_module.STREAM_KEY, {"user_id": good_user})

    monkeypatch.setattr(worker_module, "get_assessed_level", AsyncMock(return_value="A1"))
    monkeypatch.setattr(
        worker_module, "compute_insights", AsyncMock(return_value={"topic_affinity": {}})
    )

    result = await worker_module._drain()

    # The poison message (unparseable user_id) must not block the good one,
    # and both message ids must still be acked so the stream doesn't jam.
    assert result["drained"] == 2
    assert result["users_recomputed"] == 1
    assert set(fake_redis.acked) == {"1-0", "2-0"}
    assert f"{worker_module.INSIGHTS_CACHE_PREFIX}{good_user}" in fake_redis.insights


async def test_stale_pending_message_is_reclaimed_after_a_crash(monkeypatch, fake_redis):
    """A worker that dies between XREADGROUP and XACK leaves the message
    pending. XREADGROUP ">" will never return it again, so without the
    reclaim path that user's insights would stop refreshing permanently."""
    user_id = "55555555-5555-4555-8555-555555555555"
    await fake_redis.xadd(worker_module.STREAM_KEY, {"user_id": user_id})

    monkeypatch.setattr(worker_module, "get_assessed_level", AsyncMock(return_value="A1"))
    compute = AsyncMock(return_value={"topic_affinity": {}})
    monkeypatch.setattr(worker_module, "compute_insights", compute)

    # First tick delivers the message, then the process "dies" before acking.
    await fake_redis.xreadgroup(None, None, None)
    fake_redis.simulate_crash_before_ack(idle_seconds=120)
    assert not fake_redis.acked

    # A plain re-read finds nothing — the message is invisible to ">".
    assert await fake_redis.xreadgroup(None, None, None) == []

    result = await worker_module._drain()

    assert result["reclaimed"] == 1
    assert result["users_recomputed"] == 1
    assert fake_redis.acked == ["1-0"]
    assert f"{worker_module.INSIGHTS_CACHE_PREFIX}{user_id}" in fake_redis.insights


async def test_fresh_pending_message_is_not_stolen_mid_flight(monkeypatch, fake_redis):
    """Only messages idle past STALE_PENDING_MS are reclaimed — a message a
    concurrent worker is still processing must be left alone."""
    await fake_redis.xadd(worker_module.STREAM_KEY, {"user_id": "in-flight"})
    await fake_redis.xreadgroup(None, None, None)  # delivered, idle = 0

    monkeypatch.setattr(worker_module, "get_assessed_level", AsyncMock(return_value="A1"))
    monkeypatch.setattr(
        worker_module, "compute_insights", AsyncMock(return_value={"topic_affinity": {}})
    )

    result = await worker_module._drain()

    assert result == {"drained": 0}
    assert not fake_redis.acked


async def test_ensure_group_ignores_busygroup_on_second_call(fake_redis):
    await worker_module._ensure_group(fake_redis)
    await worker_module._ensure_group(fake_redis)  # must not raise

    assert worker_module.CONSUMER_GROUP in fake_redis.groups


async def test_run_connects_only_when_not_already_connected(monkeypatch):
    """RedisClient.connect() must run once for a cold worker process, and
    never again for a later task tick — this is what actually fixes a Celery
    worker (which never runs FastAPI's lifespan) being unable to reach Redis
    at all without it. Verified against mocks, not a real connection."""
    connect = AsyncMock()
    drain = AsyncMock(return_value={"drained": 0})
    monkeypatch.setattr(worker_module.RedisClient, "connect", connect)
    monkeypatch.setattr(worker_module, "_drain", drain)

    monkeypatch.setattr(worker_module.RedisClient, "is_connected", lambda: False)
    await worker_module._run()
    assert connect.await_count == 1

    monkeypatch.setattr(worker_module.RedisClient, "is_connected", lambda: True)
    await worker_module._run()
    assert connect.await_count == 1  # unchanged — already connected
