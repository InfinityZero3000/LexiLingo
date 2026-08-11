from unittest.mock import AsyncMock, MagicMock

import pytest

from api.clients.learner_state_client import LearnerStateResult
from api.services.trace_cag import nodes_v2
from api.services.trace_cag import cache_utils
from api.services.trace_cag.cache_utils import _profile_epoch


@pytest.mark.asyncio
async def test_overlay_loads_only_deduplicated_request_concepts(monkeypatch):
    client = MagicMock()
    client.batch_get = AsyncMock(
        return_value=LearnerStateResult(
            state_epoch=9,
            states={"concept:a": {"mastery_probability": 0.2}},
        )
    )
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_DEADLINE_MS", 40)
    monkeypatch.setattr(
        "api.clients.learner_state_client.get_learner_state_client", lambda: client
    )

    result = await nodes_v2._load_learner_concept_overlay(
        {"user_id": "user-1"},
        {
            "kg_seed_concepts": ["concept:a", "concept:a"],
            "diagnosis_root_causes": ["concept:b"],
            "kg_expanded_nodes": [{"id": "concept:c"}],
        },
    )

    requested = client.batch_get.await_args.args[1]
    assert requested == ["concept:a", "concept:b", "concept:c"]
    assert result["learner_state_epoch"] == 9
    assert result["learner_state_degraded"] is False


@pytest.mark.asyncio
async def test_overlay_is_noop_when_rollout_is_off(monkeypatch):
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "off")
    assert await nodes_v2._load_learner_concept_overlay(
        {"user_id": "user-1"}, {"kg_seed_concepts": ["concept:a"]}
    ) == {}


def test_cache_profile_epoch_changes_with_durable_learner_epoch():
    base = {"level": "B1", "common_errors": []}
    assert _profile_epoch(base) != _profile_epoch({**base, "_learner_state_epoch": 1})


@pytest.mark.asyncio
async def test_input_merges_learner_epoch_into_profile_cache_version(monkeypatch):
    from api.core import redis_client

    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_DEADLINE_MS", 40)
    monkeypatch.setattr(
        redis_client.RedisClient, "_benchmark_redis_disabled", lambda: False
    )
    monkeypatch.setattr(
        redis_client.RedisClient,
        "get_instance",
        AsyncMock(return_value=MagicMock()),
    )
    monkeypatch.setattr(
        redis_client.LearnerProfileCache,
        "get_profile",
        AsyncMock(return_value={"level": "B2", "common_errors": []}),
    )
    monkeypatch.setattr(
        redis_client.ConversationCache,
        "get_history",
        AsyncMock(return_value=[]),
    )
    client = MagicMock()
    client.batch_get = AsyncMock(return_value=LearnerStateResult(state_epoch=17))
    monkeypatch.setattr(
        "api.clients.learner_state_client.get_learner_state_client", lambda: client
    )

    result = await nodes_v2.input_node(
        {
            "user_input": "Explain this sentence",
            "user_id": "user-1",
            "session_id": "session-1",
            "learner_profile": {"level": "B1"},
        }
    )

    profile = result["learner_profile"]
    assert profile["_learner_state_epoch"] == 17
    assert profile["_learner_state_available"] is True
    assert _profile_epoch(profile) != _profile_epoch(
        {key: value for key, value in profile.items() if key != "_learner_state_epoch"}
    )
    client.batch_get.assert_awaited_once()


@pytest.mark.asyncio
async def test_input_merges_onboarding_goal_and_interest_into_profile(monkeypatch):
    """The onboarding goal/interest ride the same epoch pull as mastery data,
    so a chat turn immediately sees them without a separate sync mechanism."""
    from api.core import redis_client

    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_DEADLINE_MS", 40)
    monkeypatch.setattr(
        redis_client.RedisClient, "_benchmark_redis_disabled", lambda: False
    )
    monkeypatch.setattr(
        redis_client.RedisClient,
        "get_instance",
        AsyncMock(return_value=MagicMock()),
    )
    monkeypatch.setattr(
        redis_client.LearnerProfileCache,
        "get_profile",
        AsyncMock(return_value={"level": "B2", "common_errors": []}),
    )
    monkeypatch.setattr(
        redis_client.ConversationCache,
        "get_history",
        AsyncMock(return_value=[]),
    )
    client = MagicMock()
    client.batch_get = AsyncMock(
        return_value=LearnerStateResult(
            state_epoch=17, goal="career", interest="technology"
        )
    )
    monkeypatch.setattr(
        "api.clients.learner_state_client.get_learner_state_client", lambda: client
    )

    result = await nodes_v2.input_node(
        {
            "user_input": "Explain this sentence",
            "user_id": "user-1",
            "session_id": "session-1",
            "learner_profile": {"level": "B1"},
        }
    )

    profile = result["learner_profile"]
    assert profile["goal"] == "career"
    assert profile["interest"] == "technology"


