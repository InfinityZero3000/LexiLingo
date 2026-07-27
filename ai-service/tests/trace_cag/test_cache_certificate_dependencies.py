import time
from unittest.mock import AsyncMock

import pytest

import api.services.trace_cag.cache_utils as cache_mod
from api.services.trace_cag.cache_utils import _build_admissibility_certificate
from api.core.redis_client import RedisClient


def test_certificate_contains_compiled_dependency_snapshot():
    certificate = _build_admissibility_certificate(
        state={
            "user_input": "Who founded ExampleCo?",
            "dependency_events": [
                {"key": "policy:tutor", "kind": "policy", "version": "v2", "provenance": "prompt-registry", "required": True},
                {"key": "kg:main", "kind": "kg", "version": "v4", "provenance": "kuzu", "required": True},
                {"key": "policy:tutor", "kind": "policy", "version": "v2", "provenance": "prompt-registry", "required": True},
            ],
        },
        fingerprint={"query_norm": "who founded exampleco?", "intent": "ask", "level": "B1"},
        profile_epoch=3,
        state_hints={},
        now=time.time(),
    )

    assert certificate["dependencies"] == [
        {"key": "kg:main", "kind": "kg", "version": "v4", "provenance": "kuzu", "required": True},
        {"key": "policy:tutor", "kind": "policy", "version": "v2", "provenance": "prompt-registry", "required": True},
    ]


@pytest.mark.asyncio
async def test_invalid_required_dependency_prevents_cache_write():
    cache_mod._MEM_RESPONSE_CACHE.clear()

    await cache_mod._write_cache_entry(
        {
            "user_input": "Who founded ExampleCo?",
            "learner_profile": {"level": "B1"},
            "dependency_events": [
                {"key": "kg:main", "kind": "kg", "version": "", "provenance": "kuzu", "required": True},
            ],
        },
        response="Example answer",
        strategy="qa",
        errors=[],
        overall_score=1.0,
    )

    assert cache_mod._MEM_RESPONSE_CACHE == {}


@pytest.mark.asyncio
async def test_cache_write_stores_projection_hashes():
    cache_mod._MEM_RESPONSE_CACHE.clear()
    await cache_mod._write_cache_entry(
        {
            "user_input": "Who founded ExampleCo?",
            "learner_profile": {"level": "B1"},
            "retrieval_trace": [{"item_id": "exampleco", "title": "ExampleCo"}],
            "dependency_events": [
                {"key": "source:exampleco", "kind": "source", "version": "v1", "provenance": "fixture", "required": True},
            ],
        },
        response="Ada Example founded ExampleCo.",
        strategy="qa",
        errors=[],
        overall_score=1.0,
    )

    entry = next(iter(cache_mod._MEM_RESPONSE_CACHE.values()))[1]
    certificate = entry["admissibility_certificate"]
    assert certificate["schema_version"] == 3
    assert certificate["factual_projection_hash"] == cache_mod._projection_hash(
        "Ada Example founded ExampleCo."
    )
    assert certificate["provenance_projection_hash"] == cache_mod._projection_hash(
        [{"item_id": "exampleco", "title": "ExampleCo"}]
    )


@pytest.mark.asyncio
async def test_redis_miss_does_not_serve_stale_worker_local_entry(monkeypatch):
    now = time.time()
    cache_mod._MEM_RESPONSE_CACHE["k"] = (now + 60, {"response": "stale"})
    redis = AsyncMock()
    redis.get = AsyncMock(return_value=None)
    monkeypatch.setattr(RedisClient, "get_instance", AsyncMock(return_value=redis))

    assert await cache_mod._get_cache_entry("k", "B1", now) is None


@pytest.mark.asyncio
async def test_redis_outage_fails_closed_instead_of_using_worker_local_entry(monkeypatch):
    now = time.time()
    entry = {"response": "fallback"}
    cache_mod._MEM_RESPONSE_CACHE["k"] = (now + 60, entry)
    redis = AsyncMock()
    redis.get = AsyncMock(side_effect=ConnectionError("redis unavailable"))
    monkeypatch.setattr(RedisClient, "get_instance", AsyncMock(return_value=redis))
    monkeypatch.setattr(RedisClient, "_benchmark_redis_disabled", lambda: False)

    assert await cache_mod._get_cache_entry("k", "B1", now) is None
