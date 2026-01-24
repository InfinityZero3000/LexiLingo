"""STT routes for Faster-Whisper."""

from __future__ import annotations

import tempfile
from typing import Optional

from fastapi import APIRouter, File, UploadFile, HTTPException

from api.services.stt_service import get_stt_service

router = APIRouter()


@router.post(
    "/transcribe",
    summary="Transcribe audio to text",
    description="Upload an audio file (wav/mp3/m4a) and get transcription."
)
async def transcribe_audio(
    audio: UploadFile = File(...),
    language: Optional[str] = None,
):
    try:
        stt = get_stt_service()

        with tempfile.NamedTemporaryFile(delete=True, suffix=f"_{audio.filename}") as tmp:
            content = await audio.read()
            tmp.write(content)
            tmp.flush()

            result = stt.transcribe_file(tmp.name, language=language)

        return {
            "text": result.get("text", ""),
            "language": result.get("language", ""),
        }

    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))