@pytest.mark.asyncio
async def test_input_fetches_epoch_even_when_redis_is_unavailable(monkeypatch):
    from api.core import redis_client

    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_DEADLINE_MS", 40)
    monkeypatch.setattr(
        redis_client.RedisClient, "_benchmark_redis_disabled", lambda: False
    )
    monkeypatch.setattr(
        redis_client.RedisClient,
        "get_instance",
        AsyncMock(side_effect=RuntimeError("redis down")),
    )
    client = MagicMock()
    client.batch_get = AsyncMock(return_value=LearnerStateResult(state_epoch=23))
    monkeypatch.setattr(
        "api.clients.learner_state_client.get_learner_state_client", lambda: client
    )

    result = await nodes_v2.input_node(
        {"user_input": "Help", "user_id": "user-1", "learner_profile": {"level": "B1"}}
    )

    assert result["learner_profile"]["_learner_state_epoch"] == 23
    assert result["learner_profile"]["_learner_state_available"] is True
    client.batch_get.assert_awaited_once()


def test_personalized_cache_scope_is_distinct_without_exposing_user_id(monkeypatch):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(cache_utils.settings, "SECRET_KEY", "test-cache-secret")
    first = cache_utils._user_cache_scope({"user_id": "user-a"})
    second = cache_utils._user_cache_scope({"user_id": "user-b"})

    assert first != second
    assert "user-a" not in first
    assert "user-b" not in second


def test_personalized_cache_scope_remains_distinct_when_learner_state_is_off(monkeypatch):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "off")
    monkeypatch.setattr(cache_utils.settings, "SECRET_KEY", "test-cache-secret")

    first = cache_utils._user_cache_scope({"user_id": "user-a"})
    second = cache_utils._user_cache_scope({"user_id": "user-b"})

    assert first
    assert second
    assert first != second
    assert "user-a" not in first
    assert "user-b" not in second


def test_personalized_cache_scope_fails_closed_without_a_secret(monkeypatch):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "off")
    monkeypatch.setattr(cache_utils.settings, "SECRET_KEY", "")
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_INTERNAL_TOKEN", "")

    assert cache_utils._user_cache_scope({"user_id": "user-a"}) is None
    assert cache_utils._user_cache_scope({"user_id": "user-b"}) is None


@pytest.mark.asyncio
async def test_personalized_scope_does_not_enter_semantic_request_signature(monkeypatch):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(cache_utils.settings, "SECRET_KEY", "test-cache-secret")
    monkeypatch.setattr(cache_utils, "_get_cache_entry", AsyncMock(return_value=None))
    monkeypatch.setattr(cache_utils, "_get_bucket_candidate_keys", AsyncMock(return_value=[]))
    original = cache_utils._build_l1_request_signature
    semantic_inputs = []

    def capture_signature(**kwargs):
        semantic_inputs.append(kwargs["user_input"])
        return original(**kwargs)

    monkeypatch.setattr(cache_utils, "_build_l1_request_signature", capture_signature)
    query = "Explain the past perfect"

    await cache_utils.cache_gate_node({
        "user_input": query,
        "user_id": "user-a",
        "learner_profile": {
            "level": "B1",
            "_learner_state_epoch": 4,
            "_learner_state_available": True,
        },
        "cache_policy": "on",
    })

    assert semantic_inputs == [query]
    assert cache_utils._user_cache_scope({"user_id": "user-a"}) not in semantic_inputs[0]


@pytest.mark.asyncio
async def test_cache_gate_fails_closed_when_learner_epoch_is_unavailable(monkeypatch):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "read")

    result = await cache_utils.cache_gate_node(
        {
            "user_input": "Explain this",
            "user_id": "user-1",
            "learner_profile": {"level": "B1", "_learner_state_available": False},
            "cache_policy": "on",
        }
    )

    assert result["cache_hit"] is False
    assert result["cache_decision"] == "full"
    assert result["cache_gate_meta"]["reasons"] == ["learner_epoch_unavailable"]


@pytest.mark.asyncio
async def test_personalized_response_entries_are_isolated_per_user(monkeypatch):
    from api.core import redis_client

    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(cache_utils.settings, "SECRET_KEY", "test-cache-secret")
    monkeypatch.setattr(
        redis_client.RedisClient,
        "get_instance",
        AsyncMock(side_effect=RuntimeError("redis intentionally unavailable")),
    )
    cache_utils._MEM_RESPONSE_CACHE.clear()
    common = {
        "user_input": "Explain this",
        "learner_profile": {
            "level": "B1",
            "_learner_state_epoch": 4,
            "_learner_state_available": True,
        },
    }

    await cache_utils._write_cache_entry(
        {**common, "user_id": "user-a"}, "answer-a", "feedback", [], 0.8
    )
    await cache_utils._write_cache_entry(
        {**common, "user_id": "user-b"}, "answer-b", "feedback", [], 0.8
    )

    entries = [entry[1]["response"] for entry in cache_utils._MEM_RESPONSE_CACHE.values()]
    assert sorted(entries) == ["answer-a", "answer-b"]
    assert len(cache_utils._MEM_RESPONSE_CACHE) == 2


