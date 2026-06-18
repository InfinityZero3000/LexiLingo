import asyncio

import pytest

from api.services.stt.schemas import FinalTranscriptEvent
from api.services.stt.trace_cag_adapter import TraceCAGAdapter, TraceCAGDispatcher


@pytest.mark.asyncio
async def test_trace_cag_adapter_accepts_only_final():
    adapter = TraceCAGAdapter()
    with pytest.raises(TypeError):
        await adapter.submit({"type": "stt.partial"})


@pytest.mark.asyncio
async def test_trace_cag_adapter_preserves_uncertainty():
    rows = []

    async def consumer(payload):
        rows.append(payload)

    adapter = TraceCAGAdapter(consumer)
    await adapter.submit(
        FinalTranscriptEvent(
            session_id="s1",
            utterance_id="u1",
            turn_id="t1",
            text="hello.",
            start_ms=0,
            end_ms=1000,
            confidence=0.6,
            confidence_source="test",
            source="moonshine_only",
            verified=False,
            uncertain=True,
            needs_confirmation=True,
        )
    )
    assert rows[0]["event_type"] == "stt.final"
    assert rows[0]["uncertain"] is True


@pytest.mark.asyncio
async def test_trace_cag_dispatcher_passes_final_metadata(monkeypatch):
    calls = []
    responses = []

    class FakePipeline:
        async def analyze(self, **kwargs):
            calls.append(kwargs)
            return {"tutor_response": "Hi", "metadata": {"path": "test"}}

    async def fake_get_trace_cag():
        return FakePipeline()

    monkeypatch.setattr(
        "api.services.trace_cag.graph.get_trace_cag",
        fake_get_trace_cag,
    )
    dispatcher = TraceCAGDispatcher()
    await dispatcher.start()
    event = FinalTranscriptEvent(
        session_id="s1",
        user_id="user-1",
        utterance_id="u1",
        turn_id="t1",
        text="hello.",
        start_ms=0,
        end_ms=1000,
        confidence=0.9,
        confidence_source="test",
        source="moonshine",
        verified=False,
        uncertain=False,
        needs_confirmation=False,
    )

    async def collect_response(payload, preserve):
        responses.append((payload, preserve))

    await dispatcher.submit(event, collect_response)
    await dispatcher.close()

    assert calls[0]["input_type"] == "voice"
    assert calls[0]["user_id"] == "user-1"
    assert calls[0]["stt_final"]["utterance_id"] == "u1"
    assert responses[0][0]["type"] == "trace_cag.response"
    assert responses[0][1] is True


@pytest.mark.asyncio
async def test_dispatcher_applies_backpressure_instead_of_dropping_final():
    dispatcher = TraceCAGDispatcher(max_queue_size=1)
    event = FinalTranscriptEvent(
        session_id="s1",
        utterance_id="u1",
        turn_id="t1",
        text="hello.",
        start_ms=0,
        end_ms=1000,
        confidence=0.9,
        confidence_source="test",
        source="moonshine",
        verified=False,
        uncertain=False,
        needs_confirmation=False,
    )
    await dispatcher.submit(event)
    blocked = asyncio.create_task(dispatcher.submit(event))
    await asyncio.sleep(0)

    assert not blocked.done()

    dispatcher.queue.get_nowait()
    await asyncio.wait_for(blocked, timeout=0.1)


@pytest.mark.asyncio
async def test_dispatcher_queue_admission_timeout_emits_error():
    responses = []

    async def collect_response(payload, preserve):
        responses.append(payload)

    dispatcher = TraceCAGDispatcher(
        max_queue_size=1,
        queue_admission_timeout_seconds=0.01,
    )
    event = FinalTranscriptEvent(
        session_id="s1",
        utterance_id="u1",
        turn_id="t1",
        text="hello.",
        start_ms=0,
        end_ms=1000,
        confidence=0.9,
        confidence_source="test",
        source="moonshine",
        verified=False,
        uncertain=False,
        needs_confirmation=False,
    )
    await dispatcher.submit(event)

    completion = await dispatcher.submit(event, collect_response)

    assert completion.done()
    assert responses[0]["error"] == "TRACE-CAG queue is busy"


@pytest.mark.asyncio
async def test_dispatcher_shutdown_cancels_blocked_pipeline(monkeypatch):
    class BlockingPipeline:
        async def analyze(self, **kwargs):
            await asyncio.Event().wait()

    async def fake_get_trace_cag():
        return BlockingPipeline()

    monkeypatch.setattr(
        "api.services.trace_cag.graph.get_trace_cag",
        fake_get_trace_cag,
    )
    dispatcher = TraceCAGDispatcher(
        max_queue_size=3,
        shutdown_timeout_seconds=0.01,
    )
    await dispatcher.start()
    event = FinalTranscriptEvent(
        session_id="s1",
        utterance_id="u1",
        turn_id="t1",
        text="hello.",
        start_ms=0,
        end_ms=1000,
        confidence=0.9,
        confidence_source="test",
        source="moonshine",
        verified=False,
        uncertain=False,
        needs_confirmation=False,
    )
    completions = [await dispatcher.submit(event) for _ in range(3)]
    await asyncio.sleep(0)

    await asyncio.wait_for(dispatcher.close(), timeout=0.2)
    assert all(completion.done() for completion in completions)


@pytest.mark.asyncio
async def test_dispatcher_emits_error_response_when_pipeline_fails(monkeypatch):
    class FailingPipeline:
        async def analyze(self, **kwargs):
            raise RuntimeError("boom")

    async def fake_get_trace_cag():
        return FailingPipeline()

    monkeypatch.setattr(
        "api.services.trace_cag.graph.get_trace_cag",
        fake_get_trace_cag,
    )
    responses = []

    async def collect_response(payload, preserve):
        responses.append(payload)

    dispatcher = TraceCAGDispatcher()
    await dispatcher.start()
    event = FinalTranscriptEvent(
        session_id="s1",
        utterance_id="u1",
        turn_id="t1",
        text="hello.",
        start_ms=0,
        end_ms=1000,
        confidence=0.9,
        confidence_source="test",
        source="moonshine",
        verified=False,
        uncertain=False,
        needs_confirmation=False,
    )

    completion = await dispatcher.submit(event, collect_response)
    await completion
    await dispatcher.close()

    assert responses[0]["error"] == "TRACE-CAG response failed"
