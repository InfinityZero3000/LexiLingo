"""Minimal STT-final → LLM → PCM duplex turn."""

from __future__ import annotations

import asyncio
import logging
import struct
from collections.abc import Awaitable, Callable

from api.services.stt.streaming_tts import StreamingTTS, get_streaming_tts
from api.services.trace_cag.generate import ProviderBusyError, stream_llm_tokens

JsonSink = Callable[[dict], Awaitable[None]]
BinarySink = Callable[[bytes], Awaitable[None]]
PersistSink = Callable[[str, str, str], Awaitable[None]]
logger = logging.getLogger(__name__)


class DuplexTurn:
    def __init__(
        self,
        send_json: JsonSink,
        send_bytes: BinarySink,
        tts: StreamingTTS | None = None,
        persist: PersistSink | None = None,
    ) -> None:
        self._send_json = send_json
        self._send_bytes = send_bytes
        self._tts = tts or get_streaming_tts()
        self._persist = persist

    async def run(
        self,
        final: dict,
        *,
        turn_seq: int,
        tts_enabled: bool = True,
    ) -> None:
        session_id = str(final["session_id"])
        turn_id = str(final["turn_id"])
        text = str(final["text"])
        common = {"session_id": session_id, "turn_id": turn_id, "turn_seq": turn_seq}
        await self._send_json({"type": "turn_started", **common})
        try:
            response = await self._run_pipeline(text, common, tts_enabled)
            await self._send_json({"type": "llm.done", **common})
            if self._persist:
                try:
                    await self._persist(turn_id, text, response)
                    await self._send_json({"type": "turn.persisted", **common})
                except Exception:
                    logger.exception(
                        "Voice persistence failed session=%s turn=%s",
                        session_id,
                        turn_id,
                    )
                    await self._send_json(
                        {
                            "type": "voice.error",
                            "code": "PERSISTENCE_FAILED",
                            "message": "Voice turn could not be saved",
                            **common,
                        }
                    )
                    return
            await self._send_json(
                {
                    "type": "turn.done",
                    "persistence_status": "persisted" if self._persist else "skipped",
                    **common,
                }
            )
        except asyncio.CancelledError:
            await self._send_json({"type": "turn.cancelled", **common})
            raise
        except ProviderBusyError:
            await self._send_json(
                {
                    "type": "voice.error",
                    "code": "SERVER_BUSY",
                    "message": "Voice service is busy; retry shortly",
                    "retryable": True,
                    **common,
                }
            )
        except Exception:
            logger.exception("Duplex turn failed session=%s turn=%s", session_id, turn_id)
            await self._send_json(
                {
                    "type": "voice.error",
                    "code": "TURN_FAILED",
                    "message": "Voice turn failed",
                    **common,
                }
            )

    async def _run_pipeline(
        self, text: str, common: dict, tts_enabled: bool
    ) -> str:
        fragments: asyncio.Queue[tuple[int, str] | None] = asyncio.Queue(
            maxsize=2 if tts_enabled else 0
        )
        try:
            async with asyncio.TaskGroup() as tasks:
                producer = tasks.create_task(
                    self._produce_fragments(text, common, fragments)
                )
                if tts_enabled:
                    tasks.create_task(self._consume_fragments(fragments, common))
        except* ProviderBusyError as errors:
            raise ProviderBusyError("Voice provider capacity exhausted") from errors
        return producer.result()

    async def _produce_fragments(
        self,
        text: str,
        common: dict,
        fragments: asyncio.Queue[tuple[int, str] | None],
    ) -> str:
        buffer = ""
        response = ""
        sanitizer = _ThinkSanitizer()
        sentence_seq = 0
        async for raw_token in stream_llm_tokens(
            system_prompt=(
                "You are Lexi, a concise English tutor. Reply naturally in 1-2 "
                "short sentences and do not reveal internal reasoning."
            ),
            messages=[{"role": "user", "content": text}],
            user_input=text,
            max_tokens=96,
            allow_gemini_fallback=False,
        ):
            token = sanitizer.feed(raw_token)
            if not token:
                continue
            response += token
            await self._send_json({"type": "llm.token", "text": token, **common})
            buffer += token
            fragment, buffer = _take_fragment(buffer)
            if fragment:
                sentence_seq += 1
                await self._emit_fragment(sentence_seq, fragment, common, fragments)
        buffer += sanitizer.finish()
        if buffer.strip():
            sentence_seq += 1
            await self._emit_fragment(sentence_seq, buffer.strip(), common, fragments)
        await fragments.put(None)
        return response.strip()

    async def _emit_fragment(
        self,
        sentence_seq: int,
        fragment: str,
        common: dict,
        fragments: asyncio.Queue[tuple[int, str] | None],
    ) -> None:
        await self._send_json(
            {
                "type": "sentence.final",
                "sentence_seq": sentence_seq,
                "text": fragment,
                **common,
            }
        )
        await fragments.put((sentence_seq, fragment))

    async def _consume_fragments(
        self,
        fragments: asyncio.Queue[tuple[int, str] | None],
        common: dict,
    ) -> None:
        audio_seq = 0
        while (fragment := await fragments.get()) is not None:
            sentence_seq, text = fragment
            audio_seq = await self._speak(sentence_seq, text, audio_seq, common)

    async def _speak(
        self,
        sentence_seq: int,
        text: str,
        audio_seq: int,
        common: dict,
    ) -> int:
        await self._send_json(
            {
                "type": "tts.audio.start",
                "sentence_seq": sentence_seq,
                "sample_rate": self._tts.sample_rate,
                "channels": 1,
                "format": "pcm16le",
                **common,
            }
        )
        async for pcm in self._tts.stream(text):
            for offset in range(0, len(pcm), 4096):
                payload = pcm[offset : offset + 4096]
                header = struct.pack(
                    ">BBIHII",
                    1,
                    2,
                    common["turn_seq"],
                    sentence_seq,
                    audio_seq,
                    len(payload),
                )
                await self._send_bytes(header + payload)
                audio_seq += 1
        await self._send_json(
            {"type": "tts.audio.end", "sentence_seq": sentence_seq, **common}
        )
        return audio_seq


