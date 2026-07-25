import asyncio
import struct

import pytest

from api.services.stt import duplex_turn


class FakeTTS:
    sample_rate = 16000

    async def stream(self, text):
        assert text == "Hello."
        yield b"\x01\x02\x03"


def test_take_fragment_prefers_sentence_boundary_then_length_limit():
    assert duplex_turn._take_fragment("Hello! Rest") == ("Hello!", "Rest")
    fragment, rest = duplex_turn._take_fragment(
        "one two three four five", max_chars=16
    )
    assert fragment == "one two three"
    assert rest == "four five"


@pytest.mark.parametrize(
    ("tokens", "visible"),
    [
        (["Safe ", "<thi", "nk>hidden", "</thi", "nk>Answer."], "Safe Answer."),
        (["Safe ", "<think>hidden"], "Safe "),
        (["Safe ", "<thi"], "Safe "),
    ],
)
def test_think_sanitizer_handles_split_markers_and_hidden_eof(tokens, visible):
    sanitizer = duplex_turn._ThinkSanitizer()
    output = "".join(sanitizer.feed(token) for token in tokens) + sanitizer.finish()
    assert output == visible
    assert "hidden" not in output


@pytest.mark.asyncio
async def test_hidden_reasoning_never_reaches_events_or_tts(monkeypatch):
    sent = []
    spoken = []

    async def llm(**_kwargs):
        for token in ("<thi", "nk>secret", "</think>", "Visible."):
            yield token

    class RecordingTTS:
        sample_rate = 16000

        async def stream(self, text):
            spoken.append(text)
            yield b"pcm"

    async def send_json(event):
        sent.append(event)

    async def send_bytes(_payload):
        pass

    monkeypatch.setattr(duplex_turn, "stream_llm_tokens", llm)
    await duplex_turn.DuplexTurn(send_json, send_bytes, RecordingTTS()).run(
        {"session_id": "s1", "turn_id": "t1", "text": "Hi"}, turn_seq=1
    )

    visible = " ".join(
        str(event.get("text", "")) for event in sent if isinstance(event, dict)
    )
    assert "secret" not in visible
    assert spoken == ["Visible."]


@pytest.mark.asyncio
async def test_duplex_turn_event_order_and_binary_header(monkeypatch):
    sent = []

    async def llm(**kwargs):
        assert kwargs["allow_gemini_fallback"] is False
        yield "Hello."

    async def send_json(event):
        sent.append(event)
        await asyncio.sleep(0)

    async def send_bytes(payload):
        sent.append(payload)

    monkeypatch.setattr(duplex_turn, "stream_llm_tokens", llm)
    await duplex_turn.DuplexTurn(send_json, send_bytes, FakeTTS()).run(
        {"session_id": "s1", "turn_id": "t1", "text": "Hi"}, turn_seq=7
    )

    kinds = [item["type"] if isinstance(item, dict) else "binary" for item in sent]
    assert kinds[:3] == ["turn_started", "llm.token", "sentence.final"]
    assert kinds.index("tts.audio.start") < kinds.index("binary") < kinds.index("tts.audio.end")
    assert kinds.index("tts.audio.end") < kinds.index("llm.done")
    assert kinds.index("llm.done") < kinds.index("turn.done")
    assert kinds.index("tts.audio.end") < kinds.index("turn.done")
    assert kinds[-1] == "turn.done"
    binary = next(item for item in sent if isinstance(item, bytes))
    version, kind, turn_seq, sentence_seq, audio_seq, payload_len = struct.unpack(
        ">BBIHII", binary[:16]
    )
    assert (version, kind, turn_seq, sentence_seq, audio_seq) == (1, 2, 7, 1, 0)
    assert payload_len == len(binary[16:]) == 3
    start = next(item for item in sent if isinstance(item, dict) and item["type"] == "tts.audio.start")
    assert (start["turn_seq"], start["sample_rate"], start["channels"], start["format"]) == (
        7,
        16000,
        1,
        "pcm16le",
    )


