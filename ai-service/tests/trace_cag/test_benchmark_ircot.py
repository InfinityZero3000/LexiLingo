import time

import pytest

from api.services.trace_cag.benchmark import qa_generation
from api.services.trace_cag.benchmark.qa_generation import (
    _generate_benchmark_qa_response,
    _ircot_augment,
    _ircot_pick_bridge_passages,
    _ircot_should_run,
)


def _state(question_docs=None, supporting_titles=None):
    docs = question_docs or [
        {"title": "Seed Page", "text": "Seed Page mentions Bridge Target."},
        {"title": "Bridge Target", "text": "Bridge Target was founded in Khazan."},
    ]
    return {
        "benchmark_task": "multihop_qa",
        "benchmark_metadata": {
            "context_docs": docs,
            "supporting_titles": supporting_titles or ["Seed Page", "Bridge Target"],
        },
    }


def test_ircot_gate_skips_yes_no_by_default(monkeypatch):
    monkeypatch.delenv("TRACECAG_BENCHMARK_IRCOT_SELECTIVE", raising=False)
    monkeypatch.delenv("TRACECAG_IRCOT_SKIP_YES_NO", raising=False)

    selected, meta = _ircot_should_run(
        "Was the director of Seed Page born in Bridge Target?",
        "[Seed Page] Seed Page mentions Bridge Target.",
        _state(),
    )

    assert selected is False
    assert meta["reason"] == "skip_yes_no"
    assert meta["question_type"] == "yes_no"


def test_ircot_gate_skips_single_support_samples(monkeypatch):
    monkeypatch.delenv("TRACECAG_BENCHMARK_IRCOT_SELECTIVE", raising=False)

    selected, meta = _ircot_should_run(
        "Who founded Bridge Target?",
        "[Bridge Target] Bridge Target was founded in Khazan.",
        _state(supporting_titles=["Bridge Target"]),
    )

    assert selected is False
    assert meta["reason"] == "skip_single_support"


def test_ircot_gate_selects_bridge_multihop(monkeypatch):
    monkeypatch.delenv("TRACECAG_BENCHMARK_IRCOT_SELECTIVE", raising=False)

    selected, meta = _ircot_should_run(
        "What city founded the organization that Seed Page mentions?",
        "[Seed Page] Seed Page mentions Bridge Target.",
        _state(),
    )

    assert selected is True
    assert meta["reason"] in {"missing_support_bridge", "support_titles_multihop", "question_shape_multihop"}
    assert meta["support_coverage"] < 1.0


def test_ircot_bridge_selection_prefers_entity_title_and_excludes_existing():
    docs = [
        {"title": "Seed Page", "text": "Seed Page mentions Bridge Target."},
        {"title": "Distractor", "text": "Bridge Target is mentioned in passing."},
        {"title": "Bridge Target", "text": "Bridge Target was founded in Khazan."},
    ]

    picked = _ircot_pick_bridge_passages("Bridge Target", docs, {"seed page"}, k=2)

    assert [doc["title"] for doc in picked] == ["Bridge Target", "Distractor"]


@pytest.mark.asyncio
async def test_ircot_augment_returns_contract_telemetry(monkeypatch):
    async def fake_reason_call(messages, max_tokens, *, estimated_tokens=96):
        return "Bridge Target", "groq/qwen/qwen3-32b"

    monkeypatch.setattr(qa_generation, "_groq_chat_with_retry", fake_reason_call)

    context, hint, meta = await _ircot_augment(
        "What city founded the organization that Seed Page mentions?",
        "[Seed Page] Seed Page mentions Bridge Target.",
        _state(),
    )

    assert context.startswith("[Bridge Target]")
    assert hint == "Bridge Target"
    assert meta["bridge_entity"] == "Bridge Target"
    assert meta["reason_model"] == "groq/qwen/qwen3-32b"
    assert meta["added_titles"] == ["Bridge Target"]
    assert meta["contract"]["passes"] is True
    assert isinstance(meta["reason_latency_ms"], int)


@pytest.mark.asyncio
async def test_benchmark_response_exposes_ircot_metadata_and_reason_model(monkeypatch):
    async def fake_reason_call(messages, max_tokens, *, estimated_tokens=96):
        return "Bridge Target", "groq/qwen/qwen3-32b"

    monkeypatch.setattr(qa_generation, "_groq_chat_with_retry", fake_reason_call)
    monkeypatch.setattr(qa_generation, "_benchmark_provider_order", lambda: [])

    state = _state()
    state.update(
        {
            "user_input": "What city founded the organization that Seed Page mentions?",
            "retrieved_context": "[Seed Page] Seed Page mentions Bridge Target.",
            "generation_policy": "auto",
            "cache_policy": "off",
            "retrieval_trace": [],
        }
    )

    result = await _generate_benchmark_qa_response(state, time.time())

    ircot_meta = result["retrieval_meta"]["ircot"]
    assert ircot_meta["selected"] is True
    assert ircot_meta["bridge_entity"] == "Bridge Target"
    assert "ircot_reason:groq/qwen/qwen3-32b" in result["models_used"]
    assert result["models_used"][-1] == "extractive_fallback"
