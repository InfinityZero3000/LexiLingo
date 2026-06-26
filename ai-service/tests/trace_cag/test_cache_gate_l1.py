"""Regression tests for TraceCAG cache-gate L1 near-hit routing."""

import hashlib
import time

import pytest

import api.services.trace_cag.nodes_v2 as nodes
import api.services.trace_cag.cache_utils as cache_mod


@pytest.mark.asyncio
async def test_cache_gate_l1_near_hit_accepts_cache_entry_dict(monkeypatch):
    """A true L1 near-hit should not runtime-check TypedDict with isinstance()."""
    user_input = "I go to school yesterday."
    candidate_input = "I went to school yesterday."
    level = "B1"
    profile = {"level": level}
    now = time.time()

    current_key = hashlib.md5(f"{user_input.lower()}||{level}".encode()).hexdigest()
    candidate_key = hashlib.md5(f"{candidate_input.lower()}||{level}".encode()).hexdigest()
    profile_epoch = nodes._profile_epoch(profile)
    bucket = nodes._build_graph_bucket(
        user_input,
        level,
        nodes._infer_intent_pre_diagnosis(user_input),
        profile_epoch,
        [],
    )
    entry = {
        "fingerprint": {
            "query_norm": candidate_input.lower(),
            "intent": "correct",
            "level": level,
            "root_concepts": nodes._extract_lightweight_graph_concepts(user_input),
            "session_turn": 0,
        },
        "graph_bucket": bucket,
        "profile_snapshot": profile,
        "response": "Cached feedback from a related past-tense turn.",
        "evidence_bundle": [],
        "retrieval_trace": [],
        "execution_plan": {"strategy": "feedback", "intent": "correct"},
        "diagnosis_errors": [],
        "grammar_score": 0.9,
        "fluency_score": 0.9,
        "vocabulary_level": level,
        "action_plan": [],
        "overall_score": 0.9,
        "created_at": now,
        "ttl": 3600,
    }

    async def fake_get_cache_entry(cache_key, _level, _now):
        if cache_key == current_key:
            return None
        if cache_key == candidate_key:
            return entry
        raise AssertionError(f"unexpected cache key: {cache_key}")

    async def fake_get_bucket_candidate_keys(_bucket):
        return [candidate_key] if _bucket == bucket else []

    monkeypatch.setattr(cache_mod, "_get_cache_entry", fake_get_cache_entry)
    monkeypatch.setattr(cache_mod, "_get_bucket_candidate_keys", fake_get_bucket_candidate_keys)

    result = await nodes.cache_gate_node(
        {
            "user_input": user_input,
            "session_id": "test-session",
            "learner_profile": profile,
            "conversation_history": [],
            "cache_policy": "on",
        }
    )

    assert result["cache_hit"] is True
    assert result["cache_layer"] == "L1"
    assert result["cache_decision"] in {"reuse", "patch"}


@pytest.mark.asyncio
async def test_cache_gate_l1_patches_safe_qa_paraphrase(monkeypatch):
    """SCAR-L1 should patch a state-compatible QA paraphrase."""
    user_input = "Who founded the company that makes the iPhone?"
    candidate_input = "Who was the founder of the corporation behind the iPhone?"
    level = "B1"
    profile = {"level": level}
    now = time.time()

    current_key = hashlib.md5(f"{user_input.lower()}||{level}".encode()).hexdigest()
    candidate_key = hashlib.md5(f"{candidate_input.lower()}||{level}".encode()).hexdigest()
    entry = {
        "fingerprint": {
            "query_norm": candidate_input.lower(),
            "intent": "ask",
            "level": level,
            "root_concepts": [],
            "session_turn": 0,
        },
        "graph_bucket": "test-bucket",
        "profile_snapshot": profile,
        "response": "Steve Jobs",
        "evidence_bundle": [],
        "retrieval_trace": [],
        "execution_plan": {"strategy": "feedback", "intent": "ask"},
        "diagnosis_errors": [],
        "grammar_score": 0.9,
        "fluency_score": 0.9,
        "vocabulary_level": level,
        "action_plan": [],
        "overall_score": 0.9,
        "created_at": now,
        "ttl": 3600,
    }

    async def fake_get_cache_entry(cache_key, _level, _now):
        if cache_key == current_key:
            return None
        if cache_key == candidate_key:
            return entry
        raise AssertionError(f"unexpected cache key: {cache_key}")

    async def fake_get_bucket_candidate_keys(_bucket):
        return [candidate_key]

    monkeypatch.setattr(cache_mod, "_get_cache_entry", fake_get_cache_entry)
    monkeypatch.setattr(cache_mod, "_get_bucket_candidate_keys", fake_get_bucket_candidate_keys)

    result = await nodes.cache_gate_node(
        {
            "user_input": user_input,
            "session_id": "test-session",
            "learner_profile": profile,
            "conversation_history": [],
            "cache_policy": "on",
        }
    )

    assert result["cache_hit"] is True
    assert result["cache_layer"] == "L1"
    assert result["cache_decision"] == "patch"


