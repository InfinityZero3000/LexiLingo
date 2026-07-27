import pytest

from service.tracecag_service import TraceCAGRequest, TraceCAGService
from service.tracecag_service.adapters.memory import InMemoryTraceCAGAnalyzer


@pytest.mark.asyncio
async def test_memory_adapter_cache_miss_then_l0_reuse():
    service = TraceCAGService(InMemoryTraceCAGAnalyzer())
    request = TraceCAGRequest(
        user_input="Who founded AlphaSoft?",
        session_id="s1",
        learner_profile={"level": "B1"},
    )

    first = await service.analyze(request)
    second = await service.analyze(request)

    assert first.metadata["cache_hit"] is False
    assert first.metadata["cache_decision"] == "full"
    assert second.metadata["cache_hit"] is True
    assert second.metadata["cache_layer"] == "L0"
    assert second.metadata["cache_decision"] == "reuse"
    assert second.tutor_response == first.tutor_response


@pytest.mark.asyncio
async def test_memory_adapter_uses_l1_patch_for_state_compatible_near_hit():
    service = TraceCAGService(InMemoryTraceCAGAnalyzer())

    await service.analyze(
        TraceCAGRequest(
            user_input="Who founded AlphaSoft?",
            session_id="s1",
            learner_profile={"level": "B1"},
        )
    )
    response = await service.analyze(
        TraceCAGRequest(
            user_input="Who created AlphaSoft?",
            session_id="s1",
            learner_profile={"level": "B1"},
        )
    )

    assert response.metadata["cache_hit"] is True
    assert response.metadata["cache_layer"] == "L1"
    assert response.metadata["cache_decision"] == "patch"
    assert "State-compatible cache patch" in response.tutor_response


@pytest.mark.asyncio
async def test_memory_adapter_rejects_l1_when_profile_level_changes():
    service = TraceCAGService(InMemoryTraceCAGAnalyzer())

    await service.analyze(
        TraceCAGRequest(
            user_input="Who founded AlphaSoft?",
            session_id="s1",
            learner_profile={"level": "B1"},
        )
    )
    response = await service.analyze(
        TraceCAGRequest(
            user_input="Who created AlphaSoft?",
            session_id="s1",
            learner_profile={"level": "C1"},
        )
    )

    assert response.metadata["cache_hit"] is False
    assert response.metadata["cache_decision"] == "full"


@pytest.mark.asyncio
async def test_memory_adapter_respects_cache_policy_off():
    service = TraceCAGService(InMemoryTraceCAGAnalyzer())
    request = TraceCAGRequest(
        user_input="Who founded AlphaSoft?",
        session_id="s1",
        cache_policy="off",
    )

    first = await service.analyze(request)
    second = await service.analyze(request)

    assert first.metadata["cache_hit"] is False
    assert second.metadata["cache_hit"] is False
