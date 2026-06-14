import struct

import pytest

from api.services.stt.audio_ingest import (
    HEADER,
    SequenceStatus,
    classify_sequence,
    parse_audio_frame,
)
from api.services.stt.errors import STTProtocolError


def test_binary_frame_parses_bound_metadata():
    pcm = b"\x00\x00" * 320
    frame = parse_audio_frame(HEADER.pack(1, 0, 7, 1234) + pcm)
    assert frame.seq == 7
    assert frame.client_ts_ms == 1234
    assert frame.duration_ms == 20


def test_invalid_frame_is_rejected():
    with pytest.raises(STTProtocolError):
        parse_audio_frame(struct.pack(">BBIQ", 2, 0, 0, 0) + b"\x00\x00")


def test_sequence_classification():
    assert classify_sequence(4, 5) == (SequenceStatus.ACCEPTED, 0)
    assert classify_sequence(4, 4) == (SequenceStatus.DUPLICATE, 0)
    assert classify_sequence(4, 7) == (SequenceStatus.GAP, 2)