@pytest.mark.asyncio
async def test_cache_gate_l1_rejects_answer_target_shift(monkeypatch):
    """A near entity match with a changed answer target must fall through."""
    user_input = "In what year did the company behind the iPhone start?"
    candidate_input = "Who was the founder of the corporation behind the iPhone?"
    level = "B1"
    profile = {"level": level}
    now = time.time()

    current_key = hashlib.md5(f"{user_input.lower()}||{level}".encode()).hexdigest()
    candidate_key = hashlib.md5(f"{candidate_input.lower()}||{level}".encode()).hexdigest()
    entry = {
        "fingerprint": {
            "query_norm": candidate_input.lower(),
            "intent": "ask",
            "level": level,
            "root_concepts": [],
            "session_turn": 0,
        },
        "graph_bucket": "test-bucket",
        "profile_snapshot": profile,
        "response": "Steve Jobs",
        "evidence_bundle": [],
        "retrieval_trace": [],
        "execution_plan": {"strategy": "feedback", "intent": "ask"},
        "diagnosis_errors": [],
        "grammar_score": 0.9,
        "fluency_score": 0.9,
        "vocabulary_level": level,
        "action_plan": [],
        "overall_score": 0.9,
        "created_at": now,
        "ttl": 3600,
    }

    async def fake_get_cache_entry(cache_key, _level, _now):
        if cache_key == current_key:
            return None
        if cache_key == candidate_key:
            return entry
        raise AssertionError(f"unexpected cache key: {cache_key}")

    async def fake_get_bucket_candidate_keys(_bucket):
        return [candidate_key]

    monkeypatch.setattr(cache_mod, "_get_cache_entry", fake_get_cache_entry)
    monkeypatch.setattr(cache_mod, "_get_bucket_candidate_keys", fake_get_bucket_candidate_keys)

    result = await nodes.cache_gate_node(
        {
            "user_input": user_input,
            "session_id": "test-session",
            "learner_profile": profile,
            "conversation_history": [],
            "cache_policy": "on",
        }
    )

    assert result["cache_hit"] is False
    assert result["cache_layer"] == "none"
    assert result["cache_decision"] == "full"


@pytest.mark.asyncio
async def test_cache_gate_l0_rejects_reuse_across_native_languages(monkeypatch):
    """A Vietnamese-hint cache entry must not be reused for a Japanese learner
    asking the identical question at the identical level — same L0 cache_key,
    different native_language must still force a full pipeline run."""
    user_input = "She buy a car yesterday and is happy about it now."
    level = "B1"

    await cache_mod._write_cache_entry(
        state={
            "user_input": user_input,
            "learner_profile": {"level": level, "native_language": "Vietnamese"},
            "conversation_history": [],
        },
        response="Cached Vietnamese-hint response.",
        strategy="feedback",
        errors=[],
        overall_score=0.9,
    )

    result = await nodes.cache_gate_node(
        {
            "user_input": user_input,
            "session_id": "test-session",
            "learner_profile": {"level": level, "native_language": "Japanese"},
            "conversation_history": [],
            "cache_policy": "on",
        }
    )

    assert result["cache_hit"] is False
    assert result["cache_decision"] == "full"


@pytest.mark.asyncio
async def test_cache_gate_l1_rejects_near_hit_across_native_languages(monkeypatch):
    """An L1 near-hit candidate in a different native language must be
    rejected even when level/intent/concepts all match."""
    user_input = "I go to school yesterday."
    candidate_input = "I went to school yesterday."
    level = "B1"
    profile = {"level": level, "native_language": "Japanese"}
    now = time.time()

    current_key = hashlib.md5(f"{user_input.lower()}||{level}".encode()).hexdigest()
    candidate_key = hashlib.md5(f"{candidate_input.lower()}||{level}".encode()).hexdigest()
    profile_epoch = nodes._profile_epoch(profile)
    bucket = nodes._build_graph_bucket(
        user_input,
        level,
        nodes._infer_intent_pre_diagnosis(user_input),
        profile_epoch,
        [],
    )
    entry = {
        "fingerprint": {
            "query_norm": candidate_input.lower(),
            "intent": "correct",
            "level": level,
            "native_language": "Vietnamese",
            "root_concepts": nodes._extract_lightweight_graph_concepts(user_input),
            "session_turn": 0,
        },
        "graph_bucket": bucket,
        "profile_snapshot": {"level": level, "native_language": "Vietnamese"},
        "response": "Cached Vietnamese-hint feedback.",
        "evidence_bundle": [],
        "retrieval_trace": [],
        "execution_plan": {"strategy": "feedback", "intent": "correct"},
        "diagnosis_errors": [],
        "grammar_score": 0.9,
        "fluency_score": 0.9,
        "vocabulary_level": level,
        "action_plan": [],
        "overall_score": 0.9,
        "created_at": now,
        "ttl": 3600,
    }

    async def fake_get_cache_entry(cache_key, _level, _now):
        if cache_key == current_key:
            return None
        if cache_key == candidate_key:
            return entry
        raise AssertionError(f"unexpected cache key: {cache_key}")

    async def fake_get_bucket_candidate_keys(_bucket):
        return [candidate_key] if _bucket == bucket else []

    monkeypatch.setattr(cache_mod, "_get_cache_entry", fake_get_cache_entry)
    monkeypatch.setattr(cache_mod, "_get_bucket_candidate_keys", fake_get_bucket_candidate_keys)

    result = await nodes.cache_gate_node(
        {
            "user_input": user_input,
            "session_id": "test-session",
            "learner_profile": profile,
            "conversation_history": [],
            "cache_policy": "on",
        }
    )

    assert result["cache_hit"] is False
    assert result["cache_decision"] == "full"
