import pytest

from api.services.content_agent.adapters import normalize_source_records
from api.services.content_agent.store import ContentAgentStore


def _record():
    return normalize_source_records(
        [
            {
                "record_id": "upload:1",
                "word": "book",
                "declared_cefr": "A1",
            }
        ],
        source_name="admin_upload",
    )[0]


class FakeRedis:
    def __init__(self):
        self.values = {}
        self.expirations = {}

    async def get(self, key):
        return self.values.get(key)

    async def set(self, key, value, *, ex):
        self.values[key] = value
        self.expirations[key] = ex

    async def delete(self, key):
        self.values.pop(key, None)


class FailingRedis:
    async def get(self, key):
        raise ConnectionError("redis unavailable")

    async def set(self, key, value, *, ex):
        raise ConnectionError("redis unavailable")

    async def delete(self, key):
        raise ConnectionError("redis unavailable")


@pytest.mark.asyncio
async def test_store_uses_redis_with_configured_ttl():
    redis = FakeRedis()
    store = ContentAgentStore(
        ttl_seconds=45,
        max_records=10,
        redis_client=redis,
    )

    assert await store.append("job-1", [_record()]) == 1
    assert await store.get("job-1") == [_record()]
    assert redis.expirations["content-agent:job:job-1:records"] == 45


@pytest.mark.asyncio
async def test_store_falls_back_locally_when_redis_is_unavailable():
    store = ContentAgentStore(
        ttl_seconds=45,
        max_records=10,
        redis_client=FailingRedis(),
    )

    assert await store.append("job-1", [_record()]) == 1
    assert await store.get("job-1") == [_record()]
    await store.delete("job-1")
    assert await store.get("job-1") is None


@pytest.mark.asyncio
async def test_store_fails_closed_when_local_fallback_is_disabled():
    store = ContentAgentStore(
        ttl_seconds=45,
        max_records=10,
        redis_client=FailingRedis(),
        allow_local_fallback=False,
    )

    with pytest.raises(RuntimeError, match="Redis read failed"):
        await store.append("job-1", [_record()])
