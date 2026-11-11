"""The in-process cache indexes must stay bounded however many users and answers pass through."""

import json
import time
from unittest.mock import AsyncMock

import pytest

import api.services.trace_cag.cache_utils as cache_mod
import api.services.trace_cag.invalidation as inv
from api.core.redis_client import RedisClient
from api.services.trace_cag.bounded import LRUDict


@pytest.fixture(autouse=True)
def _clean_indexes():
    for store in (cache_mod._MEM_RESPONSE_CACHE, cache_mod._MEM_GRAPH_BUCKETS, cache_mod._MEM_BUCKET_VERSIONS):
        store.clear()
    yield
    for store in (cache_mod._MEM_RESPONSE_CACHE, cache_mod._MEM_GRAPH_BUCKETS, cache_mod._MEM_BUCKET_VERSIONS):
        store.clear()


def test_lru_drops_the_least_recently_used_key():
    dropped = []
    d = LRUDict(3, on_evict=lambda k, v: dropped.append(k))
    for i in range(3):
        d[i] = i
    d.get(0)
    d[3] = 3

    assert list(d) == [2, 0, 3]
    assert dropped == [1]


def test_lru_does_not_report_explicit_removals_as_evictions():
    dropped = []
    d = LRUDict(2, on_evict=lambda k, v: dropped.append(k))
    d["a"] = 1
    d.pop("a")
    d["b"] = 2
    d.clear()

    assert dropped == []


def test_lru_keeps_pinned_keys_and_never_loses_one_when_all_are_pinned():
    d = LRUDict(2, can_evict=lambda k: k != "pinned")
    d["pinned"] = 0
    for i in range(5):
        d[i] = i
    assert "pinned" in d and len(d) == 2

    all_pinned = LRUDict(1, can_evict=lambda k: False)
    all_pinned["x"] = 1
    all_pinned["y"] = 2
    assert set(all_pinned) == {"x", "y"}


def test_bucket_index_is_capped_and_takes_its_version_records_with_it(monkeypatch):
    monkeypatch.setattr(cache_mod._MEM_GRAPH_BUCKETS, "max_items", 5)

    for i in range(200):
        cache_mod._register_graph_bucket(f"bucket-{i}", f"key-{i}")

    assert len(cache_mod._MEM_GRAPH_BUCKETS) == 5
    assert set(cache_mod._MEM_BUCKET_VERSIONS) == set(cache_mod._MEM_GRAPH_BUCKETS)


def test_response_cache_cap_also_drops_reverse_edges(monkeypatch):
    monkeypatch.setattr(cache_mod._MEM_RESPONSE_CACHE, "max_items", 3)
    inv.clear_reverse_index()

    for i in range(10):
        inv.register_reverse_edges(f"artifact-{i}", [{"key": f"dep-{i}"}])
        cache_mod._MEM_RESPONSE_CACHE[f"artifact-{i}"] = (time.time() + 60, {})

    assert len(cache_mod._MEM_RESPONSE_CACHE) == 3
    assert set(inv._MEM_ARTIFACT_DEPENDENCIES) == {"artifact-7", "artifact-8", "artifact-9"}
    assert set(inv._MEM_REVERSE_INDEX) == {"dep-7", "dep-8", "dep-9"}


def test_dependency_tokens_are_capped_but_tokens_a_cached_answer_needs_stay(monkeypatch):
    monkeypatch.setattr(inv._MEM_DEPENDENCY_TOKENS, "max_items", 10)
    inv.clear_reverse_index()
    inv.register_reverse_edges("artifact", [{"key": "kg:main"}])
    inv.observe_dependency_tokens([{"key": "kg:main", "version": "v1"}])

    for i in range(500):
        inv.observe_dependency_tokens([{"key": f"learner:{i}:profile", "version": "p"}])

    assert len(inv._MEM_DEPENDENCY_TOKENS) == 10
    assert inv._MEM_DEPENDENCY_TOKENS.get("kg:main") == "v1"
    assert inv.recheck_dependency_snapshot([{"key": "kg:main", "version": "v1", "required": True}]) == (True, ())


def test_an_evicted_token_is_reseeded_by_the_next_request_not_treated_as_a_mutation(monkeypatch):
    monkeypatch.setattr(inv._MEM_DEPENDENCY_TOKENS, "max_items", 2)
    inv.clear_reverse_index()
    inv.observe_dependency_tokens([{"key": "learner:a:profile", "version": "p1"}])
    inv.observe_dependency_tokens([{"key": "learner:b:profile", "version": "p1"}])
    inv.observe_dependency_tokens([{"key": "learner:c:profile", "version": "p1"}])
    assert "learner:a:profile" not in inv._MEM_DEPENDENCY_TOKENS

    inv.observe_dependency_tokens([{"key": "learner:a:profile", "version": "p2"}])

    assert inv._MEM_DEPENDENCY_TOKENS.get("learner:a:profile") == "p2"


@pytest.mark.asyncio
async def test_reading_an_entry_from_redis_does_not_copy_it_into_process_memory(monkeypatch):
    now = time.time()
    fake_redis = AsyncMock()
    fake_redis.get.return_value = json.dumps({
        "response": "hello",
        "created_at": now,
        "ttl": 3600,
        "fingerprint": {"level": "B1"},
    })
    monkeypatch.setattr(RedisClient, "get_instance", AsyncMock(return_value=fake_redis))

    entry = await cache_mod._get_cache_entry("cache-key", "B1", now)

    assert entry["response"] == "hello"
    assert "cache-key" not in cache_mod._MEM_RESPONSE_CACHE
