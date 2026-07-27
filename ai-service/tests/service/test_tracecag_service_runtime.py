import asyncio

import pytest

from service.tracecag_service import (
    TraceCAGRequest,
    TraceCAGResponse,
    TraceCAGService,
    TraceCAGServiceConfig,
)


class DictAnalyzer:
    async def analyze(self, request: TraceCAGRequest):
        return {
            "tutor_response": f"handled:{request.user_input}",
            "metadata": {"path": "slow", "cache_hit": False},
        }


class SlowAnalyzer:
    async def analyze(self, request: TraceCAGRequest):
        await asyncio.sleep(0.05)
        return TraceCAGResponse(tutor_response="too late")


@pytest.mark.asyncio
async def test_runtime_normalizes_mapping_response():
    service = TraceCAGService(DictAnalyzer())

    response = await service.analyze_text("hello", session_id="s1")

    assert response.tutor_response == "handled:hello"
    assert response.metadata["path"] == "slow"
    assert response.metadata["service"]["adapter"] == "DictAnalyzer"
    assert response.metadata["request"]["session_id"] == "s1"


@pytest.mark.asyncio
async def test_runtime_returns_validation_error_without_calling_adapter():
    service = TraceCAGService(DictAnalyzer())

    response = await service.analyze(TraceCAGRequest(user_input="", session_id="s1"))

    assert response.error == "user_input is required"
    assert response.metadata["path"] == "error"
    assert response.metadata["error_type"] == "validation"


@pytest.mark.asyncio
async def test_runtime_timeout_is_returned_as_response():
    service = TraceCAGService(
        SlowAnalyzer(),
        TraceCAGServiceConfig(timeout_seconds=0.001),
    )

    response = await service.analyze_text("hello", session_id="s1")

    assert response.error == "TRACE-CAG service timed out"
    assert response.metadata["error_type"] == "timeout"


@pytest.mark.asyncio
async def test_analyze_many_uses_service_contract():
    service = TraceCAGService(DictAnalyzer(), TraceCAGServiceConfig(max_concurrency=2))
    requests = [
        TraceCAGRequest(user_input="one", session_id="s1"),
        TraceCAGRequest(user_input="two", session_id="s2"),
    ]

    responses = await service.analyze_many(requests)

    assert [item.tutor_response for item in responses] == ["handled:one", "handled:two"]
