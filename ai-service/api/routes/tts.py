"""TTS routes for Piper."""

from __future__ import annotations

from fastapi import APIRouter, Body, HTTPException
from fastapi.responses import Response

from api.services.tts_service import get_tts_service

router = APIRouter()


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
        audio_bytes = tts.synthesize(text)
        return Response(content=audio_bytes, media_type="audio/wav")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))