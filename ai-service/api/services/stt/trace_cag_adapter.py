"""Final-only boundary between realtime STT and TRACE-CAG consumers."""

from __future__ import annotations

import asyncio
import logging
from typing import Awaitable, Callable

from api.services.stt.schemas import FinalTranscriptEvent

logger = logging.getLogger(__name__)


class TraceCAGAdapter:
    def __init__(self, consumer: Callable[[dict], Awaitable[None]] | None = None):
        self.consumer = consumer

    async def submit(self, event: FinalTranscriptEvent) -> None:
        if not isinstance(event, FinalTranscriptEvent):
            raise TypeError("TRACE-CAG accepts only FinalTranscriptEvent")
        if self.consumer:
            await self.consumer(
                {
                    "event_type": event.type,
                    "session_id": event.session_id,
                    "user_id": event.user_id,
                    "turn_id": event.turn_id,
                    "utterance_id": event.utterance_id,
                    "text": event.text,
                    "final_text": event.text,
                    "language": event.language,
                    "confidence": event.confidence,
                    "source": event.source,
                    "verified": event.verified,
                    "uncertain": event.uncertain,
                    "needs_confirmation": event.needs_confirmation,
                    "segments": [
                        {
                            "text": event.text,
                            "start_ms": event.start_ms,
                            "end_ms": event.end_ms,
                            "confidence": event.confidence,
                            "source": event.source,
                            "verified": event.verified,
                        }
                    ],
                    "created_at": event.created_at,
                }
            )


class TraceCAGDispatcher:
    def __init__(
        self,
        max_queue_size: int = 100,
        queue_admission_timeout_seconds: float = 1,
        processing_timeout_seconds: float = 30,
        shutdown_timeout_seconds: float = 5,
    ):
        self.queue: asyncio.Queue[
            tuple[
                FinalTranscriptEvent,
                Callable[[dict, bool], Awaitable[None]] | None,
                asyncio.Future[None],
                float,
            ]
            | None
        ] = asyncio.Queue(
            maxsize=max_queue_size
        )
        self._task: asyncio.Task | None = None
        self.queue_admission_timeout_seconds = queue_admission_timeout_seconds
        self.processing_timeout_seconds = processing_timeout_seconds
        self.shutdown_timeout_seconds = shutdown_timeout_seconds

    async def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(
                self._run(), name="stt-trace-cag-dispatcher"
            )

    async def submit(
        self,
        event: FinalTranscriptEvent,
        result_sink: Callable[[dict, bool], Awaitable[None]] | None = None,
    ) -> asyncio.Future[None]:
        if not isinstance(event, FinalTranscriptEvent):
            raise TypeError("TRACE-CAG accepts only FinalTranscriptEvent")
        completion = asyncio.get_running_loop().create_future()
        deadline = (
            asyncio.get_running_loop().time() + self.processing_timeout_seconds
        )
        try:
            await asyncio.wait_for(
                self.queue.put((event, result_sink, completion, deadline)),
                timeout=self.queue_admission_timeout_seconds,
            )
        except asyncio.TimeoutError:
            await self._deliver(
                result_sink,
                {
                    "type": "trace_cag.response",
                    "session_id": event.session_id,
                    "utterance_id": event.utterance_id,
                    "tutor_response": None,
                    "metadata": {},
                    "error": "TRACE-CAG queue is busy",
                },
            )
            completion.set_result(None)
        return completion

    async def close(self) -> None:
        if self._task is None:
            return
        try:
            await asyncio.wait_for(
                self.queue.put(None),
                timeout=self.shutdown_timeout_seconds,
            )
            await asyncio.wait_for(
                asyncio.shield(self._task),
                timeout=self.shutdown_timeout_seconds,
            )
        except asyncio.TimeoutError:
            logger.error(
                "TRACE-CAG dispatcher shutdown timed out pending=%s",
                self.queue.qsize(),
            )
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._settle_queued_jobs()
        self._task = None

    async def _run(self) -> None:
        from api.services.trace_cag.graph import get_trace_cag

        while True:
            job = await self.queue.get()
            if job is None:
                return
            event, result_sink, completion, deadline = job
            if completion.cancelled():
                continue
            try:
                remaining = deadline - asyncio.get_running_loop().time()
                if remaining <= 0:
                    raise asyncio.TimeoutError

                async def analyze():
                    pipeline = await get_trace_cag()
                    return await pipeline.analyze(
                        user_input=event.text,
                        session_id=event.session_id,
                        user_id=event.user_id,
                        input_type="voice",
                        stt_final=event.model_dump(),
                    )

                result = await asyncio.wait_for(
                    analyze(),
                    timeout=remaining,
                )
                await self._deliver(
                    result_sink,
                    {
                        "type": "trace_cag.response",
                        "session_id": event.session_id,
                        "utterance_id": event.utterance_id,
                        "tutor_response": result.get("tutor_response"),
                        "metadata": result.get("metadata", {}),
                        "error": result.get("error"),
                    },
                )
            except Exception as exc:
                logger.exception(
                    "TRACE-CAG final dispatch failed session=%s utterance=%s",
                    event.session_id,
                    event.utterance_id,
                )
                await self._deliver(
                    result_sink,
                    {
                        "type": "trace_cag.response",
                        "session_id": event.session_id,
                        "utterance_id": event.utterance_id,
                        "tutor_response": None,
                        "metadata": {},
                        "error": (
                            "TRACE-CAG response timed out"
                            if isinstance(exc, asyncio.TimeoutError)
                            else "TRACE-CAG response failed"
                        ),
                    },
                )
            finally:
                if not completion.done():
                    completion.set_result(None)

    async def _deliver(
        self,
        result_sink: Callable[[dict, bool], Awaitable[None]] | None,
        payload: dict,
    ) -> None:
        if not result_sink:
            return
        try:
            await result_sink(payload, True)
        except Exception:
            logger.exception(
                "TRACE-CAG response sink failed session=%s",
                payload.get("session_id"),
            )

    def _settle_queued_jobs(self) -> None:
        while not self.queue.empty():
            job = self.queue.get_nowait()
            if job is None:
                continue
            _, _, completion, _ = job
            if not completion.done():
                completion.set_result(None)
