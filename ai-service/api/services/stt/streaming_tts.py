"""Bounded, non-queuing Piper admission for realtime voice turns."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator, Iterator

from api.services.tts_service import TTSService, get_tts_service


class TTSBusyError(RuntimeError):
    pass


class StreamingTTS:
    def __init__(self, service: TTSService | None = None, capacity: int = 1) -> None:
        if capacity < 1:
            raise ValueError("capacity must be positive")
        self._service = service or get_tts_service()
        self._capacity = capacity
        self._active = 0
        self._lock = asyncio.Lock()

    async def stream(self, text: str) -> AsyncIterator[bytes]:
        async with self._lock:
            if self._active >= self._capacity:
                raise TTSBusyError("TTS capacity exhausted")
            self._active += 1

        iterator = self._service.iter_pcm_chunks(text)
        try:
            while True:
                worker = asyncio.create_task(asyncio.to_thread(_next_or_none, iterator))
                try:
                    chunk = await asyncio.shield(worker)
                except asyncio.CancelledError:
                    await worker
                    raise
                if chunk is None:
                    return
                yield chunk
        finally:
            async with self._lock:
                self._active -= 1


def _next_or_none(iterator: Iterator[bytes]) -> bytes | None:
    return next(iterator, None)
