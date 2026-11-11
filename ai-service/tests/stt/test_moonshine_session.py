import struct
from types import SimpleNamespace

import pytest

from api.services.stt.engines.moonshine import MoonshineSession
from api.services.stt.schemas import AudioSegment


class _SessionTranscriber:
    """Like the real one: every line spoken so far stays in `lines`."""

    MOONSHINE_FLAG_FORCE_UPDATE = 1

    def __init__(self):
        self.lines = []

    def add_audio(self, _samples, _rate):
        pass

    def update_transcription(self, _flags=0):
        return SimpleNamespace(
            lines=[SimpleNamespace(text=text) for text in self.lines]
        )


def _audio():
    return AudioSegment(pcm16=b"", start_ms=0, end_ms=100)


@pytest.mark.asyncio
async def test_finals_and_partials_cover_only_the_current_utterance():
    transcriber = _SessionTranscriber()
    session = MoonshineSession(transcriber, "en")
    chunk = struct.pack("<h", 1000) * 4800  # 300 ms, enough to emit a partial

    transcriber.lines = ["hello there"]
    first_partial = await session.push_audio(chunk, 0, 300)
    first = await session.finalize(_audio())

    transcriber.lines = ["hello there", "how are you"]
    second_partial = await session.push_audio(chunk, 300, 600)
    second = await session.finalize(_audio())

    assert first_partial.text == first.text == "hello there"
    assert second_partial.text == second.text == "how are you"


@pytest.mark.asyncio
async def test_a_utterance_split_into_several_lines_is_kept_whole():
    transcriber = _SessionTranscriber()
    session = MoonshineSession(transcriber, "en")
    await session.finalize(_audio())

    transcriber.lines = ["tell me", "a story"]
    assert (await session.finalize(_audio())).text == "tell me a story"
