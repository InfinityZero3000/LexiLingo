"""Authenticated ticket entry point for the duplex STT socket."""

from fastapi import APIRouter, Depends, HTTPException

from api.core.auth import AuthenticatedUser, get_current_user
from api.core.config import settings
from api.core.quota_guard import enforce_user_quota
from api.routes.stt import stream_audio
from api.services.stt.voice_ticket import issue_voice_ticket

router = APIRouter()
router.add_api_websocket_route("/stream", stream_audio)


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
