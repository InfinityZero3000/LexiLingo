"""STT routes for Faster-Whisper."""

from __future__ import annotations

import tempfile
import os
from typing import Optional
import logging

from fastapi import APIRouter, File, UploadFile, HTTPException
from starlette.concurrency import run_in_threadpool

from api.services.stt_service import get_stt_service

router = APIRouter()
logger = logging.getLogger(__name__)


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

        # Save to temp file
        with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{audio.filename}") as tmp:
            content = await audio.read()
            tmp.write(content)
            tmp_path = tmp.name

        try:
            # Run blocking transcription in threadpool
            result = await run_in_threadpool(stt.transcribe_file, tmp_path, language)

            return {
                "success": True,
                "text": result.get("text", ""),
                "language": result.get("language", ""),
                "model": "faster-whisper",
            }
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    except Exception as exc:
        logger.error(f"STT error: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))