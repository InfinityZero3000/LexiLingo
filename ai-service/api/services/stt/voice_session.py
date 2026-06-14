"""Orchestration for one bounded realtime voice session."""

from __future__ import annotations

import asyncio
import time
from contextlib import suppress
from uuid import uuid4

from api.services.stt.audio_ingest import AudioFrame
from api.services.stt.config import STTConfig
from api.services.stt.ring_buffer import AudioRingBuffer
from api.services.stt.schemas import (
    AudioSegment,
    CandidateTranscriptEvent,
    PartialTranscriptEvent,
    StartMessage,
)
from api.services.stt.sentence_finalizer import SentenceFinalizer
from api.services.stt.temp_audio_writer import TempAudioWriter
from api.services.stt.transcript_state import TranscriptState


class VoiceSession:
    def __init__(
        self, start: StartMessage, config: STTConfig, registry, metrics, final_sink=None
    ):
        self.start = start
        self.config = config
        self.registry = registry
        self.metrics = metrics
        self.final_sink = final_sink
        self.input_queue: asyncio.Queue[AudioFrame | None] = asyncio.Queue(
            maxsize=config.audio_queue_max_frames
        )
        self.event_queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=100)
        self.ring = AudioRingBuffer(config.ring_buffer_seconds * 16000 * 2)
        self.writer = TempAudioWriter(
            config.temp_dir,
            start.session_id,
            max_file_bytes=config.temp_rotation_seconds * 16000 * 2,
        )
        self.vad = registry.create_vad()
        self.transcripts = TranscriptState()
        self.last_seq = -1
        self.last_ack_seq = -1
        self.last_activity = time.monotonic()
        self.started_at = self.last_activity
        self.disconnected_at = None
        self.closed = False
        self._task = None
        self._primary = None
        self._segment = bytearray()
        self._segment_start_ms = 0
        self._clock_ms = 0
        self._finalizer = SentenceFinalizer(config, registry)
        self._downstream_futures: dict[asyncio.Future, str] = {}

    async def start_worker(self) -> None:
        self._primary = await self.registry.create_primary_session(self.start.language)
        self._task = asyncio.create_task(
            self._run(), name=f"stt-{self.start.session_id}"
        )

    def enqueue(self, frame: AudioFrame) -> bool:
        if self.closed or self.input_queue.full():
            self.metrics.increment("stt_dropped_frames")
            return False
        self.input_queue.put_nowait(frame)
        self.last_seq = frame.seq
        self.last_ack_seq = frame.seq
        self.last_activity = time.monotonic()
        return True

    async def emit(self, event: dict, preserve: bool = False) -> None:
        if self.event_queue.full():
            if not preserve:
                self.metrics.increment("stt_dropped_partials")
                return
            retained = []
            while not self.event_queue.empty():
                item = self.event_queue.get_nowait()
                if item.get("type") != "stt.partial":
                    retained.append(item)
            capacity = max(0, self.event_queue.maxsize - 1)
            dropped = max(0, len(retained) - capacity)
            if dropped:
                self.metrics.increment("stt_dropped_preserved_events", dropped)
            for item in retained[-capacity:] if capacity else []:
                self.event_queue.put_nowait(item)
        self.event_queue.put_nowait(event)

    async def _run(self) -> None:
        try:
            while True:
                frame = await self.input_queue.get()
                if frame is None:
                    break
                await self._process(frame)
            await self._flush()
        finally:
            if self._primary:
                await self._primary.close()

    async def _process(self, frame: AudioFrame) -> None:
        start_ms = self._clock_ms
        self._clock_ms += frame.duration_ms
        self.ring.append(frame.pcm16)
        self.writer.write(frame.pcm16)
        partial = await self._primary.push_audio(frame.pcm16, start_ms, self._clock_ms)
        if partial:
            event = PartialTranscriptEvent(
                session_id=self.start.session_id,
                text=partial.text,
                start_ms=self._segment_start_ms,
                end_ms=self._clock_ms,
                confidence=partial.confidence,
                source=partial.source,
            )
            self.transcripts.set_partial(event)
            await self.emit(event.model_dump())
        vad_event = self.vad.process(frame.pcm16, frame.duration_ms)
        if vad_event.speech_started:
            pre_roll_bytes = self.config.pre_roll_ms * 16000 * 2 // 1000
            self._segment = bytearray(self.ring.getvalue()[-pre_roll_bytes:])
            self._segment_start_ms = max(0, self._clock_ms - self.config.pre_roll_ms)
        elif self.vad.in_speech:
            self._segment.extend(frame.pcm16)
        if vad_event.speech_ended:
            await self._finalize_segment()

    async def _finalize_segment(self) -> None:
        if not self._segment:
            return
        audio = AudioSegment(
            pcm16=bytes(self._segment),
            start_ms=self._segment_start_ms,
            end_ms=max(self._segment_start_ms + 1, self._clock_ms),
        )
        primary = await self._primary.finalize(audio)
        if primary.text.strip():
            utterance_id = f"utt_{uuid4().hex[:12]}"
            candidate = CandidateTranscriptEvent(
                session_id=self.start.session_id,
                utterance_id=utterance_id,
                text=primary.text,
                start_ms=audio.start_ms,
                end_ms=audio.end_ms,
                confidence=primary.confidence,
                source=primary.source,
            )
            self.transcripts.add_candidate(candidate)
            if self.config.emit_candidate_events:
                await self.emit(candidate.model_dump(), preserve=True)
            final = await self._finalizer.finalize(
                self.start.session_id,
                f"turn_{uuid4().hex[:12]}",
                self.start.use_case,
                self.start.language,
                audio,
                primary,
                utterance_id,
                self.start.user_id,
            )
            self.transcripts.add_final(final)
            await self.emit(final.model_dump(), preserve=True)
            if self.final_sink:
                completion = await self.final_sink.submit(
                    final, self.emit_downstream_response
                )
                self._downstream_futures[completion] = final.utterance_id
                completion.add_done_callback(self._downstream_futures.pop)
            self.metrics.increment("stt_number_of_segments")
        self._segment.clear()

    async def _flush(self) -> None:
        if self._segment:
            await self._finalize_segment()

    async def stop(self, reason: str = "client_stop") -> None:
        if self.closed:
            return
        self.closed = True
        if self._task:
            try:
                self.input_queue.put_nowait(None)
            except asyncio.QueueFull:
                self.input_queue.get_nowait()
                self.metrics.increment("stt_dropped_frames")
                self.input_queue.put_nowait(None)
            with suppress(asyncio.TimeoutError):
                await asyncio.wait_for(
                    asyncio.shield(self._task),
                    timeout=self.config.session_stop_timeout_seconds,
                )
            if not self._task.done():
                self._task.cancel()
                with suppress(asyncio.CancelledError):
                    await self._task
        elif self._primary:
            await self._primary.close()
        if self._downstream_futures:
            pending = tuple(self._downstream_futures.items())
            group = asyncio.gather(
                *(completion for completion, _ in pending),
                return_exceptions=True,
            )
            try:
                await asyncio.wait_for(
                    asyncio.shield(group),
                    timeout=self.config.downstream_response_timeout_seconds,
                )
            except asyncio.TimeoutError:
                self.metrics.increment("stt_downstream_response_timeouts")
                for completion, utterance_id in pending:
                    if completion.done():
                        continue
                    completion.cancel()
                    await self.emit_downstream_response(
                        {
                            "type": "trace_cag.response",
                            "session_id": self.start.session_id,
                            "utterance_id": utterance_id,
                            "tutor_response": None,
                            "metadata": {},
                            "error": "TRACE-CAG response timed out",
                        }
                    )
                await asyncio.gather(group, return_exceptions=True)
        self.writer.close(delete=not self.config.save_audio_for_debug)
        await self.emit(
            {
                "type": "session_closed",
                "session_id": self.start.session_id,
                "reason": reason,
            },
            preserve=True,
        )

    async def emit_downstream_response(
        self, event: dict, preserve: bool = True
    ) -> None:
        self.transcripts.add_response(event)
        await self.emit(event, preserve=preserve)

    def replay_snapshot(self) -> tuple[list[dict], list[dict]]:
        retained = []
        while not self.event_queue.empty():
            event = self.event_queue.get_nowait()
            if event.get("type") not in {"stt.final", "trace_cag.response"}:
                retained.append(event)
        for event in retained:
            self.event_queue.put_nowait(event)
        finals = [event.model_dump() for event in self.transcripts.finals.values()]
        responses = [
            dict(event) for event in self.transcripts.responses.values()
        ]
        return finals, responses
