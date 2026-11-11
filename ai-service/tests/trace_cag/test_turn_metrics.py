import asyncio
from unittest.mock import AsyncMock, MagicMock

import pytest

from api.services.trace_cag import turn_metrics

STATE = {
    "session_id": "s1",
    "user_input": "SECRET learner text",
    "tutor_response": "SECRET reply",
    "path": "slow",
    "cache_hit": False,
    "latency_ms": 1234,
    "ttft_ms": 400,
    "kg_seed_concepts": ["a", "b"],
    "kg_expanded_nodes": ["x"],
    "retrieval_trace": [{}, {}, {}],
    "diagnosis_errors": [{}],
    "models_used": ["qwen"],
    "prompt_tokens": 900,
}


def test_the_row_carries_numbers_and_never_the_conversation():
    doc = turn_metrics.build_turn_metrics(STATE)

    assert (doc["kg_seed"], doc["kg_expanded"], doc["retrieved"], doc["diagnosis_errors"]) == (2, 1, 3, 1)
    assert doc["latency_ms"] == 1234 and doc["models"] == ["qwen"]
    assert "SECRET" not in repr(doc)


@pytest.mark.parametrize("key", ["benchmark_task", "benchmark_context"])
def test_benchmark_runs_are_not_recorded(key):
    assert turn_metrics.build_turn_metrics({**STATE, key: "hotpot"}) is None


@pytest.mark.asyncio
async def test_a_dead_mongo_never_reaches_the_caller(monkeypatch):
    broken = MagicMock()
    type(broken).db = property(lambda self: (_ for _ in ()).throw(RuntimeError("down")))
    monkeypatch.setattr("api.core.database.mongodb_manager", broken)
    monkeypatch.setattr(turn_metrics, "_index_ready", False)

    turn_metrics.record_turn_metrics(STATE)
    await asyncio.gather(*turn_metrics._pending)


@pytest.mark.asyncio
async def test_the_row_is_inserted_and_the_ttl_index_created_once(monkeypatch):
    collection = MagicMock()
    collection.create_index = AsyncMock()
    collection.insert_one = AsyncMock()
    manager = MagicMock()
    manager.db = {turn_metrics.COLLECTION: collection}
    monkeypatch.setattr("api.core.database.mongodb_manager", manager)
    monkeypatch.setattr(turn_metrics, "_index_ready", False)

    for _ in range(2):
        turn_metrics.record_turn_metrics(STATE)
        await asyncio.gather(*turn_metrics._pending)

    collection.create_index.assert_awaited_once_with("ts", expireAfterSeconds=turn_metrics.RETENTION_SECONDS)
    assert collection.insert_one.await_count == 2
