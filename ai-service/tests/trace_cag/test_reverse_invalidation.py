from api.services.trace_cag.invalidation import (
    _MEM_REVERSE_INDEX,
    clear_reverse_index,
    pop_dependent_artifacts,
    register_reverse_edges,
    register_reverse_edges_redis,
    pop_dependent_artifacts_redis,
    remove_reverse_edges,
)
from unittest.mock import AsyncMock
import pytest


def setup_function():
    clear_reverse_index()


def test_related_dependency_selects_only_dependent_artifacts():
    register_reverse_edges("a1", [{"key": "kg:main"}, {"key": "policy:tutor"}])
    register_reverse_edges("a2", [{"key": "policy:tutor"}])

    assert pop_dependent_artifacts("kg:main") == {"a1"}
    assert _MEM_REVERSE_INDEX["policy:tutor"] == {"a2"}


def test_unrelated_dependency_preserves_artifacts():
    register_reverse_edges("a1", [{"key": "kg:main"}])

    assert pop_dependent_artifacts("learner:u1") == set()
    assert _MEM_REVERSE_INDEX["kg:main"] == {"a1"}


def test_edge_cleanup_removes_empty_sets():
    register_reverse_edges("a1", [{"key": "kg:main"}])

    remove_reverse_edges("a1")

    assert "kg:main" not in _MEM_REVERSE_INDEX


@pytest.mark.asyncio
async def test_redis_reverse_edges_round_trip():
    redis = AsyncMock()
    redis.smembers.return_value = {b"a1", "a2"}

    await register_reverse_edges_redis(redis, "a1", [{"key": "kg:main"}], 60)
    artifacts = await pop_dependent_artifacts_redis(redis, "kg:main")

    assert artifacts == {"a1", "a2"}
    redis.sadd.assert_awaited_once()
    redis.expire.assert_awaited_once()
    redis.delete.assert_awaited_once()
