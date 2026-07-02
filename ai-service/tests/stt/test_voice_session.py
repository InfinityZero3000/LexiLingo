import asyncio
import struct

import pytest

from api.services.stt.audio_ingest import HEADER, parse_audio_frame
from api.services.stt.config import STTConfig
from api.services.stt.metrics import STTMetrics
from api.services.stt.model_registry import STTModelRegistry
from api.services.stt.schemas import StartMessage
from api.services.stt.voice_session import VoiceSession
from tests.stt.fakes import FakePrimary, FakePrimarySession, FakeVerifier


class BlockingPrimarySession(FakePrimarySession):
    async def push_audio(self, pcm16, start_ms, end_ms):
        await asyncio.Event().wait()


class DelayedFinalSink:
    async def submit(self, event, result_sink):
        completion = asyncio.get_running_loop().create_future()

        async def deliver():
            await asyncio.sleep(0.01)
            await result_sink(
                {
                    "type": "trace_cag.response",
                    "session_id": event.session_id,
                    "utterance_id": event.utterance_id,
                    "tutor_response": "Hi",
                    "metadata": {},
                    "error": None,
                },
                True,
            )
            completion.set_result(None)

        asyncio.create_task(deliver())
        return completion


def _speech_frame(seq, samples=320):
    pcm = struct.pack("<h", 5000) * samples
    return parse_audio_frame(HEADER.pack(1, 0, seq, seq * 20) + pcm)


@pytest.mark.asyncio
async def test_voice_session_queue_is_bounded(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path), audio_queue_max_frames=1)
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="s1"), config, registry, STTMetrics()
    )
    assert session.enqueue(_speech_frame(0))
    assert not session.enqueue(_speech_frame(1))
    await session.stop()


@pytest.mark.asyncio
async def test_voice_session_emits_final_and_closes(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        min_speech_ms=20,
        min_silence_ms=20,
        verify_enabled=False,
    )
    primary_session = FakePrimarySession()
    registry = STTModelRegistry(
        config, primary=FakePrimary(primary_session), verifier=FakeVerifier()
    )
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="s1"), config, registry, STTMetrics()
    )
    await session.start_worker()
    session.enqueue(_speech_frame(0))
    silence = parse_audio_frame(HEADER.pack(1, 0, 1, 20) + b"\x00\x00" * 320)
    session.enqueue(silence)
    await asyncio.sleep(0.05)
    await session.stop()
    events = []
    while not session.event_queue.empty():
        events.append(session.event_queue.get_nowait())
    assert any(event["type"] == "stt.final" for event in events)
    assert events[-1]["type"] == "session_closed"
    final = next(event for event in events if event["type"] == "stt.final")
    assert final["utterance_id"] in session.transcripts.finals
    assert not session.transcripts.candidates


@pytest.mark.asyncio
async def test_stop_cancels_blocked_worker_when_queue_is_full(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        audio_queue_max_frames=1,
        session_stop_timeout_seconds=0.01,
    )
    primary_session = BlockingPrimarySession()
    registry = STTModelRegistry(
        config, primary=FakePrimary(primary_session), verifier=FakeVerifier()
    )
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="blocked"), config, registry, STTMetrics()
    )

    await session.start_worker()
    assert session.enqueue(_speech_frame(0))
    await asyncio.sleep(0)
    assert session.enqueue(_speech_frame(1))

    await asyncio.wait_for(session.stop(), timeout=0.5)

    assert session.closed
    assert primary_session.closed


@pytest.mark.asyncio
async def test_preserved_event_does_not_block_when_event_queue_is_full(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path))
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="events"), config, registry, STTMetrics()
    )
    for index in range(session.event_queue.maxsize):
        session.event_queue.put_nowait({"type": "stt.final", "index": index})

    await asyncio.wait_for(
        session.emit({"type": "session_closed"}, preserve=True),
        timeout=0.1,
    )

    assert session.event_queue.qsize() == session.event_queue.maxsize
    assert any(
        event["type"] == "session_closed"
        for event in list(session.event_queue._queue)
    )


