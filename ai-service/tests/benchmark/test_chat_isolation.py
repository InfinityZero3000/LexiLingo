"""Chat-persona changes must never reach the benchmark paths.

The QA benchmark (benchmark_task = multihop_qa / retrieval_qa) bypasses
diagnosis and answers through its own generator. Tutor wording, learner profile
and memory belong to chat only; these tests fail if a prompt builder is ever
called on a benchmark turn.
"""

import pytest

from api.services.trace_cag import generate as gen
from api.services.trace_cag import nodes_v2


@pytest.mark.parametrize("task", ["multihop_qa", "retrieval_qa"])
@pytest.mark.asyncio
async def test_benchmark_generation_never_builds_a_tutor_prompt(monkeypatch, task):
    def forbidden(*_args, **_kwargs):
        raise AssertionError("tutor prompt builder reached on a benchmark turn")

    for name in ("_build_base_system_prompt", "_errors_directive", "_is_asking",
                 "_personalization_hint", "build_generation_prompt"):
        monkeypatch.setattr(gen, name, forbidden)

    async def benchmark_answer(state, _start):
        return {"tutor_response": "stub", "models_used": ["bench"]}

    monkeypatch.setattr(gen, "_generate_benchmark_qa_response", benchmark_answer)

    result = await gen.generate_node(
        {
            "benchmark_task": task,
            "user_input": "Who directed the film?",
            # chat-only fields that must be ignored here
            "learner_profile": {"level": "A1", "profile_brief": "First name: X",
                                "memory": "Interests: golf"},
            "diagnosis_errors": [{"span": "a", "correction": "b"}],
        }
    )

    assert result == {"tutor_response": "stub", "models_used": ["bench"]}


@pytest.mark.parametrize("task", ["multihop_qa", "retrieval_qa"])
@pytest.mark.asyncio
async def test_benchmark_diagnosis_skips_the_llm_and_extracts_no_facts(monkeypatch, task):
    async def no_gateway():
        raise AssertionError("diagnosis called an LLM on a benchmark turn")

    monkeypatch.setattr(nodes_v2, "get_gateway", no_gateway)

    result = await nodes_v2.diagnose_node(
        {"benchmark_task": task, "user_input": "My name is Thang, I am a nurse."}
    )

    assert result["models_used"] == ["benchmark_bypass"]
    assert result["diagnosis_errors"] == []
    assert "diagnosis_facts" not in result


def test_benchmark_state_has_no_chat_profile_by_default():
    from api.services.trace_cag.state import create_initial_state

    state = create_initial_state("q", "s", "u", benchmark_task="multihop_qa")

    profile = state["learner_profile"]
    assert "profile_brief" not in profile and "memory" not in profile
