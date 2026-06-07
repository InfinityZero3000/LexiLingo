"""TTS routes for Piper and local fallback."""

from __future__ import annotations

import time
import uuid
import os
import io
import re
from typing import Optional

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


def find_local_audio(text: str, media_dir: str = "/app/data/media") -> Optional[tuple[bytes, str]]:
    """Check if the requested word/phrase has a pre-recorded audio file under media_dir."""
    if not os.path.isdir(media_dir):
        return None

    clean_text = text.strip()
    if not clean_text:
        return None

    # Build candidate filenames (word, lowercase, capitalized)
    candidates = [
        clean_text,
        clean_text.lower(),
        clean_text.capitalize(),
    ]

    # Also support replacing spaces with underscores/hyphens if it's a short phrase
    if " " in clean_text:
        candidates.extend([
            clean_text.replace(" ", "_"),
            clean_text.lower().replace(" ", "_"),
            clean_text.replace(" ", "-"),
            clean_text.lower().replace(" ", "-"),
        ])

    seen = set()
    unique_candidates = []
    for c in candidates:
        if c not in seen:
            seen.add(c)
            unique_candidates.append(c)

    # 1. Exact case-sensitive search
    for filename_base in unique_candidates:
        for ext in [".mp3", ".wav"]:
            filename = filename_base + ext
            filepath = os.path.join(media_dir, filename)
            if os.path.isfile(filepath):
                try:
                    with open(filepath, "rb") as f:
                        content = f.read()
                    media_type = "audio/mpeg" if ext == ".mp3" else "audio/wav"
                    logger.info(f"Found local fallback audio: {filepath}")
                    return content, media_type
                except Exception as e:
                    logger.warning(f"Error reading local audio file {filepath}: {e}")

    # 2. Case-insensitive search of directory
    try:
        files = os.listdir(media_dir)
        files_lower = {f.lower(): f for f in files}
        for filename_base in unique_candidates:
            for ext in [".mp3", ".wav"]:
                target_lower = (filename_base + ext).lower()
                if target_lower in files_lower:
                    real_filename = files_lower[target_lower]
                    filepath = os.path.join(media_dir, real_filename)
                    if os.path.isfile(filepath):
                        try:
                            with open(filepath, "rb") as f:
                                content = f.read()
                            media_type = "audio/mpeg" if ext == ".mp3" else "audio/wav"
                            logger.info(f"Found local fallback audio (case-insensitive): {filepath}")
                            return content, media_type
                        except Exception as e:
                            logger.warning(f"Error reading local audio file {filepath}: {e}")
    except Exception as e:
        logger.warning(f"Error listing media dir for case-insensitive search: {e}")

    return None


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

        # 1. Try local audio fallback first
        local_audio = find_local_audio(text)
        if local_audio is not None:
            audio_bytes, media_type = local_audio
            await emit_ai_audit_event(
                {
                    "request_id": request_id,
                    "user_id": current_user.user_id,
                    "endpoint": "tts.synthesize",
                    "status": "success",
                    "local_fallback": True,
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
            return Response(content=audio_bytes, media_type=media_type)

        # 2. Try Piper TTS generation
        try:
            tts = get_tts_service()
            # Run blocking synthesis in threadpool
            audio_bytes = await run_in_threadpool(tts.synthesize, text)
            media_type = "audio/wav"
        except Exception as tts_err:
            logger.warning(f"Piper TTS generation failed, falling back to gTTS: {tts_err}")
            
            # 3. Try gTTS fallback
            from gtts import gTTS
            clean = re.sub(r'[*_~`#]', '', text)
            clean = re.sub(r'[\U00010000-\U0010ffff]', '', clean, flags=re.UNICODE)
            clean = clean.strip()
            if not clean:
                raise ValueError("Clean text for TTS is empty") from tts_err

            def generate_gtts():
                gtts_obj = gTTS(text=clean, lang='en', slow=False)
                buf = io.BytesIO()
                gtts_obj.write_to_fp(buf)
                buf.seek(0)
                return buf.read()

            audio_bytes = await run_in_threadpool(generate_gtts)
            media_type = "audio/mpeg"

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

        return Response(content=audio_bytes, media_type=media_type)

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