@pytest.mark.asyncio
async def test_degraded_epoch_fetch_marks_profile_unavailable_and_gate_fails_closed(
    monkeypatch,
):
    from api.core import redis_client

    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(
        redis_client.RedisClient, "_benchmark_redis_disabled", lambda: True
    )
    client = MagicMock()
    client.batch_get = AsyncMock(
        return_value=LearnerStateResult(
            state_epoch=0, degraded=True, reason="circuit_open"
        )
    )
    monkeypatch.setattr(
        "api.clients.learner_state_client.get_learner_state_client", lambda: client
    )

    input_result = await nodes_v2.input_node(
        {"user_input": "Explain this", "user_id": "user-1"}
    )
    gate_result = await cache_utils.cache_gate_node(
        {
            "user_input": "Explain this",
            "user_id": "user-1",
            "learner_profile": input_result["learner_profile"],
            "cache_policy": "on",
        }
    )

    assert input_result["learner_profile"]["_learner_state_available"] is False
    assert input_result["learner_state_reason"] == "circuit_open"
    assert gate_result["cache_hit"] is False
    assert gate_result["cache_gate_meta"]["reasons"] == [
        "learner_epoch_unavailable"
    ]


@pytest.mark.asyncio
async def test_overlay_unexpected_error_degrades_without_breaking_chat(monkeypatch):
    client = MagicMock()
    client.batch_get = AsyncMock(side_effect=RuntimeError("boom"))
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(
        "api.clients.learner_state_client.get_learner_state_client", lambda: client
    )

    result = await nodes_v2._load_learner_concept_overlay(
        {"user_id": "user-1", "learner_profile": {"_learner_state_epoch": 8}},
        {"kg_seed_concepts": ["concept:a"]},
    )

    assert result["learner_concept_states"] == {}
    assert result["learner_state_epoch"] == 8
    assert result["learner_state_degraded"] is True
    assert result["learner_state_reason"] == "unexpected_error"


@pytest.mark.asyncio
async def test_degraded_overlay_does_not_discard_merged_pipeline_results(monkeypatch):
    monkeypatch.setattr(
        nodes_v2,
        "kg_expand_node",
        AsyncMock(return_value={"kg_seed_concepts": ["concept:a"], "models_used": ["kg"]}),
    )
    monkeypatch.setattr(
        nodes_v2,
        "diagnose_node",
        AsyncMock(
            return_value={
                "diagnosis_root_causes": ["concept:b"],
                "models_used": ["diagnoser"],
            }
        ),
    )
    monkeypatch.setattr(
        nodes_v2,
        "_jit_graph_extract_node",
        AsyncMock(return_value={"jit_soft_graph": {"nodes": []}, "models_used": ["jit"]}),
    )
    monkeypatch.setattr(
        nodes_v2,
        "_load_learner_concept_overlay",
        AsyncMock(
            return_value={
                "learner_concept_states": {},
                "learner_state_degraded": True,
                "learner_state_reason": "timeout",
            }
        ),
    )

    result = await nodes_v2.kg_diagnose_node({"user_id": "user-1"})

    assert result["kg_seed_concepts"] == ["concept:a"]
    assert result["diagnosis_root_causes"] == ["concept:b"]
    assert result["jit_soft_graph"] == {"nodes": []}
    assert result["learner_state_degraded"] is True
    assert result["models_used"] == ["kg", "diagnoser", "jit"]


@pytest.mark.asyncio
async def test_overlay_caps_backend_request_at_sixty_candidates(monkeypatch):
    client = MagicMock()
    client.batch_get = AsyncMock(return_value=LearnerStateResult())
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_DEADLINE_MS", 40)
    monkeypatch.setattr(
        "api.clients.learner_state_client.get_learner_state_client", lambda: client
    )

    await nodes_v2._load_learner_concept_overlay(
        {"user_id": "user-1"},
        {"kg_expanded_nodes": [{"id": f"concept:{index}"} for index in range(80)]},
    )

    requested = client.batch_get.await_args.args[1]
    assert len(requested) == 60
    assert requested == [f"concept:{index}" for index in range(60)]


@pytest.mark.asyncio
async def test_shared_concepts_keep_learner_state_scoped_to_user(monkeypatch):
    client = MagicMock()

    async def batch_get(user_id, concept_ids, *, deadline):
        del deadline
        mastery = 0.2 if user_id == "user-a" else 0.9
        return LearnerStateResult(
            state_epoch=1,
            states={concept_ids[0]: {"mastery_probability": mastery}},
        )

    client.batch_get = AsyncMock(side_effect=batch_get)
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(nodes_v2.settings, "LEARNER_STATE_DEADLINE_MS", 40)
    monkeypatch.setattr(
        "api.clients.learner_state_client.get_learner_state_client", lambda: client
    )
    merged = {"kg_seed_concepts": ["concept:shared"]}

    first = await nodes_v2._load_learner_concept_overlay(
        {"user_id": "user-a"}, merged
    )
    second = await nodes_v2._load_learner_concept_overlay(
        {"user_id": "user-b"}, merged
    )

    assert first["learner_concept_states"]["concept:shared"]["mastery_probability"] == 0.2
    assert second["learner_concept_states"]["concept:shared"]["mastery_probability"] == 0.9
    assert [call.args[0] for call in client.batch_get.await_args_list] == [
        "user-a",
        "user-b",
    ]
