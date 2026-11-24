"""Production L1 serves only a reworded copy of the same question, and only when switched on."""

import pytest

import api.services.trace_cag.cache_utils as cache_mod
import api.services.trace_cag.invalidation as invalidation
from api.core.redis_client import RedisClient
from api.services.trace_cag.l1_state_cache import L1Candidate, L1Request, decide_l1_reuse

from .test_kg_mastery_traversal import _DictRedis

QUESTION = "why do we use the present perfect here?"
REWORDED = "Please, why do we use the present perfect here?"
SHORT_WORD_CHANGED = "why do we use the present perfect there?"
ERROR = {"span": "x", "correction": "y", "type": "grammar", "explanation": "z"}


class _StatsRedis(_DictRedis):
    def __init__(self) -> None:
        super().__init__()
        self.stats: dict[str, int] = {}

    async def hincrby(self, _key, field, amount=1):
        self.stats[field] = self.stats.get(field, 0) + amount
        return self.stats[field]


@pytest.fixture
def redis(monkeypatch):
    monkeypatch.setattr(cache_mod.settings, "SECRET_KEY", "test-secret")
    monkeypatch.setattr(cache_mod.settings, "LEARNER_STATE_MODE", "off")
    fake = _StatsRedis()

    async def get_instance():
        return fake

    monkeypatch.setattr(RedisClient, "get_instance", get_instance)
    for store in (cache_mod._MEM_RESPONSE_CACHE, cache_mod._MEM_GRAPH_BUCKETS, cache_mod._MEM_BUCKET_VERSIONS):
        store.clear()
    invalidation.clear_reverse_index()
    return fake


def _mode(monkeypatch, mode):
    monkeypatch.setattr(cache_mod.settings, "TRACECAG_L1_MODE", mode)


def _state(text, *, intent="explain", freshness="stable", errors=()):
    return {
        "user_input": text,
        "session_id": "s",
        "user_id": "alice",
        "learner_profile": {"level": "B1"},
        "conversation_history": [],
        "cache_policy": "on",
        "diagnosis_confidence": 0.9,
        "diagnosis_intent": intent,
        "diagnosis_errors": list(errors),
        "diagnosis_root_causes": ["concept:grammar.present_perfect"] if errors else [],
        "kg_seed_concepts": ["concept:grammar.present_perfect"],
        "retrieval_trace": [{"item_id": "c1", "title": "t"}],
        "retrieval_meta": {"evidence_hash": "evidence:e1", "source_version": "evidence:e1", "freshness_class": freshness},
    }


async def _write(state, text="cached answer"):
    await cache_mod._write_cache_entry(state, text, "praise", state["diagnosis_errors"], 0.8, "", model_used="groq/x")


def _gate_state(text):
    state = _state(text)
    state.pop("retrieval_meta")
    return state


@pytest.mark.asyncio
async def test_off_never_looks_at_l1(redis, monkeypatch):
    _mode(monkeypatch, "off")
    await _write(_state(QUESTION))

    result = await cache_mod.cache_gate_node(_gate_state(REWORDED))

    assert result["cache_hit"] is False and not result.get("l1_shadow_response")


@pytest.mark.asyncio
async def test_shadow_generates_fresh_and_counts_the_comparison(redis, monkeypatch):
    _mode(monkeypatch, "shadow")
    await _write(_state(QUESTION), "the cached answer about the present perfect")

    gate = await cache_mod.cache_gate_node(_gate_state(REWORDED))
    assert gate["cache_hit"] is False and gate["cache_decision"] == "full"
    assert gate["l1_shadow_response"] == "the cached answer about the present perfect"

    await _write({**_state(REWORDED), **gate}, "a completely unrelated reply")

    assert redis.stats == {"compared": 1, "low_similarity": 1}


@pytest.mark.asyncio
async def test_on_serves_a_reworded_copy(redis, monkeypatch):
    _mode(monkeypatch, "on")
    await _write(_state(QUESTION))

    result = await cache_mod.cache_gate_node(_gate_state(REWORDED))

    assert (result["cache_decision"], result["cache_layer"]) == ("patch", "L1")
    assert result["tutor_response"] == "cached answer"


@pytest.mark.asyncio
async def test_on_refuses_when_one_short_word_differs(redis, monkeypatch):
    _mode(monkeypatch, "on")
    await _write(_state(QUESTION))

    result = await cache_mod.cache_gate_node(_gate_state(SHORT_WORD_CHANGED))

    assert result["cache_hit"] is False


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "overrides",
    [{"errors": [ERROR]}, {"intent": "correct"}, {"intent": "practice"}, {"freshness": "volatile"}],
)
async def test_on_refuses_entries_that_may_not_be_reused(redis, monkeypatch, overrides):
    _mode(monkeypatch, "on")
    await _write(_state(QUESTION, **overrides))

    result = await cache_mod.cache_gate_node(_gate_state(REWORDED))

    assert result["cache_hit"] is False


@pytest.mark.asyncio
async def test_audit_fields_do_not_become_required_and_l0_still_hits(redis, monkeypatch):
    _mode(monkeypatch, "off")
    await _write(_state(QUESTION))
    certificate = next(iter(cache_mod._MEM_RESPONSE_CACHE.values()))[1]["admissibility_certificate"]

    assert certificate["evidence_hash"] == "evidence:e1" and certificate["freshness_class"] == "stable"
    assert not {"evidence_hash", "source_version", "freshness_class"} & set(certificate["required_dimensions"])
    result = await cache_mod.cache_gate_node(_gate_state(QUESTION))
    assert (result["cache_decision"], result["cache_layer"]) == ("reuse", "L0")


@pytest.mark.asyncio
async def test_cache_hit_keeps_the_mastery_evidence(redis, monkeypatch):
    _mode(monkeypatch, "off")
    await _write(_state(QUESTION, errors=[ERROR]))

    result = await cache_mod.cache_gate_node(_gate_state(QUESTION))

    assert result["cache_decision"] == "reuse"
    assert result["diagnosis_root_causes"] == ["concept:grammar.present_perfect"]
    assert result["kg_seed_concepts"] == ["concept:grammar.present_perfect"]


def test_audit_version_on_one_side_is_not_drift():
    base = {
        "query_norm": "q", "intent": "ask", "level": "B1", "profile_epoch": 1, "session_turn": 0,
        "concepts": {"a"}, "answer_target": "person", "policy_version": "p", "kg_version": "k", "user_scope": "a",
    }
    bare = L1Candidate(**base, cache_key="k", created_at=100.0, ttl=3600)
    audited = L1Candidate(**base, cache_key="k", source_version="s1", freshness_class="stable", created_at=100.0, ttl=3600)
    request = L1Request(**base)

    assert decide_l1_reuse(request, audited, now=100.0).risk == decide_l1_reuse(request, bare, now=100.0).risk
