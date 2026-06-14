"""ModelGateway compatibility adapter for the unified STT verifier."""

from __future__ import annotations

import base64
import os
import tempfile
from typing import Any, Optional

from api.services.stt.runtime import get_stt_config, get_stt_registry


class WhisperHandler:
    @property
    def is_loaded(self) -> bool:
        try:
            return get_stt_registry().status in {"ready", "degraded"}
        except RuntimeError:
            return False

    @property
    def memory_usage_mb(self) -> float:
        return 0.0

    async def load(self) -> bool:
        return self.is_loaded

    async def unload(self) -> None:
        return None

    async def transcribe(
        self,
        audio: str | bytes | None = None,
        language: Optional[str] = None,
        audio_bytes: bytes | None = None,
        **_: Any,
    ) -> dict[str, Any]:
        value = audio if audio is not None else audio_bytes
        if value is None:
            raise ValueError("Missing 'audio' parameter")
        path = None
        temporary = False
        try:
            if isinstance(value, bytes):
                if len(value) > get_stt_config().legacy_upload_max_bytes:
                    raise ValueError("Legacy audio payload exceeds size limit")
                with tempfile.NamedTemporaryFile(
                    delete=False, suffix=".audio"
                ) as handle:
                    handle.write(value)
                    path = handle.name
                temporary = True
            elif value.startswith("data:audio"):
                encoded = value.split("base64,", 1)[-1]
                decoded = base64.b64decode(encoded, validate=True)
                return await self.transcribe(audio=decoded, language=language)
            elif not os.path.isfile(value):
                # Treat unrecognised strings as raw base64 payloads.
                decoded = base64.b64decode(value, validate=True)
                return await self.transcribe(audio=decoded, language=language)
            else:
                path = value
            result = await get_stt_registry().verifier.transcribe_path(
                path, language or "en"
            )
            return result.model_dump()
        finally:
            if temporary and path:
                os.unlink(path)

    async def invoke(self, params: dict[str, Any]) -> dict[str, Any]:
        return await self.transcribe(**params)


_handler: Optional[WhisperHandler] = None


def get_whisper_handler() -> WhisperHandler:
    global _handler
    if _handler is None:
        _handler = WhisperHandler()
    return _handler