@pytest.mark.asyncio
async def test_stop_waits_for_downstream_response_before_closing(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        min_speech_ms=20,
        min_silence_ms=20,
        verify_enabled=False,
        downstream_response_timeout_seconds=0.5,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="downstream"),
        config,
        registry,
        STTMetrics(),
        final_sink=DelayedFinalSink(),
    )
    await session.start_worker()
    session.enqueue(_speech_frame(0))
    silence = parse_audio_frame(HEADER.pack(1, 0, 1, 20) + b"\x00\x00" * 320)
    session.enqueue(silence)
    await asyncio.sleep(0.02)

    await session.stop()

    events = list(session.event_queue._queue)
    response_index = next(
        index for index, event in enumerate(events)
        if event["type"] == "trace_cag.response"
    )
    close_index = next(
        index for index, event in enumerate(events)
        if event["type"] == "session_closed"
    )
    assert response_index < close_index
    assert session.transcripts.responses


@pytest.mark.asyncio
async def test_stop_emits_downstream_timeout_before_closing(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        downstream_response_timeout_seconds=0.01,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="timeout"),
        config,
        registry,
        STTMetrics(),
    )
    completion = asyncio.get_running_loop().create_future()
    session._downstream_futures[completion] = "u1"

    await session.stop()

    events = list(session.event_queue._queue)
    assert [event["type"] for event in events[-2:]] == [
        "trace_cag.response",
        "session_closed",
    ]
    assert events[-2]["error"] == "TRACE-CAG response timed out"


@pytest.mark.asyncio
async def test_silence_frames_produce_no_final(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        min_speech_ms=20,
        min_silence_ms=20,
        verify_enabled=False,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="silent"), config, registry, STTMetrics()
    )
    await session.start_worker()
    for i in range(5):
        silence = parse_audio_frame(HEADER.pack(1, 0, i, i * 20) + b"\x00\x00" * 320)
        session.enqueue(silence)
    await asyncio.sleep(0.05)
    await session.stop()
    events = list(session.event_queue._queue)
    final_events = [e for e in events if e.get("type") == "stt.final"]
    assert not final_events


@pytest.mark.asyncio
async def test_metrics_records_time_to_first_partial(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        min_speech_ms=20,
        min_silence_ms=20,
        verify_enabled=False,
    )
    primary_session = FakePrimarySession()
    registry = STTModelRegistry(
        config, primary=FakePrimary(primary_session), verifier=FakeVerifier()
    )
    registry.status = "ready"
    metrics = STTMetrics()
    session = VoiceSession(
        StartMessage(session_id="partial-metrics"), config, registry, metrics
    )
    await session.start_worker()
    session.enqueue(_speech_frame(0))
    await asyncio.sleep(0.05)
    await session.stop()
    stats = metrics.latency_stats("stt_time_to_first_partial_ms")
    assert stats["count"] == 1
    assert stats["avg"] >= 0


@pytest.mark.asyncio
async def test_metrics_records_final_latency(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        min_speech_ms=20,
        min_silence_ms=20,
        verify_enabled=False,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    metrics = STTMetrics()
    session = VoiceSession(
        StartMessage(session_id="final-metrics"), config, registry, metrics
    )
    await session.start_worker()
    session.enqueue(_speech_frame(0))
    silence = parse_audio_frame(HEADER.pack(1, 0, 1, 20) + b"\x00\x00" * 320)
    session.enqueue(silence)
    await asyncio.sleep(0.05)
    await session.stop()
    stats = metrics.latency_stats("stt_final_latency_ms")
    assert stats["count"] >= 1
    assert stats["avg"] >= 0


@pytest.mark.asyncio
async def test_metrics_records_session_duration(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path))
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    metrics = STTMetrics()
    session = VoiceSession(
        StartMessage(session_id="duration-metrics"), config, registry, metrics
    )
    await session.start_worker()
    await asyncio.sleep(0.01)
    await session.stop()
    stats = metrics.latency_stats("stt_session_duration_s")
    assert stats["count"] == 1
    assert stats["avg"] >= 0.01


@pytest.mark.asyncio
async def test_stop_timeout_does_not_overwrite_completed_response(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        downstream_response_timeout_seconds=0.01,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="mixed"),
        config,
        registry,
        STTMetrics(),
    )
    await session.emit_downstream_response(
        {
            "type": "trace_cag.response",
            "session_id": "mixed",
            "utterance_id": "done",
            "tutor_response": "Success",
            "metadata": {},
            "error": None,
        }
    )
    done = asyncio.get_running_loop().create_future()
    done.set_result(None)
    pending = asyncio.get_running_loop().create_future()
    session._downstream_futures[done] = "done"
    session._downstream_futures[pending] = "pending"

    await session.stop()

    assert session.transcripts.responses["done"]["tutor_response"] == "Success"
    assert session.transcripts.responses["done"]["error"] is None
    assert session.transcripts.responses["pending"]["error"] == (
        "TRACE-CAG response timed out"
    )
