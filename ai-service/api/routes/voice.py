"""Authenticated ticket entry point and readiness for duplex voice."""

import asyncio

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse

from api.core.auth import AuthenticatedUser, get_current_user
from api.core.config import settings
from api.core.database import mongodb_manager
from api.core.groq_key_pool import get_configured_key_count
from api.core.quota_guard import enforce_user_quota
from api.core.redis_client import get_redis
from api.routes.stt import stream_audio
from api.services.stt.runtime import get_stt_registry
from api.services.stt.voice_ticket import issue_voice_ticket
from api.services.tts_service import get_tts_service

router = APIRouter()
router.add_api_websocket_route("/stream", stream_audio)


async def voice_readiness() -> dict[str, str | int | bool]:
    """Fail closed when an enabled voice dependency is unavailable."""
    if not settings.VOICE_DUPLEX_ENABLED:
        return {"ready": False, "status": "disabled"}
    redis = await get_redis()
    await redis.ping()
    registry = get_stt_registry()
    if registry.status not in {"ready", "degraded"}:
        raise RuntimeError("STT primary is unavailable")
    key_count = get_configured_key_count()
    if key_count < 1:
        raise RuntimeError("No Groq keys configured")
    sample_rate = await asyncio.wait_for(
        asyncio.to_thread(lambda: get_tts_service().sample_rate), timeout=5
    )
    index = (await mongodb_manager.db["lexi_messages"].index_information()).get(
        "lexi_messages_session_id_uq", {}
    )
    if not index.get("unique"):
        raise RuntimeError("Voice persistence idempotency index is unavailable")
    return {
        "ready": True,
        "status": "ready",
        "stt": registry.status,
        "tts_sample_rate": sample_rate,
        "groq_keys": key_count,
    }


@router.get("/ready")
async def ready() -> JSONResponse:
    try:
        status = await voice_readiness()
    except Exception:
        return JSONResponse(status_code=503, content={"ready": False, "status": "unavailable"})
    public = {"ready": bool(status["ready"]), "status": str(status["status"])}
    return JSONResponse(status_code=200 if status["ready"] else 503, content=public)


@router.post("/ticket")
async def create_voice_ticket(
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> dict:
    if not settings.VOICE_DUPLEX_ENABLED:
        raise HTTPException(status_code=404, detail="Duplex voice is disabled")
    await enforce_user_quota(
        current_user.user_id,
        "voice.ticket",
        token_cost=1,
        fail_closed=True,
    )
    ticket, expires_in = await issue_voice_ticket(current_user.user_id)
    return {"ticket": ticket, "expires_in": expires_in}
