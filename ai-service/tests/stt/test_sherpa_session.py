import struct

import pytest

from api.services.stt.engines.sherpa import SherpaSession
from api.services.stt.schemas import AudioSegment


class _AccumulatingStream:
    """Like a real transducer stream: its text only ever grows."""

    def __init__(self, words):
        self._words = words
        self.text = ""

    def accept_waveform(self, _rate, _samples):
        if self._words:
            self.text = f"{self.text} {self._words.pop(0)}".strip()

    def input_finished(self):
        pass


class _Recognizer:
    def __init__(self, words):
        self._words = list(words)
        self.streams = 0

    def create_stream(self):
        self.streams += 1
        return _AccumulatingStream(self._words)

    def is_ready(self, _stream):
        return False

    def decode_stream(self, _stream):
        pass

    def get_result(self, stream):
        return stream.text


def _audio():
    return AudioSegment(pcm16=b"", start_ms=0, end_ms=100)


@pytest.mark.asyncio
async def test_each_utterance_starts_from_a_clean_stream():
    recognizer = _Recognizer(["hello", "world"])
    session = SherpaSession(recognizer, "en")
    chunk = struct.pack("<h", 1000) * 160

    await session.push_audio(chunk, 0, 10)
    first = await session.finalize(_audio())
    await session.push_audio(chunk, 100, 110)
    second = await session.finalize(_audio())

    assert first.text == "hello"
    assert second.text == "world"
    assert recognizer.streams == 3
