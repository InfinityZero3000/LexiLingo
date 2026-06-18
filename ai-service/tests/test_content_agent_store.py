import pytest

from api.services.content_agent.adapters import normalize_source_records
from api.models.content_agent import SourceSnapshotDescriptor
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


def _snapshot(snapshot_id: str = "oewn:2025:" + "a" * 64) -> SourceSnapshotDescriptor:
    return SourceSnapshotDescriptor(
        source_id="oewn",
        source_name="oewn",
        source_version="2025",
        snapshot_id=snapshot_id,
        official_url="https://en-word.net/static/english-wordnet-2025.xml.gz",
        license_id="CC-BY-4.0",
        license_url="https://creativecommons.org/licenses/by/4.0/",
        attribution_text="Open English WordNet 2025",
        retrieved_at="2026-06-15T00:00:00Z",
        raw_checksum="a" * 64,
        normalized_sha256="b" * 64,
        normalized_bytes=100,
        record_checksum_root="c" * 64,
        adapter_version=1,
        record_count=1,
        enabled=True,
    )


def _oewn_record():
    return normalize_source_records(
        [
            {
                "record_id": "oewn:1",
                "word": "journey",
                "definition": "A complete definition.",
            }
        ],
        source_name="oewn",
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
async def test_attach_snapshot_records_is_idempotent_for_same_snapshot_set():
    store = ContentAgentStore(ttl_seconds=45, max_records=10)

    assert await store.attach_snapshot_records("job-1", [_oewn_record()], [_snapshot()]) == 1
    assert await store.attach_snapshot_records("job-1", [_oewn_record()], [_snapshot()]) == 1
    assert len(await store.get("job-1") or []) == 1
    with pytest.raises(ValueError, match="different set"):
        await store.attach_snapshot_records(
            "job-1",
            [_oewn_record()],
            [_snapshot("oewn:2025:" + "d" * 64)],
        )


@pytest.mark.asyncio
async def test_attach_snapshot_records_preserves_other_sources():
    store = ContentAgentStore(ttl_seconds=45, max_records=10)
    await store.append("job-1", [_record()])

    attached_count = await store.attach_snapshot_records(
        "job-1",
        [_oewn_record()],
        [_snapshot()],
    )

    records = await store.get("job-1") or []
    assert attached_count == 2
    assert {record.source_name for record in records} == {"admin_upload", "oewn"}


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
