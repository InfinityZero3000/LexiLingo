"""Protocols shared by streaming and verifier engines."""

from __future__ import annotations

from typing import Optional, Protocol

from api.services.stt.schemas import AudioSegment, PrimaryResult, VerificationResult


class PrimarySTTSession(Protocol):
    async def push_audio(
        self, pcm16: bytes, start_ms: int, end_ms: int
    ) -> Optional[PrimaryResult]: ...

    async def finalize(self, audio: AudioSegment) -> PrimaryResult: ...

    async def close(self) -> None: ...


class PrimarySTTEngine(Protocol):
    async def load(self) -> None: ...

    async def create_session(self, language: str) -> PrimarySTTSession: ...

    async def close(self) -> None: ...


class VerifierEngine(Protocol):
    async def load(self) -> None: ...

    async def verify(
        self, audio: AudioSegment, language: str
    ) -> VerificationResult: ...

    async def close(self) -> None: ...
