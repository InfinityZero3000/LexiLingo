"""A cached answer is valid for one conversation context and one current learner state."""

import hashlib
import json
from dataclasses import replace

import pytest

import api.services.trace_cag.cache_utils as cache_mod
import api.services.trace_cag.invalidation as invalidation
import api.services.trace_cag.nodes_v2 as nodes_mod
import api.services.trace_cag.retrieve as retrieve_mod
from api.core.redis_client import RedisClient
from api.services.trace_cag.dependencies import dependency_record
from api.services.trace_cag.l1_state_cache import L1Candidate, L1Request, decide_l1_reuse
from api.services.trace_cag.state import create_initial_state

from .test_kg_mastery_traversal import _DictRedis

FOLLOW_UP = "what about that one?"
MAKE_DO = [{"role": "user", "content": "Compare 'make' and 'do'"}]
PIZZA = [{"role": "user", "content": "Which pizza should I order?"}]
QUESTION = "how do I use the present perfect tense"


@pytest.fixture(autouse=True)
def _env(monkeypatch):
    monkeypatch.setattr(cache_mod.settings, "SECRET_KEY", "test-secret")
    monkeypatch.setattr(cache_mod.settings, "LEARNER_STATE_MODE", "off")
    fake = _DictRedis()

    async def get_instance():
        return fake

    monkeypatch.setattr(RedisClient, "get_instance", get_instance)
    for store in (cache_mod._MEM_RESPONSE_CACHE, cache_mod._MEM_GRAPH_BUCKETS, cache_mod._MEM_BUCKET_VERSIONS):
        store.clear()
    invalidation.clear_reverse_index()


def _state(text=QUESTION, *, user="alice", history=None, epoch=5, evidence="evidence:e1", for_gate=False):
    state = create_initial_state(
        text, "s1", user_id=user,
        learner_profile={"level": "B1", "native_language": "Vietnamese", "_learner_state_epoch": epoch},
    )
    state["conversation_history"] = list(history or [])
    state["diagnosis_confidence"] = 0.9
    state["kg_seed_concepts"] = ["concept:grammar.present_perfect"]
    state["retrieval_trace"] = [{"item_id": "c1", "title": "t", "text": "x"}]
    events = [dependency_record(f"learner:{user}:profile", "learner", str(epoch), "test")]
    if not for_gate:
        events.append(dependency_record(f"evidence:retrieval:{user}:{text}", "evidence", evidence, "test"))
    state["dependency_events"] = events
    return state


async def _write(state, text="cached answer"):
    await cache_mod._write_cache_entry(state, text, "praise", [], 0.8, "ctx", model_used="groq/x")


@pytest.mark.asyncio
async def test_follow_up_is_not_served_from_another_conversation():
    await _write(_state(FOLLOW_UP, history=MAKE_DO), "Use 'do' for tasks.")

    result = await cache_mod.cache_gate_node(_state(FOLLOW_UP, history=PIZZA, for_gate=True))

    assert result["cache_hit"] is False
    assert result.get("tutor_response") != "Use 'do' for tasks."


@pytest.mark.asyncio
async def test_same_conversation_still_hits_l0():
    await _write(_state(FOLLOW_UP, history=MAKE_DO), "Use 'do' for tasks.")

    result = await cache_mod.cache_gate_node(_state(FOLLOW_UP, history=MAKE_DO, for_gate=True))

    assert (result["cache_decision"], result["cache_layer"]) == ("reuse", "L0")
    assert result["tutor_response"] == "Use 'do' for tasks."


def test_digest_reads_both_history_shapes_and_ignores_message_metadata():
    role_shape = [{"role": "user", "content": "Hi"}, {"role": "assistant", "content": "Hello"}]
    pair_shape = [{"user": "Hi", "ai": "Hello"}]
    with_metadata = [{**message, "id": "x", "timestamp": "t"} for message in role_shape]

    assert cache_mod._context_digest(role_shape) == cache_mod._context_digest(pair_shape)
    assert cache_mod._context_digest(role_shape) == cache_mod._context_digest(with_metadata)
    assert cache_mod._context_digest([{"user": "Bye", "ai": "Hello"}]) != cache_mod._context_digest(pair_shape)
    assert cache_mod._context_digest([]) == ""


