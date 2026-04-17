"""STT routes for Faster-Whisper."""

from __future__ import annotations

import tempfile
import os
import time
import uuid
from typing import Optional
import logging

from fastapi import APIRouter, File, UploadFile, HTTPException, Depends, Request
from starlette.concurrency import run_in_threadpool

from api.core.auth import AuthenticatedUser, get_current_user
from api.core.audit_emitter import emit_ai_audit_event
from api.core.quota_guard import enforce_user_quota
from api.services.stt_service import get_stt_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post(
    "/transcribe",
    summary="Transcribe audio to text",
    description="Upload an audio file (wav/mp3/m4a) and get transcription."
)
async def transcribe_audio(
    request_context: Request,
    audio: UploadFile = File(...),
    language: Optional[str] = None,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())

    try:
        quota = await enforce_user_quota(current_user.user_id, "stt.transcribe")
        stt = get_stt_service()

        # Save to temp file
        with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{audio.filename}") as tmp:
            content = await audio.read()
            tmp.write(content)
            tmp_path = tmp.name

        try:
            # Run blocking transcription in threadpool
            result = await run_in_threadpool(stt.transcribe_file, tmp_path, language)

            await emit_ai_audit_event(
                {
                    "request_id": request_id,
                    "user_id": current_user.user_id,
                    "endpoint": "stt.transcribe",
                    "status": "success",
                    "latency_ms": int((time.time() - start_time) * 1000),
                    "quota": {
                        "rpm_used": quota.rpm_used,
                        "rpm_limit": quota.rpm_limit,
                        "rpd_used": quota.rpd_used,
                        "rpd_limit": quota.rpd_limit,
                    },
                }
            )

            return {
                "success": True,
                "text": result.get("text", ""),
                "language": result.get("language", ""),
                "model": "faster-whisper",
            }
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    except HTTPException:
        raise
    except Exception as exc:
        logger.error(f"STT error: {exc}")
        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "stt.transcribe",
                "status": "error",
                "error": str(exc),
                "latency_ms": int((time.time() - start_time) * 1000),
            }
        )
        raise HTTPException(status_code=500, detail=str(exc))