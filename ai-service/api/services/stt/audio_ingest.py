"""Binary audio frame parsing and sequence validation."""

from __future__ import annotations

import struct
from dataclasses import dataclass

from api.services.stt.errors import STTErrorCode, STTProtocolError

HEADER = struct.Struct(">BBIQ")


@dataclass(frozen=True)
class AudioFrame:
    version: int
    flags: int
    seq: int
    client_ts_ms: int
    pcm16: bytes
    duration_ms: int


class SequenceStatus:
    ACCEPTED = "accepted"
    DUPLICATE = "duplicate"
    GAP = "gap"


def parse_audio_frame(
    data: bytes, sample_rate: int = 16000, max_ms: int = 250
) -> AudioFrame:
    if len(data) <= HEADER.size:
        raise STTProtocolError(STTErrorCode.INVALID_FRAME, "Missing PCM payload")
    version, flags, seq, client_ts_ms = HEADER.unpack_from(data)
    payload = data[HEADER.size :]
    if version != 1 or len(payload) % 2:
        raise STTProtocolError(
            STTErrorCode.INVALID_FRAME, "Invalid frame version or PCM16 payload"
        )
    duration_ms = len(payload) * 1000 // (sample_rate * 2)
    if duration_ms <= 0 or duration_ms > max_ms:
        raise STTProtocolError(
            STTErrorCode.INVALID_FRAME, "Audio frame duration is out of range"
        )
    return AudioFrame(version, flags, seq, client_ts_ms, payload, duration_ms)


def classify_sequence(last_seq: int, seq: int) -> tuple[str, int]:
    if seq <= last_seq:
        return SequenceStatus.DUPLICATE, 0
    missing = max(0, seq - last_seq - 1)
    return (SequenceStatus.GAP if missing else SequenceStatus.ACCEPTED), missing
