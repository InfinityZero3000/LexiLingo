import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

import api.services.topic_chat_service as svc
from api.services.topic_chat_service import (
    call_tracecag_with_retry,
    stream_tracecag_topic_message,
)


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


# ─── _run_with_heartbeats ──────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_run_with_heartbeats_yields_heartbeat_then_result(monkeypatch):
    monkeypatch.setattr(svc, "HEARTBEAT_INTERVAL_S", 0.01)

    async def slow():
        await asyncio.sleep(0.05)
        return "done-value"

    items = [item async for item in svc._run_with_heartbeats(slow, timeout_s=1.0)]

    assert items[-1] == "done-value"
    assert any(isinstance(i, str) and "heartbeat" in i for i in items[:-1])


@pytest.mark.asyncio
async def test_run_with_heartbeats_raises_timeout(monkeypatch):
    monkeypatch.setattr(svc, "HEARTBEAT_INTERVAL_S", 0.01)

    async def never_done():
        await asyncio.sleep(10)

    with pytest.raises(asyncio.TimeoutError):
        async for _ in svc._run_with_heartbeats(never_done, timeout_s=0.05):
            pass


# ─── stream_tracecag_topic_message ─────────────────────────────────────────

def _quota():
    return SimpleNamespace(
        rpm_used=1, rpm_limit=60, rpd_used=1, rpd_limit=1000,
        tpm_used=10, tpm_limit=60000, tpd_used=10, tpd_limit=1000000,
    )


def _raw_state(**overrides):
    state = {"tutor_response": "", "diagnosis_errors": [], "user_input": "hello"}
    state.update(overrides)
    return state


def _repo():
    repo = MagicMock()
    repo.insert_messages_bulk = AsyncMock()
    repo.update_session_activity = AsyncMock()
    return repo


def _parse_sse(events: list[str]) -> list[tuple[str, dict]]:
    parsed = []
    for raw in events:
        lines = raw.strip("\n").split("\n")
        event_name = lines[0].split(":", 1)[1].strip()
        data = json.loads(lines[1].split(":", 1)[1].strip())
        parsed.append((event_name, data))
    return parsed


async def _run_stream(monkeypatch, **overrides):
    monkeypatch.setattr("api.core.audit_emitter.emit_ai_audit_event", AsyncMock())
    kwargs = dict(
        message="hello",
        session_id="s1",
        user_id="u1",
        difficulty_level="B1",
        conversation_history=[],
        kg_seeds=[],
        topic_system_prompt="You are Sarah.",
        repo=_repo(),
        quota=_quota(),
        start_time=0.0,
        request_id="r1",
    )
    kwargs.update(overrides)
    events = [chunk async for chunk in stream_tracecag_topic_message(**kwargs)]
    return _parse_sse(events), kwargs["repo"]


def _mock_streaming_tokens(monkeypatch, tokens, provider="groq", model="llama-3.1-8b-instant"):
    async def fake_stream_tokens(**kw):
        provider_info = kw.get("provider_info")
        if provider_info is not None:
            provider_info["provider"] = provider
            provider_info["model"] = model
        for tok in tokens:
            yield tok

    monkeypatch.setattr(
        "api.services.trace_cag.nodes_v2.build_generation_prompt",
        MagicMock(return_value=("system prompt", [{"role": "user", "content": "hi"}])),
    )
    monkeypatch.setattr("api.services.trace_cag.nodes_v2.stream_llm_tokens", fake_stream_tokens)


@pytest.mark.asyncio
async def test_stream_topic_message_primary_success(monkeypatch):
    orchestrator = MagicMock()
    orchestrator.pipeline.analyze_for_streaming = AsyncMock(return_value=_raw_state())
    monkeypatch.setattr(
        "api.services.orchestrator.get_orchestrator", AsyncMock(return_value=orchestrator)
    )
    _mock_streaming_tokens(monkeypatch, ["Hello", " there", "!"])

    events, repo = await _run_stream(monkeypatch)

    names = [n for n, _ in events]
    assert names[0] == "thinking"
    assert names.count("chunk") >= 1
    assert names[-1] == "done"

    done_data = events[-1][1]
    assert done_data["ai_response"] == "Hello there!"
    assert done_data["llm_metadata"]["model"] == "groq/llama-3.1-8b-instant"
    assert done_data["llm_metadata"]["fallback_used"] is False
    repo.insert_messages_bulk.assert_awaited_once()

    # Analyze called with the full quality-path params — nothing skipped.
    prep_kwargs = orchestrator.pipeline.analyze_for_streaming.await_args.kwargs
    assert prep_kwargs["retrieval_policy"] == "rapid"
    assert prep_kwargs["diagnosis_policy"] == "rules"
    assert prep_kwargs["topic_system_prompt"] == "You are Sarah."
    assert prep_kwargs["cache_policy"] == "off"


@pytest.mark.asyncio
async def test_stream_topic_message_primary_fails_then_degraded_retry_succeeds(monkeypatch):
    orchestrator = MagicMock()
    orchestrator.pipeline.analyze_for_streaming = AsyncMock(
        side_effect=[RuntimeError("primary failed"), _raw_state()]
    )
    monkeypatch.setattr(
        "api.services.orchestrator.get_orchestrator", AsyncMock(return_value=orchestrator)
    )
    _mock_streaming_tokens(monkeypatch, ["Retried", " reply"])

    events, repo = await _run_stream(monkeypatch)

    done_data = events[-1][1]
    assert done_data["ai_response"] == "Retried reply"
    assert done_data["llm_metadata"]["fallback_used"] is True
    assert done_data["llm_metadata"]["retry_mode"] == "trace-cag_degraded"
    assert orchestrator.pipeline.analyze_for_streaming.await_count == 2
    retry_kwargs = orchestrator.pipeline.analyze_for_streaming.await_args.kwargs
    assert retry_kwargs["conversation_history"] == []


@pytest.mark.asyncio
async def test_stream_topic_message_both_tiers_fail_falls_back_to_safe_response(monkeypatch):
    orchestrator = MagicMock()
    orchestrator.pipeline.analyze_for_streaming = AsyncMock(
        side_effect=[RuntimeError("primary failed"), RuntimeError("retry failed")]
    )
    monkeypatch.setattr(
        "api.services.orchestrator.get_orchestrator", AsyncMock(return_value=orchestrator)
    )

    events, repo = await _run_stream(monkeypatch)

    names = [n for n, _ in events]
    # Graceful degrade, not a hard error — the endpoint always returns a
    # readable turn, matching the JSON endpoint's existing contract.
    assert "error" not in names
    assert names[-1] == "done"
    done_data = events[-1][1]
    assert done_data["ai_response"] == svc.SAFE_FIXED_RESPONSE
    assert done_data["llm_metadata"]["model"] == "safe_fixed_response"
    repo.insert_messages_bulk.assert_awaited_once()