def _take_fragment(buffer: str, max_chars: int = 48) -> tuple[str | None, str]:
    for index, char in enumerate(buffer):
        if char in ".!?" and (index + 1 == len(buffer) or buffer[index + 1].isspace()):
            return buffer[: index + 1].strip(), buffer[index + 1 :].lstrip()
    if len(buffer) < max_chars:
        return None, buffer
    cut = buffer.rfind(" ", 0, max_chars + 1)
    cut = cut if cut >= 8 else max_chars
    return buffer[:cut].strip(), buffer[cut:].lstrip()


class _ThinkSanitizer:
    _start = "<think>"
    _end = "</think>"

    def __init__(self) -> None:
        self._buffer = ""
        self._hidden = False

    def feed(self, token: str) -> str:
        self._buffer += token
        output = ""
        while self._buffer:
            marker = self._end if self._hidden else self._start
            index = self._buffer.find(marker)
            if index >= 0:
                if not self._hidden:
                    output += self._buffer[:index]
                self._buffer = self._buffer[index + len(marker) :]
                self._hidden = not self._hidden
                continue
            keep = _marker_prefix_length(self._buffer, marker)
            if not self._hidden:
                output += self._buffer[:-keep] if keep else self._buffer
            self._buffer = self._buffer[-keep:] if keep else ""
            break
        return output

    def finish(self) -> str:
        if self._hidden or self._buffer in {
            self._start[:index] for index in range(1, len(self._start))
        }:
            self._buffer = ""
            return ""
        output, self._buffer = self._buffer, ""
        return output


def _marker_prefix_length(value: str, marker: str) -> int:
    return max(
        (
            size
            for size in range(1, min(len(value), len(marker) - 1) + 1)
            if value.endswith(marker[:size])
        ),
        default=0,
    )
