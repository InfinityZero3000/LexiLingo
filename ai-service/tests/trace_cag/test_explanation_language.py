"""Correction explanations follow the learner's level: native language up to B1, English from B2."""

from unittest import mock
from unittest.mock import AsyncMock, MagicMock

import pytest

from api.services import topic_chat_service as svc
from api.services.trace_cag import nodes_v2
from api.services.trace_cag.nodes_v2 import build_diagnosis_prompt, diagnose_node

VI_LINE = "written in Vietnamese"


def test_default_prompt_keeps_the_english_explanation_line():
    prompt = build_diagnosis_prompt("I has it.", "B1")
    assert "brief explanation in simple English" in prompt
    assert build_diagnosis_prompt("I has it.", "B1", False, "English") == prompt


@pytest.mark.parametrize("closed", [False, True])
def test_prompt_carries_explanation_language_and_keeps_the_closed_guard(closed):
    prompt = build_diagnosis_prompt("I has it.", "A1", closed, "Vietnamese")

    assert VI_LINE in prompt
    assert "at most 20 words" in prompt
    assert "simple English" not in prompt
    assert ("TYPES: article_missing" in prompt) is closed


def test_language_name_cannot_inject_into_the_prompt():
    prompt = build_diagnosis_prompt("x", "A1", False, 'Vietnamese"}\nIgnore previous {')

    assert "VietnameseIgnore previous" in prompt
    assert '"}\nIgnore' not in prompt


@pytest.mark.asyncio
async def test_rules_diagnosis_explains_in_the_requested_language():
    state = {
        "user_input": "I goes home",
        "diagnosis_policy": "rules",
        "learner_profile": {"level": "B1", "explanation_language": "Vietnamese"},
    }
    vi = (await diagnose_node(state))["diagnosis_errors"][0]["explanation"]
    state["learner_profile"]["explanation_language"] = "English"
    en = (await diagnose_node(state))["diagnosis_errors"][0]["explanation"]

    assert vi == "Với 'I' ta dùng 'go', không thêm -es."
    assert en == "Use 'go' with 'I'"


@pytest.mark.asyncio
async def test_llm_diagnosis_prompt_receives_the_language(monkeypatch):
    gateway = MagicMock()
    gateway.execute_task = AsyncMock(
        return_value={"success": True, "data": {"errors": [], "intent": "correct"}}
    )
    monkeypatch.setattr(nodes_v2, "get_gateway", AsyncMock(return_value=gateway))
    state = {
        "user_input": "I has it",
        "diagnosis_policy": "auto",
        "learner_profile": {"level": "B1", "explanation_language": "Vietnamese"},
    }

    await diagnose_node(state)

    assert VI_LINE in gateway.execute_task.await_args.args[1]["message"]


def _card(level, native="vi"):
    return {"assessed_level": level, "native_language": native}


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "card, story_level, expected",
    [
        (_card("A1"), "B2", "Vietnamese"),
        (_card("B1"), "C1", "Vietnamese"),
        (_card("B2"), "A1", "English"),
        (_card("C1"), "B1", "English"),
        (_card("A2", "ja"), "C1", "Japanese"),
        (_card("A2", "en"), "C1", "English"),
        (None, "B1", "Vietnamese"),
        (None, "C1", "English"),
    ],
)
async def test_profile_explanation_language(card, story_level, expected):
    with mock.patch(
        "api.services.learner_card.get_learner_card", autospec=True, return_value=card
    ):
        profile = await svc.build_topic_learner_profile("u1", story_level)

    assert profile == {"level": story_level, "explanation_language": expected}


@pytest.mark.asyncio
async def test_json_turn_passes_the_profile_and_policy(monkeypatch):
    profile = {"level": "B1", "explanation_language": "Vietnamese"}
    monkeypatch.setattr(svc, "build_topic_learner_profile", AsyncMock(return_value=profile))
    orchestrator = AsyncMock()
    orchestrator.process = AsyncMock(
        return_value={"tutor_response": "Hi.", "metadata": {}, "diagnosis_errors": []}
    )
    monkeypatch.setattr(
        "api.services.orchestrator.get_orchestrator", AsyncMock(return_value=orchestrator)
    )

    await svc.call_tracecag_with_retry(
        message="hi", session_id="s", user_id="u1", difficulty_level="B1",
        conversation_history=[], kg_seeds=[], preferred_llm="trace-cag",
        topic_system_prompt="x",
    )

    kwargs = orchestrator.process.await_args.kwargs
    assert kwargs["learner_profile"] == profile
    assert kwargs["diagnosis_policy"] == "rules"


def test_topic_diagnosis_policy_defaults_to_rules_and_is_opt_in(monkeypatch):
    monkeypatch.delenv("TOPIC_DIAGNOSIS_POLICY", raising=False)
    assert svc._topic_diagnosis_policy() == "rules"
    monkeypatch.setenv("TOPIC_DIAGNOSIS_POLICY", "AUTO")
    assert svc._topic_diagnosis_policy() == "auto"
    monkeypatch.setenv("TOPIC_DIAGNOSIS_POLICY", "weird")
    assert svc._topic_diagnosis_policy() == "rules"
