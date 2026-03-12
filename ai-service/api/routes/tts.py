"""TTS routes for Piper."""

from __future__ import annotations

from fastapi import APIRouter, Body, HTTPException
from fastapi.responses import Response
from starlette.concurrency import run_in_threadpool
import logging

from api.services.tts_service import get_tts_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post(
    "/synthesize",
    summary="Synthesize speech from text",
    description="Generate WAV audio from input text."
)
async def synthesize_text(
    text: str = Body(..., embed=True),
):
    try:
        tts = get_tts_service()
        # Run blocking synthesis in threadpool
        audio_bytes = await run_in_threadpool(tts.synthesize, text)
        return Response(content=audio_bytes, media_type="audio/wav")
    except Exception as exc:
        logger.error(f"TTS error: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))