@pytest.mark.asyncio
async def test_duplex_turn_without_tts_emits_no_binary(monkeypatch):
    sent_json = []
    sent_binary = []

    async def llm(**_kwargs):
        yield "Hello."

    async def send_json(event):
        sent_json.append(event)

    async def send_bytes(payload):
        sent_binary.append(payload)

    monkeypatch.setattr(duplex_turn, "stream_llm_tokens", llm)
    await duplex_turn.DuplexTurn(send_json, send_bytes, FakeTTS()).run(
        {"session_id": "s1", "turn_id": "t1", "text": "Hi"},
        turn_seq=1,
        tts_enabled=False,
    )

    assert sent_binary == []
    assert all(not event["type"].startswith("tts.") for event in sent_json)
    assert sent_json[-1]["type"] == "turn.done"


@pytest.mark.asyncio
async def test_completed_turn_is_persisted_after_done(monkeypatch):
    sent = []
    persisted = []

    async def llm(**_kwargs):
        yield "Hello."

    async def persist(turn_id, user_text, assistant_text):
        persisted.append((turn_id, user_text, assistant_text))

    monkeypatch.setattr(duplex_turn, "stream_llm_tokens", llm)
    await duplex_turn.DuplexTurn(
        lambda event: _append(sent, event),
        lambda payload: _append(sent, payload),
        FakeTTS(),
        persist=persist,
    ).run({"session_id": "s1", "turn_id": "t1", "text": "Hi"}, turn_seq=1)

    assert persisted == [("t1", "Hi", "Hello.")]
    assert [event["type"] for event in sent if isinstance(event, dict)][-2:] == [
        "turn.persisted",
        "turn.done",
    ]


async def _append(items, item):
    items.append(item)


@pytest.mark.asyncio
async def test_duplex_turn_cancellation_emits_cancelled(monkeypatch):
    started = asyncio.Event()
    release = asyncio.Event()
    sent = []

    async def llm(**_kwargs):
        started.set()
        await release.wait()
        yield "late"

    async def send_json(event):
        sent.append(event)

    async def send_bytes(_payload):
        pass

    monkeypatch.setattr(duplex_turn, "stream_llm_tokens", llm)
    task = asyncio.create_task(
        duplex_turn.DuplexTurn(send_json, send_bytes, FakeTTS()).run(
            {"session_id": "s1", "turn_id": "t1", "text": "Hi"}, turn_seq=1
        )
    )
    await started.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task

    assert sent[-1]["type"] == "turn.cancelled"


@pytest.mark.asyncio
async def test_tts_failure_with_many_fragments_finishes_with_generic_error(monkeypatch):
    sent = []

    async def llm(**_kwargs):
        for index in range(5):
            yield f"Sentence {index}. "

    class FailingTTS:
        sample_rate = 16000

        async def stream(self, _text):
            raise RuntimeError("secret provider failure")
            yield b""  # pragma: no cover

    async def send_json(event):
        sent.append(event)

    async def send_bytes(_payload):
        pass

    monkeypatch.setattr(duplex_turn, "stream_llm_tokens", llm)
    await asyncio.wait_for(
        duplex_turn.DuplexTurn(send_json, send_bytes, FailingTTS()).run(
            {"session_id": "s1", "turn_id": "t1", "text": "Hi"}, turn_seq=2
        ),
        timeout=1,
    )

    assert sent[-1]["type"] == "voice.error"
    assert sent[-1]["message"] == "Voice turn failed"
    assert "secret" not in sent[-1]["message"]


@pytest.mark.asyncio
async def test_provider_capacity_error_is_retryable_server_busy(monkeypatch):
    sent = []

    async def busy(**kwargs):
        assert kwargs["allow_gemini_fallback"] is False
        raise duplex_turn.ProviderBusyError("busy")
        yield ""  # pragma: no cover

    async def send_json(event):
        sent.append(event)

    async def send_bytes(_payload):
        pass

    monkeypatch.setattr(duplex_turn, "stream_llm_tokens", busy)
    await duplex_turn.DuplexTurn(send_json, send_bytes, FakeTTS()).run(
        {"session_id": "s1", "turn_id": "t1", "text": "Hi"}, turn_seq=3
    )

    assert sent[-1]["type"] == "voice.error"
    assert sent[-1]["code"] == "SERVER_BUSY"
    assert sent[-1]["retryable"] is True
