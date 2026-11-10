"""Every cache artifact belongs to one learner: bucket keys, PCC and the anonymous bypass."""


import pytest

import api.services.trace_cag.cache_utils as cache_mod
from api.core.redis_client import RedisClient
from api.services.trace_cag.l1_state_cache import CERTIFICATE_SCHEMA_VERSION, L1Request, decide_l1_reuse

from .test_kg_mastery_traversal import _DictRedis

QUESTION = "Who founded the company that makes the iPhone?"
PARAPHRASE = "Who was the founder of the corporation behind the iPhone?"
HINTS = {
    "intent": "ask",
    "concepts": ["iphone", "founder"],
    "answer_target": "person",
    "evidence_hash": "ev1",
    "source_version": "src1",
    "freshness_class": "static",
    "patchable_slots": ["query", "concepts"],
}


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


def _state(user_id, text, *, hints=HINTS):
    state = {
        "user_input": text,
        "session_id": "s",
        "learner_profile": {"level": "B1"},
        "conversation_history": [],
        "cache_policy": "on",
        "retrieval_trace": [{"item_id": "apple", "title": "Apple Inc."}],
        "benchmark_metadata": {"_tracecag_state": dict(hints)} if hints else {},
    }
    if user_id:
        state["user_id"] = user_id
    return state


async def _write(user_id, text, *, hints=HINTS):
    await cache_mod._write_cache_entry(_state(user_id, text, hints=hints), "Steve Jobs", "qa", [], 1.0, "", model_used="groq/x")


def _decide(**overrides):
    base = {
        "query_norm": "q", "intent": "ask", "level": "B1", "profile_epoch": 1, "session_turn": 0,
        "concepts": {"a"}, "answer_target": "person", "policy_version": "p", "kg_version": "k",
    }
    request = L1Request(**{**base, "user_scope": "a"})
    candidate = cache_mod.L1Candidate(**{**base, "cache_key": "k", "user_scope": "a", "created_at": 100.0, "ttl": 3600})
    from dataclasses import replace

    return decide_l1_reuse(replace(request, **overrides.get("request", {})), replace(candidate, **overrides.get("candidate", {})), now=100.0)


def test_pcc_rejects_other_users_candidate():
    assert _decide().decision == "reuse"
    decision = _decide(candidate={"user_scope": "b"})
    assert decision.decision == "full" and decision.safe_to_reuse is False
    assert "mismatch:user_scope" in decision.reasons
    anonymous = _decide(candidate={"user_scope": ""})
    assert anonymous.safe_to_reuse is False and "mismatch:user_scope" in anonymous.reasons


def test_bucket_aliases_are_disjoint_across_users():
    args = (QUESTION, "B1", "ask", 1, [])
    a = cache_mod._build_l1_bucket_aliases(*args, user_scope="a")
    b = cache_mod._build_l1_bucket_aliases(*args, user_scope="b")
    assert len(a) > 1 and len(b) == len(a)
    assert not set(a) & set(b)
    assert cache_mod._build_graph_bucket(*args, user_scope="a") != cache_mod._build_graph_bucket(*args, user_scope="b")


def test_user_scope_is_keyword_required():
    with pytest.raises(TypeError):
        cache_mod._build_graph_bucket(QUESTION, "B1", "ask", 1, [])
    with pytest.raises(TypeError):
        cache_mod._build_l1_bucket_aliases(QUESTION, "B1", "ask", 1, [])


@pytest.mark.asyncio
@pytest.mark.parametrize("text", [QUESTION, PARAPHRASE])
async def test_two_users_same_question_get_no_cache(text):
    await _write("alice", QUESTION)
    assert cache_mod._MEM_RESPONSE_CACHE

    result = await cache_mod.cache_gate_node(_state("bob", text))

    assert result["cache_hit"] is False
    assert result["cache_decision"] == "full"
    assert result.get("cache_layer", "none") == "none"


