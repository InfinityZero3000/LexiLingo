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
    monkeypatch.setenv("TRACECAG_BENCHMARK_FAIL_ON_PROVIDER_ERROR", "false")
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


@pytest.mark.asyncio
async def test_benchmark_response_fails_instead_of_using_fallback_in_strict_run(monkeypatch):
    monkeypatch.setenv("TRACECAG_BENCHMARK_FAIL_ON_PROVIDER_ERROR", "true")
    monkeypatch.setattr(qa_generation, "_benchmark_provider_order", lambda: [])
    state = _state()
    state.update(
        {
            "user_input": "Was Seed Page founded in Khazan?",
            "retrieved_context": "[Seed Page] Seed Page mentions Bridge Target.",
            "generation_policy": "auto",
            "cache_policy": "off",
            "retrieval_trace": [],
        }
    )

    with pytest.raises(RuntimeError, match="Primary benchmark provider returned no response"):
        await _generate_benchmark_qa_response(state, time.time())


def test_ircot_gate_uses_context_coverage_not_the_answer_key():
    """The gold `supporting_titles` this gate was written against are never
    passed to the pipeline at runtime, so every support-coverage branch was
    dead and selection collapsed to a question-shape guess. Selection must key
    off entities the question names but the retrieved context never mentions —
    the same signal, without reading the answer key."""
    from api.services.trace_cag.benchmark.qa_generation import _ircot_should_run

    state = {
        "benchmark_task": "multihop_qa",
        "benchmark_metadata": {
            "_benchmark_mode": "tracecag_rapid",
            "context_docs": [
                {"item_id": f"d{i}", "title": f"Doc {i}", "text": "x"} for i in range(10)
            ],
            "source_id": "q1",
        },
    }
    question = "Who wrote These Boots Are Made for Walkin?"

    missing_hop, meta = _ircot_should_run(
        question, "[Nancy Sinatra] Nancy Sinatra recorded the song.", state
    )
    assert missing_hop is True
    assert meta["reason"] == "uncovered_question_entity"
    assert meta["uncovered_entities"]

    covered, meta = _ircot_should_run(
        question, "[These Boots Are Made for Walkin] Written by Lee Hazlewood.", state
    )
    assert covered is False, "a second retrieval buys nothing when the hop is already present"
    assert meta["uncovered_entities"] == []


def test_ircot_skips_the_reason_call_when_nothing_is_left_to_retrieve():
    """IRCoT's second retrieval can only help by adding a passage not already in
    context. With the evidence budget at 9-10 of a 10-document pool that set is
    usually empty — 41 of 53 reason calls in the n=64 run came back with
    `no_bridge_passages`, i.e. an LLM call spent retrieving nothing."""
    from api.services.trace_cag.benchmark.qa_generation import _ircot_should_run

    docs = [{"item_id": f"d{i}", "title": f"Doc {i}", "text": "x"} for i in range(3)]
    state = {
        "benchmark_task": "multihop_qa",
        "benchmark_metadata": {"_benchmark_mode": "tracecag_rapid", "context_docs": docs, "source_id": "q1"},
    }
    question = "Which director of Doc 1 also made Doc 2?"

    everything_selected = "\n".join(f"[Doc {i}] x" for i in range(3))
    ran, meta = _ircot_should_run(question, everything_selected, state)
    assert ran is False
    assert meta["reason"] == "no_unselected_candidates"
    assert meta["unselected_docs"] == 0

    # One passage still outside the window: this early skip must not fire, so
    # the remaining (question-shape / coverage) branches get to decide.
    partial = "\n".join(f"[Doc {i}] x" for i in range(2))
    _ran, meta = _ircot_should_run(question, partial, state)
    assert meta["unselected_docs"] == 1
    assert meta["reason"] != "no_unselected_candidates"


@pytest.mark.asyncio
async def test_answer_grounded_only_in_the_ircot_passage_survives_postprocessing(monkeypatch):
    """IRCoT appends a passage to `truncated_context`, but the grounding check,
    the low-quality gate and the cache write all read `clean_context`, which
    never saw it. An answer that only the added passage supports was therefore
    judged ungrounded and rewritten away — IRCoT retrieved the hop and the
    postprocessor threw it out."""
    monkeypatch.setenv("TRACECAG_BENCHMARK_FAIL_ON_PROVIDER_ERROR", "false")

    async def fake_reason_call(messages, max_tokens, *, estimated_tokens=96):
        return "Bridge Target", "groq/qwen"

    monkeypatch.setattr(qa_generation, "_groq_chat_with_retry", fake_reason_call)
    monkeypatch.setattr(qa_generation, "_benchmark_provider_order", lambda: [])
    monkeypatch.setattr(
        qa_generation, "_generate_extractive_qa_response", lambda q, ctx: "Khazan"
    )

    seen: dict[str, str] = {}

    def spy_postprocess(question, response, context, **kwargs):
        seen["context"] = context
        return response

    monkeypatch.setattr(qa_generation, "_postprocess_benchmark_qa_answer", spy_postprocess)

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

    await _generate_benchmark_qa_response(state, time.time())

    assert "Khazan" in seen["context"], "grounding must see the passage IRCoT added"
    assert "Seed Page mentions Bridge Target" in seen["context"], (
        "and must not lose the original context: the augmented string is re-capped "
        "with the bridge block first, so it drops the tail of what came before"
    )
