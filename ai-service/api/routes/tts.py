"""TTS routes for Piper."""

from __future__ import annotations

import time
import uuid

from fastapi import APIRouter, Body, HTTPException, Depends, Request
from fastapi.responses import Response
from starlette.concurrency import run_in_threadpool
import logging

from api.core.auth import AuthenticatedUser, get_current_user
from api.core.audit_emitter import emit_ai_audit_event
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
from api.services.tts_service import get_tts_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post(
    "/synthesize",
    summary="Synthesize speech from text",
    description="Generate WAV audio from input text."
)
async def synthesize_text(
    request_context: Request,
    text: str = Body(..., embed=True),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())

    try:
        quota = await enforce_user_quota(
            current_user.user_id,
            "tts.synthesize",
            token_cost=default_token_cost_for_endpoint("tts.synthesize", text=text),
            fail_closed=True,
        )
        tts = get_tts_service()
        # Run blocking synthesis in threadpool
        audio_bytes = await run_in_threadpool(tts.synthesize, text)

        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "tts.synthesize",
                "status": "success",
                "latency_ms": int((time.time() - start_time) * 1000),
                "quota": {
                    "rpm_used": quota.rpm_used,
                    "rpm_limit": quota.rpm_limit,
                    "rpd_used": quota.rpd_used,
                    "rpd_limit": quota.rpd_limit,
                        "tpm_used": quota.tpm_used,
                        "tpm_limit": quota.tpm_limit,
                        "tpd_used": quota.tpd_used,
                        "tpd_limit": quota.tpd_limit,
                },
            }
        )

        return Response(content=audio_bytes, media_type="audio/wav")
    except HTTPException:
        raise
    except Exception as exc:
        logger.error(f"TTS error: {exc}")
        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "tts.synthesize",
                "status": "error",
                "error": str(exc),
                "latency_ms": int((time.time() - start_time) * 1000),
            }
        )
        raise HTTPException(status_code=500, detail=str(exc))