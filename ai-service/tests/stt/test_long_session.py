import struct

import pytest

from api.services.stt.audio_ingest import HEADER, parse_audio_frame
from api.services.stt.config import STTConfig
from api.services.stt.metrics import STTMetrics
from api.services.stt.model_registry import STTModelRegistry
from api.services.stt.schemas import StartMessage
from api.services.stt.voice_session import VoiceSession
from tests.stt.fakes import FakePrimary, FakeVerifier


@pytest.mark.asyncio
async def test_ten_minute_stream_keeps_ring_and_queue_bounded(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        ring_buffer_seconds=1,
        audio_queue_max_frames=4,
        save_audio_for_debug=False,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    session = VoiceSession(
        StartMessage(session_id="long"), config, registry, STTMetrics()
    )

    pcm = b"\x00\x00" * 320
    # Exercise storage directly to keep this deterministic and fast while
    # representing 30,000 20 ms frames (10 minutes).
    for seq in range(30_000):
        frame = parse_audio_frame(HEADER.pack(1, 0, seq, seq * 20) + pcm)
        session.ring.append(frame.pcm16)
        session.writer.write(frame.pcm16)

    assert len(session.ring) == 16000 * 2
    assert max(path.stat().st_size for path in session.writer.paths) <= (
        config.temp_rotation_seconds * 16000 * 2
    )
    assert len(session.writer.paths) <= 3
    await session.stop()
    assert not list(tmp_path.glob("*.pcm"))
