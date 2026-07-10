import hashlib
import logging
import time

import pytest

import api.services.trace_cag.nodes_v2 as nodes
import api.services.trace_cag.cache_utils as cache_mod


@pytest.mark.asyncio
async def test_cache_gate_reports_benchmark_evidence_mismatch(monkeypatch):
    query = "What verb collocates with decision?"
    level = "B1"
    profile = {"level": level}
    cache_key = hashlib.md5(f"{query.lower()}||{level}".encode()).hexdigest()
    entry = {
        "fingerprint": {
            "query_norm": query.lower(),
            "intent": "ask",
            "level": level,
            "root_concepts": ["collocation"],
            "session_turn": 0,
        },
        "profile_snapshot": profile,
        "response": "make",
        "retrieval_trace": [],
        "evidence_bundle": [],
        "execution_plan": {
            "intent": "ask",
            "benchmark_state": {
                "intent": "ask",
                "concepts": ["collocation"],
                "answer_target": "word",
                "evidence_hash": "old",
            },
        },
        "created_at": time.monotonic(),
        "ttl": 3600,
    }

    async def fake_get_cache_entry(key, _level, _now):
        return entry if key == cache_key else None

    async def no_candidates(_bucket):
        return []

    monkeypatch.setattr(cache_mod, "_get_cache_entry", fake_get_cache_entry)
    monkeypatch.setattr(cache_mod, "_get_bucket_candidate_keys", no_candidates)

    result = await nodes.cache_gate_node({
        "user_input": query,
        "learner_profile": profile,
        "conversation_history": [],
        "cache_policy": "on",
        "benchmark_task": "multihop_qa",
        "benchmark_metadata": {
            "_tracecag_state": {
                "intent": "ask",
                "concepts": ["collocation"],
                "answer_target": "word",
                "evidence_hash": "new",
            }
        },
    })

    assert result["cache_decision"] == "full"
    assert result["cache_gate_meta"]["pcc_passed"] is False
    assert "evidence_mismatch" in result["cache_gate_meta"]["reasons"]


@pytest.mark.asyncio
async def test_input_node_skips_redis_warning_when_benchmark_redis_disabled(
    monkeypatch,
    caplog,
):
    monkeypatch.setenv("BENCHMARK_REDIS_DISABLED", "true")
    caplog.set_level(logging.WARNING, logger="api.services.trace_cag.nodes_v2")

    result = await nodes.input_node({
        "user_input": "What verb collocates with decision?",
        "learner_profile": {"level": "B1"},
    })

    assert result["learner_profile"] == {"level": "B1"}
    assert "Redis unavailable" not in caplog.text
