from unittest.mock import AsyncMock

import pytest

from api.services.topic_chat_service import call_tracecag_with_retry


@pytest.mark.asyncio
async def test_call_tracecag_for_topic_uses_topic_prompt_and_disables_cache(monkeypatch):
    orchestrator = AsyncMock()
    orchestrator.process = AsyncMock(
        return_value={
            "tutor_response": "Here is your boarding pass.",
            "metadata": {"models_used": ["trace-cag_pipeline"]},
        }
    )
    monkeypatch.setattr(
        "api.services.orchestrator.get_orchestrator",
        AsyncMock(return_value=orchestrator),
    )

    await call_tracecag_with_retry(
        message="I need check in.",
        session_id="sess-1",
        user_id="u1",
        difficulty_level="A2",
        conversation_history=[],
        kg_seeds=["concept:travel.airport"],
        preferred_llm="trace-cag",
        topic_system_prompt="You are Sarah, an airport check-in agent.",
    )

    kwargs = orchestrator.process.await_args.kwargs
    assert kwargs["topic_system_prompt"] == "You are Sarah, an airport check-in agent."
    assert kwargs["cache_policy"] == "off"
