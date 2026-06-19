"""Pronunciation assessment routes backed by HuBERT."""

from __future__ import annotations

import logging
import os
import tempfile
import time
import uuid
from typing import Tuple

import numpy as np
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from starlette.concurrency import run_in_threadpool

from api.core.auth import AuthenticatedUser, get_current_user
from api.core.audit_emitter import emit_ai_audit_event
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
from api.services.hubert_service import get_hubert_service

router = APIRouter()
logger = logging.getLogger(__name__)


def _decode_audio_file(path: str) -> Tuple[np.ndarray, int]:
    """Decode uploaded audio into mono float32 waveform."""
    try:
        from faster_whisper.audio import decode_audio

        return decode_audio(path, sampling_rate=16000), 16000
    except Exception:
        logger.debug("Falling back to scipy WAV decoder", exc_info=True)

    try:
        from scipy.io import wavfile

        sample_rate, audio = wavfile.read(path)
    except Exception as exc:
        raise ValueError("Unsupported or unreadable audio file") from exc

    if audio.ndim > 1:
        audio = audio.mean(axis=1)

    audio = audio.astype(np.float32)
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if peak > 1.0:
        audio = audio / peak

    return audio, int(sample_rate)


@router.post(
    "/assess-pronunciation",
    summary="Assess pronunciation with HuBERT",
    description="Upload audio and a target word or phrase to receive pronunciation feedback.",
)
async def assess_pronunciation(
    request_context: Request,
    audio: UploadFile = File(...),
    target_text: str = Form(...),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
    tmp_path = ""

    try:
        quota = await enforce_user_quota(
            current_user.user_id,
            "stt.assess_pronunciation",
            token_cost=default_token_cost_for_endpoint("stt.transcribe"),
            fail_closed=True,
        )

        requested_suffix = os.path.splitext(audio.filename or "")[1].lower()
        suffix = (
            requested_suffix
            if requested_suffix in {".wav", ".mp3", ".m4a", ".ogg", ".webm", ".flac"}
            else ".wav"
        )
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            content = await audio.read()
            if not content:
                raise HTTPException(status_code=400, detail="Audio file is empty")
            tmp.write(content)
            tmp_path = tmp.name

        waveform, sample_rate = await run_in_threadpool(_decode_audio_file, tmp_path)
        hubert = await get_hubert_service()
        result = await hubert.analyze_pronunciation(
            waveform,
            sample_rate=sample_rate,
            reference_text=target_text,
        )

        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "stt.assess_pronunciation",
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

        return {
            "success": True,
            "target_text": target_text,
            **result.to_dict(),
        }
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Pronunciation assessment error: %s", exc, exc_info=True)
        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "stt.assess_pronunciation",
                "status": "error",
                "error": str(exc),
                "latency_ms": int((time.time() - start_time) * 1000),
            }
        )
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)
