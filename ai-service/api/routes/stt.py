"""Realtime and short-clip STT transports."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import tempfile
import time
import uuid
from contextlib import suppress

logger = logging.getLogger(__name__)

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Request,
    UploadFile,
    WebSocket,
)
from fastapi.websockets import WebSocketDisconnect

from api.core.auth import AuthenticatedUser, _decode_backend_jwt, get_current_user
from api.core.audit_emitter import emit_ai_audit_event
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
from api.services.stt.audio_ingest import (
    SequenceStatus,
    classify_sequence,
    parse_audio_frame,
)
from api.services.stt.errors import STTErrorCode, STTProtocolError
from api.services.stt.runtime import get_stt_config, get_stt_sessions
from api.services.stt.schemas import ResumeMessage, StartMessage
from api.services.stt_service import get_stt_service

router = APIRouter()

_AUDIO_MAGIC: dict[bytes, str] = {
    b"RIFF": ".wav",
    b"fLaC": ".flac",
    b"OggS": ".ogg",
    b"\x1a\x45\xdf\xa3": ".webm",
    b"ID3": ".mp3",
    b"\xff\xfb": ".mp3",
    b"\xff\xf3": ".mp3",
    b"\xff\xf2": ".mp3",
}

def _validate_audio_magic(header: bytes) -> bool:
    """Return True if header bytes match a known audio format signature."""
    for magic in _AUDIO_MAGIC:
        if header[: len(magic)] == magic:
            return True
    # M4A/MP4 ftyp box: bytes 4-8 are 'ftyp'
    if len(header) >= 8 and header[4:8] == b"ftyp":
        return True
    return False


def _websocket_user_id(websocket: WebSocket) -> str | None:
    # Tokens must come via Authorization header only — query params appear in access logs.
    header = websocket.headers.get("authorization", "")
    token = header[7:].strip() if header.lower().startswith("bearer ") else ""
    payload = _decode_backend_jwt(token) if token else None
    if not payload or payload.get("type") != "access":
        return None
    sub = payload.get("sub") if payload else None
    return str(sub) if sub else None


@router.websocket("/stream")
async def stream_audio(websocket: WebSocket):
    await websocket.accept()
    send_lock = asyncio.Lock()

    async def send_json(payload):
        async with send_lock:
            await websocket.send_json(payload)

    user_id = _websocket_user_id(websocket)
    if not user_id:
        await send_json(
            {
                "type": "stt.error",
                "session_id": None,
                "code": STTErrorCode.INVALID_START.value,
                "message": "Authentication required",
            }
        )
        await websocket.close(code=4401)
        return
    manager = get_stt_sessions()
    connection_acquired = manager.acquire_connection(user_id)
    if not connection_acquired:
        await send_json(
            {
                "type": "stt.error",
                "session_id": None,
                "code": STTErrorCode.SERVER_BUSY.value,
                "message": "Per-user WebSocket connection capacity reached",
            }
        )
        await websocket.close(code=4429)
        return
    session = None
    sender = None
    try:
        first = await asyncio.wait_for(
            websocket.receive_text(),
            timeout=get_stt_config().first_message_timeout_seconds,
        )
        payload = json.loads(first)
        if payload.get("type") == "start":
            message = StartMessage.model_validate(payload)
            if message.user_id and message.user_id != user_id:
                raise STTProtocolError(
                    STTErrorCode.INVALID_START, "User scope mismatch"
                )
            message.user_id = user_id
            try:
                await enforce_user_quota(
                    user_id,
                    "stt.stream",
                    token_cost=default_token_cost_for_endpoint("stt.transcribe"),
                    fail_closed=True,
                )
            except HTTPException as exc:
                raise STTProtocolError(
                    STTErrorCode.SERVER_BUSY,
                    "STT quota unavailable or exceeded",
                ) from exc
            session = await manager.create(message)
            await send_json(
                {
                    "type": "session_started",
                    "session_id": message.session_id,
                    "sample_rate": message.sample_rate,
                    "format": message.format,
                    "mode": manager.registry.status,
                }
            )
        elif payload.get("type") == "resume":
            message = ResumeMessage.model_validate(payload)
            session = manager.resume(message.session_id, message.last_seq, user_id)
            await send_json(
                {
                    "type": "session_started",
                    "session_id": message.session_id,
                    "resumed": True,
                    "server_last_seq": session.last_ack_seq,
                }
            )
            finals, responses = session.replay_snapshot()
            for final in finals:
                replay = dict(final)
                replay["replayed"] = True
                await send_json(replay)
            for response in responses:
                replay = dict(response)
                replay["replayed"] = True
                await send_json(replay)
        else:
            raise STTProtocolError(
                STTErrorCode.INVALID_START, "First message must be start or resume"
            )

        async def send_events():
            while True:
                event = await session.event_queue.get()
                await send_json(event)
                if event.get("type") == "session_closed":
                    return

        sender = asyncio.create_task(send_events())
        while not session.closed:
            incoming = await websocket.receive()
            if incoming.get("bytes") is not None:
                frame = parse_audio_frame(
                    incoming["bytes"],
                    sample_rate=session.start.sample_rate,
                    max_ms=get_stt_config().max_client_chunk_ms,
                )
                status, missing = classify_sequence(session.last_seq, frame.seq)
                if status == SequenceStatus.DUPLICATE:
                    await send_json(
                        {
                            "type": "ack",
                            "session_id": session.start.session_id,
                            "last_seq": session.last_ack_seq,
                            "duplicate": True,
                        }
                    )
                    continue
                if status == SequenceStatus.GAP:
                    manager.metrics.increment("stt_missing_frames", missing)
                    await send_json(
                        {
                            "type": "stt.gap",
                            "session_id": session.start.session_id,
                            "expected_seq": session.last_seq + 1,
                            "received_seq": frame.seq,
                            "missing": missing,
                        }
                    )
                if not session.enqueue(frame):
                    await send_json(
                        {
                            "type": "stt.backpressure",
                            "session_id": session.start.session_id,
                            "action": "slow_down",
                            "reason": "audio_queue_full",
                            "queue_depth": session.input_queue.qsize(),
                        }
                    )
                    continue
                await send_json(
                    {
                        "type": "ack",
                        "session_id": session.start.session_id,
                        "last_seq": frame.seq,
                        "server_ts_ms": int(time.time() * 1000),
                    }
                )
            elif incoming.get("text"):
                control = json.loads(incoming["text"])
                if control.get("type") == "stop":
                    await manager.close(session.start.session_id, "client_stop")
                    break
                if control.get("type") == "ping":
                    await send_json(
                        {"type": "pong", "session_id": session.start.session_id}
                    )
        if sender:
            with suppress(asyncio.CancelledError):
                await sender
    except WebSocketDisconnect:
        if session:
            manager.mark_disconnected(session.start.session_id)
    except asyncio.TimeoutError:
        await send_json(
            {
                "type": "stt.error",
                "session_id": None,
                "code": STTErrorCode.INVALID_START.value,
                "message": "Start message timeout",
            }
        )
        await websocket.close(code=4408)
    except STTProtocolError as exc:
        if sender and not sender.done():
            sender.cancel()
            with suppress(asyncio.CancelledError):
                await sender
        await send_json(
            {
                "type": "stt.error",
                "session_id": session.start.session_id if session else None,
                "code": exc.code.value,
                "message": exc.message,
            }
        )
        if session:
            await manager.close(session.start.session_id, "error")
        await websocket.close(code=4400)
    except Exception as exc:
        logger.exception("Unhandled error in stream_audio session=%s", session.start.session_id if session else None)
        if sender and not sender.done():
            sender.cancel()
            with suppress(asyncio.CancelledError):
                await sender
        await send_json(
            {
                "type": "stt.error",
                "session_id": session.start.session_id if session else None,
                "code": STTErrorCode.INTERNAL_ERROR.value,
                "message": "Internal server error",
            }
        )
        if session:
            await manager.close(session.start.session_id, "error")
        await websocket.close(code=1011)
    finally:
        if sender and not sender.done():
            sender.cancel()
        manager.release_connection(user_id)


@router.post("/transcribe")
async def transcribe_audio(
    request_context: Request,
    audio: UploadFile = File(...),
    language: str = "en",
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
    quota = await enforce_user_quota(
        current_user.user_id,
        "stt.transcribe",
        token_cost=default_token_cost_for_endpoint("stt.transcribe"),
        fail_closed=True,
    )
    config = get_stt_config()
    requested_suffix = os.path.splitext(audio.filename or "")[1].lower()
    suffix = (
        requested_suffix
        if requested_suffix in {".wav", ".mp3", ".m4a", ".ogg", ".webm", ".flac"}
        else ".audio"
    )
    path = None
    total = 0
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as handle:
            path = handle.name
            first_chunk = True
            while chunk := await audio.read(64 * 1024):
                total += len(chunk)
                if total > config.legacy_upload_max_bytes:
                    raise HTTPException(
                        status_code=413, detail="Audio clip exceeds upload limit"
                    )
                if first_chunk:
                    if not _validate_audio_magic(chunk[:8]):
                        raise HTTPException(
                            status_code=415, detail="Unsupported audio format"
                        )
                    first_chunk = False
                handle.write(chunk)
        result = await get_stt_service().transcribe_file(path, language)
        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "stt.transcribe",
                "status": "success",
                "latency_ms": int((time.time() - start_time) * 1000),
                "quota": quota.model_dump() if hasattr(quota, "model_dump") else {},
            }
        )
        return {"success": True, **result, "model": "faster-whisper"}
    finally:
        if path:
            os.unlink(path)