@pytest.mark.asyncio
async def test_pcc_blocks_another_users_entry_even_when_pooled_into_the_bucket():
    await _write("alice", QUESTION)
    alice_key = next(iter(cache_mod._MEM_RESPONSE_CACHE))
    state = _state("bob", PARAPHRASE)
    epoch = cache_mod._profile_epoch(state["learner_profile"])
    bob_buckets = cache_mod._build_l1_bucket_aliases(
        PARAPHRASE, "B1", "ask", epoch, [], user_scope=cache_mod._user_cache_scope(state),
    )
    for bucket in bob_buckets:
        cache_mod._register_graph_bucket(bucket, alice_key, profile_epoch=epoch)

    result = await cache_mod.cache_gate_node(state)

    assert result["cache_hit"] is False
    assert "mismatch:user_scope" in result["cache_gate_meta"]["reasons"]


@pytest.mark.asyncio
async def test_same_user_reuses_l0_and_patches_l1():
    await _write("alice", QUESTION)

    exact = await cache_mod.cache_gate_node(_state("alice", QUESTION))
    assert (exact["cache_decision"], exact["cache_layer"]) == ("reuse", "L0")

    near = await cache_mod.cache_gate_node(_state("alice", PARAPHRASE))
    assert (near["cache_decision"], near["cache_layer"]) == ("patch", "L1")
    assert near["tutor_response"] == "Steve Jobs"


@pytest.mark.asyncio
async def test_production_entry_never_patches():
    def prod_state(text):
        # stable enough to be promoted to L1, so the read side has a candidate and fails for the right reason
        state = _state("alice", text, hints=None)
        state.update(diagnosis_confidence=0.9, kg_seed_concepts=["concept:company_founder"])
        return state

    await cache_mod._write_cache_entry(prod_state(QUESTION), "Steve Jobs", "qa", [], 1.0, "", model_used="groq/x")
    entry = next(iter(cache_mod._MEM_RESPONSE_CACHE.values()))[1]
    assert entry["admissibility_certificate"]["patchable_slots"] == []
    assert cache_mod._MEM_GRAPH_BUCKETS

    near = await cache_mod.cache_gate_node(prod_state(PARAPHRASE))

    assert near["cache_hit"] is False and near["cache_decision"] == "full"
    assert "patch_slots_not_declared" in near["cache_gate_meta"]["reasons"]


@pytest.mark.asyncio
async def test_anonymous_request_bypasses_cache_and_writes_nothing():
    await _write(None, QUESTION)
    assert not cache_mod._MEM_RESPONSE_CACHE and not cache_mod._MEM_GRAPH_BUCKETS

    result = await cache_mod.cache_gate_node(_state(None, QUESTION))

    assert result["cache_hit"] is False and result["cache_decision"] == "full"
    assert result["cache_gate_meta"]["reasons"] == ["no_user_cache_scope"]


@pytest.mark.asyncio
async def test_certificate_records_schema4_and_scope():
    await _write("alice", QUESTION)
    certificate = next(iter(cache_mod._MEM_RESPONSE_CACHE.values()))[1]["admissibility_certificate"]
    assert CERTIFICATE_SCHEMA_VERSION == 4
    assert certificate["schema_version"] == 4
    assert certificate["user_scope"] == cache_mod._user_cache_scope({"user_id": "alice"})


@pytest.mark.asyncio
async def test_schema3_entry_is_ignored():
    await _write("alice", QUESTION)
    entry = next(iter(cache_mod._MEM_RESPONSE_CACHE.values()))[1]
    entry["admissibility_certificate"]["schema_version"] = 3
    key = next(iter(cache_mod._MEM_RESPONSE_CACHE))
    redis = await RedisClient.get_instance()
    import json

    await redis.set(f"v1:resp:{key}", json.dumps(entry))

    result = await cache_mod.cache_gate_node(_state("alice", QUESTION))

    assert result["cache_hit"] is False and result["cache_decision"] == "full"
    assert "unsupported_certificate_schema" in result["cache_gate_meta"]["reasons"]