def test_key_without_history_is_byte_identical_to_the_measured_benchmark_key():
    raw = f"scope||{QUESTION.lower()}||B1||mode"

    assert cache_mod._build_cache_key("scope", QUESTION, "B1", "mode") == hashlib.md5(raw.encode()).hexdigest()


def test_l1_refuses_a_candidate_from_another_conversation():
    base = {
        "query_norm": "q", "intent": "ask", "level": "B1", "profile_epoch": 1, "session_turn": 2,
        "concepts": {"a"}, "answer_target": "person", "policy_version": "p", "kg_version": "k", "user_scope": "a",
    }
    request = L1Request(**base, context_digest="one")
    candidate = L1Candidate(**base, cache_key="k", context_digest="one", created_at=100.0, ttl=3600)

    assert decide_l1_reuse(request, candidate, now=100.0).decision == "reuse"
    other = decide_l1_reuse(request, replace(candidate, context_digest="two"), now=100.0)
    assert other.decision == "full" and "mismatch:context" in other.reasons


@pytest.mark.asyncio
async def test_a_new_profile_version_invalidates_then_the_rewritten_answer_is_served():
    # Production publishes prompt_profile_version, not the raw epoch (test_cache_profile_projection).
    await _write(_state(epoch=5))
    assert (await cache_mod.cache_gate_node(_state(epoch=5, for_gate=True)))["cache_decision"] == "reuse"

    await cache_mod.publish_dependency_version("learner:alice:profile", "6")

    assert (await cache_mod.cache_gate_node(_state(epoch=6, for_gate=True)))["cache_hit"] is False
    await _write(_state(epoch=6), "answer for epoch 6")
    served = await cache_mod.cache_gate_node(_state(epoch=6, for_gate=True))
    assert (served["cache_decision"], served["tutor_response"]) == ("reuse", "answer for epoch 6")


@pytest.mark.asyncio
async def test_late_read_of_an_older_epoch_does_not_roll_the_token_back():
    key = "learner:alice:profile"
    invalidation.observe_dependency_tokens([{"key": key, "version": "6"}])

    await cache_mod.publish_dependency_version(key, "5")

    assert invalidation._MEM_DEPENDENCY_TOKENS[key] == "6"


@pytest.mark.asyncio
async def test_benchmark_request_never_publishes_a_mutation():
    key = "learner:alice:profile"
    invalidation.observe_dependency_tokens([{"key": key, "version": "5"}])
    state = _state(epoch=6)
    state["conversation_history_supplied"] = True
    state["benchmark_metadata"] = {"_benchmark_mode": "probe"}

    await nodes_mod.input_node(state)

    assert invalidation._MEM_DEPENDENCY_TOKENS[key] == "5"


def test_evidence_scope_is_per_learner_in_production_only():
    alice, bob = _state(user="alice"), _state(user="bob")
    assert retrieve_mod._evidence_scope(alice, "full") != retrieve_mod._evidence_scope(bob, "full")

    alice["benchmark_metadata"] = {"_benchmark_mode": "probe"}
    bob["benchmark_metadata"] = {"_benchmark_mode": "probe"}
    assert retrieve_mod._evidence_scope(alice, "full") == retrieve_mod._evidence_scope(bob, "full")


class _Gateway:
    _models = {"qwen": None}

    def __init__(self, payload):
        self.payload = payload

    async def execute_task(self, _task, _payload):
        return {"success": True, "data": json.dumps(self.payload)}


@pytest.mark.asyncio
@pytest.mark.parametrize("bad", [None, "high", float("nan"), True])
async def test_diagnosis_score_the_model_got_wrong_falls_back_to_the_default(monkeypatch, bad):
    payload = {"errors": [], "intent": "ask", "confidence": bad, "grammar_score": bad, "fluency_score": bad}

    async def gateway():
        return _Gateway(payload)

    monkeypatch.setattr(nodes_mod, "get_gateway", gateway)
    state = create_initial_state("um maybe this", "s1", learner_profile={"level": "B1"})

    result = await nodes_mod.diagnose_node(state)

    assert result["diagnosis_confidence"] == 0.9
    assert result["grammar_score"] == 0.8
    assert result["fluency_score"] == 0.8


@pytest.mark.parametrize("raw, expected", [(1.7, 1.0), (-0.2, 0.0), ("0.4", 0.4), (0.65, 0.65)])
def test_score_is_clamped_to_unit_range(raw, expected):
    assert nodes_mod._unit_score(raw, 0.9) == expected
