"""
Lexi Chat Route — Story-driven conversational AI with the parrot mascot.

Pipeline:
  1. STT (if voice input) → Whisper transcription
  2. TraceCAG pipeline → KG expansion + diagnosis + retrieval
    3. TraceCAG generation (internal model fallback handled by TraceCAG)
  4. TTS synthesis → gTTS / Piper for Lexi's voice
  5. Return structured response with audio, story context, corrections

Integrates with the existing TraceCAG system for document retrieval
and knowledge graph expansion to make conversations contextually rich.

The actual pipeline orchestration (session bootstrap, STT/TraceCAG/TTS,
persistence) lives in api.services.lexi_chat_service — this module only
parses requests, enforces auth/quota, and shapes responses.
"""

import asyncio
import logging
import time
import uuid
from datetime import datetime, timezone
from typing import Dict, Any

from fastapi import APIRouter, HTTPException, Depends, Query, Header, Request
from fastapi.responses import StreamingResponse
from motor.motor_asyncio import AsyncIOMotorDatabase
from pymongo.errors import OperationFailure
from api.core.auth import AuthenticatedUser, enforce_user_scope, get_current_user
from api.core.audit_emitter import emit_ai_audit_event
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
from api.core.database import get_database
from api.utils.cursor import (
    build_pagination,
    decode_cursor_str,
    encode_cursor,
    load_full_cursor,
    to_iso_timestamp,
)
from api.services import lexi_chat_service as svc
from api.services.lexi_chat_service import (
    LexiChatRequest,
    LexiChatResponse,
    LexiSessionListResponse,
    LexiSessionRenameRequest,
    LexiSessionRequest,
    LexiSessionResponse,
    LexiSessionSummary,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/lexi", tags=["lexi-chat"])


def _serialize_lexi_message(doc: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": doc.get("id") or doc.get("message_id") or str(doc.get("_id", "")),
        "session_id": doc.get("session_id", ""),
        "role": doc.get("role", "user"),
        "content": doc.get("content", ""),
        "timestamp": to_iso_timestamp(doc.get("timestamp")),
    }


# ─── Routes ──────────────────────────────────────────────────────────────────
@router.post("/sessions", response_model=LexiSessionResponse)
async def create_lexi_session(
    request: LexiSessionRequest = LexiSessionRequest(),
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> LexiSessionResponse:
    """Create a new conversation session with Lexi."""
    auth_user_id = enforce_user_scope(current_user, request.user_id)
    request = request.model_copy(update={"user_id": auth_user_id})

    session_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    await svc.lexi_store.set_session(session_id, {
        "session_id": session_id,
        "user_id": request.user_id,
        "created_at": now,
        "updated_at": now,
        "title": "Lexi Chat",
        "message_count": 0,
        "persona": "lexi",
        "story_context": None,
    })
    await svc.lexi_store.init_messages(session_id)

    await db["lexi_sessions"].update_one(
        {"session_id": session_id},
        {
            "$set": {
                "session_id": session_id,
                "user_id": request.user_id,
                "title": "Lexi Chat",
                "created_at": now,
                "updated_at": now,
                "message_count": 0,
                "persona": "lexi",
            }
        },
        upsert=True,
    )

    logger.info(f" Lexi session created: {session_id[:8]}... for user: {request.user_id}")
    return LexiSessionResponse(session_id=session_id, created_at=now)


@router.post("/chat", response_model=LexiChatResponse)
async def lexi_chat(
    request_context: Request,
    request: LexiChatRequest,
    x_idempotency_key: str | None = Header(
        default=None,
        alias="X-Idempotency-Key",
    ),
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> LexiChatResponse:
    """
    Chat with Lexi — the full AI pipeline.

    Pipeline flow:
      1. Session management (create if needed)
      2. STT transcription (if voice input)
      3. TraceCAG pipeline (KG expansion + retrieval)
      4. LLM generation with Lexi persona (Groq → Gemini → Ollama)
      5. TTS synthesis (if enabled)
      6. Return structured response
    """
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
    auth_user_id = enforce_user_scope(current_user, request.user_id)
    request = request.model_copy(update={"user_id": auth_user_id})

    quota = await enforce_user_quota(
        current_user.user_id,
        "lexi.chat",
        token_cost=default_token_cost_for_endpoint("lexi.chat", text=request.message),
        fail_closed=True,
    )

    # ── 1. Session management ──
    if request.session_id:
        session_id = request.session_id
        history = await svc.prepare_existing_lexi_session(session_id, current_user, db)
    else:
        session_id = str(uuid.uuid4())
        history = []
        await svc.create_lexi_session_for_user(
            session_id=session_id,
            user_id=request.user_id,
            story_context=request.story_context,
            db=db,
        )

    request_hash = svc.idempotency_request_hash(request)
    if x_idempotency_key:
        cached_response = await svc.lexi_idempotency_store.get(
            user_id=request.user_id,
            session_id=session_id,
            idempotency_key=x_idempotency_key,
            request_hash=request_hash,
        )
        if cached_response:
            return LexiChatResponse(**cached_response)

    # ── 2–6. Execute shared pipeline (STT → TraceCAG → TTS → persist) ──
    result = await svc.run_lexi_pipeline(
        request=request,
        session_id=session_id,
        history=history,
        db=db,
        quota=quota,
        start_time=start_time,
    )

    # ── 7. Build response ──
    logger.info(
        f" Lexi chat complete — {result.metadata['latency_ms']}ms, "
        f"model: {result.model_used}, steps: {result.metadata['pipeline_steps']}"
    )

    await emit_ai_audit_event(
        {
            "request_id": request_id,
            "user_id": current_user.user_id,
            "endpoint": "lexi.chat",
            "status": "success",
            "session_id": result.session_id,
            "model_used": result.model_used,
            "latency_ms": result.metadata["latency_ms"],
            "quota": result.metadata["quota"],
        }
    )

    response = LexiChatResponse(
        session_id=result.session_id,
        message_id=result.message_id,
        lexi_response=result.lexi_response,
        audio_base64=result.audio_b64,
        corrections=result.corrections,
        linked_concepts=result.linked_concepts,
        suggested_practice=result.suggested_practice,
        vietnamese_hint=result.vietnamese_hint,
        scores=result.scores,
        story_context=result.story_ctx,
        metadata=result.metadata,
    )

    if x_idempotency_key:
        await svc.lexi_idempotency_store.set(
            user_id=request.user_id,
            session_id=session_id,
            idempotency_key=x_idempotency_key,
            request_hash=request_hash,
            response=response.model_dump(),
        )

    return response


@router.post("/stream")
async def lexi_stream_chat(
    request_context: Request,
    request: LexiChatRequest,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> StreamingResponse:
    """
    Chat with Lexi — streaming SSE variant.

    Returns a text/event-stream response. Events:
      • ``thinking``  — sent immediately to signal the pipeline has started
      • ``heartbeat`` — SSE data event sent every 2.5 s to keep proxies alive
      • ``chunk``     — one word at a time as the response is "typed out"
      • ``done``      — final event carrying message_id, corrections, audio, etc.
      • ``error``     — sent if the pipeline raises an unrecoverable error

    The TraceCAG pipeline runs first (text only, TTS skipped); text chunks
    begin streaming as soon as the LLM response is ready.  TTS audio is
    synthesised after the last chunk and delivered in the ``done`` event.
    """
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
    auth_user_id = enforce_user_scope(current_user, request.user_id)
    request = request.model_copy(update={"user_id": auth_user_id})

    quota_timeout_s = svc.env_float("LEXI_STREAM_QUOTA_TIMEOUT_SECONDS", 5.0, minimum=0.5)
    try:
        quota = await asyncio.wait_for(
            enforce_user_quota(
                current_user.user_id,
                "lexi.chat",
                token_cost=default_token_cost_for_endpoint(
                    "lexi.chat",
                    text=request.message,
                ),
                fail_closed=True,
            ),
            timeout=quota_timeout_s,
        )
    except asyncio.TimeoutError as exc:
        logger.error(
            "Lexi /stream quota check timed out after %.1fs",
            quota_timeout_s,
        )
        raise HTTPException(
            status_code=503,
            detail="AI quota service is temporarily unavailable",
        ) from exc

    session_id = request.session_id or str(uuid.uuid4())
    prechecked_history: list[Dict[str, Any]] | None = None
    if request.session_id:
        session_timeout_s = svc.env_float(
            "LEXI_STREAM_SESSION_TIMEOUT_SECONDS",
            15.0,
            minimum=svc.HEARTBEAT_INTERVAL_S,
        )
        try:
            prechecked_history = await asyncio.wait_for(
                svc.prepare_existing_lexi_session(session_id, current_user, db),
                timeout=session_timeout_s,
            )
        except asyncio.TimeoutError as exc:
            logger.error(
                "Lexi /stream session ownership check timed out after %.1fs",
                session_timeout_s,
            )
            raise HTTPException(
                status_code=503,
                detail="Chat session service is temporarily unavailable",
            ) from exc

    return StreamingResponse(
        svc.stream_lexi_chat(
            request=request,
            session_id=session_id,
            prechecked_history=prechecked_history,
            quota=quota,
            start_time=start_time,
            request_id=request_id,
            current_user=current_user,
            db=db,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/sessions/{session_id}/messages")
async def get_lexi_messages(
    session_id: str,
    limit: int = Query(100, ge=1, le=200),
    cursor: str | None = None,
    full: bool = Query(False, description="Set true to force full session history load"),
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    """Get messages in a Lexi session.

    By default this endpoint returns a bounded page to avoid heavy full-session scans.
    Set `full=true` only for maintenance/legacy flows that require the entire history.
    """
    is_full = full if isinstance(full, bool) else False
    if not is_full:
        return await get_lexi_messages_paged(
            session_id=session_id,
            limit=limit,
            cursor=cursor,
            db=db,
            current_user=current_user,
        )

    session_doc = None
    try:
        session_doc = await svc.ensure_session_owner(session_id, current_user, db)
        cached_session = await svc.lexi_store.get_session(session_id)
    except HTTPException as e:
        cached_session = await svc.lexi_store.get_session(session_id)
        if e.status_code == 404 and cached_session:
            owner_user_id = str(cached_session.get("user_id") or "")
            if owner_user_id and hasattr(current_user, "user_id") and owner_user_id != current_user.user_id:
                raise HTTPException(status_code=403, detail="Forbidden: session ownership mismatch")
        else:
            raise
    cached_messages = await svc.lexi_store.get_messages(session_id) if cached_session else []

    expected_count = int((session_doc or {}).get("message_count") or 0)
    cache_is_complete = cached_session is not None and (
        expected_count == 0 or len(cached_messages) >= expected_count
    )

    if cache_is_complete:
        return {
            "success": True,
            "session_id": session_id,
            "messages": cached_messages,
        }

    if not session_doc:
        if cached_session is not None:
            return {
                "success": True,
                "session_id": session_id,
                "messages": cached_messages,
            }
        raise HTTPException(status_code=404, detail="Session not found")

    cursor = db["lexi_messages"].find({"session_id": session_id}).sort("timestamp", 1)
    messages = await load_full_cursor(cursor)
    payload = [
        {
            "id": m.get("id", str(uuid.uuid4())),
            "role": m.get("role", "user"),
            "content": m.get("content", ""),
            "timestamp": m.get("timestamp", datetime.now(timezone.utc).isoformat()),
        }
        for m in messages
    ]

    # Rehydrate cache for faster next reads.
    await svc.lexi_store.set_session(session_id, {
        "session_id": session_doc.get("session_id"),
        "user_id": session_doc.get("user_id", "demo_user"),
        "created_at": session_doc.get("created_at", datetime.now(timezone.utc).isoformat()),
        "updated_at": session_doc.get("updated_at", datetime.now(timezone.utc).isoformat()),
        "title": session_doc.get("title", "Lexi Chat"),
        "message_count": session_doc.get("message_count", len(payload)),
        "persona": session_doc.get("persona", "lexi"),
        "story_context": session_doc.get("story_context"),
    })
    await svc.lexi_store.delete_messages(session_id)
    for item in payload:
        await svc.lexi_store.append_message(session_id, item)

    return {
        "success": True,
        "session_id": session_id,
        "messages": payload,
    }


@router.get("/sessions/{session_id}/messages/paged")
async def get_lexi_messages_paged(
    session_id: str,
    limit: int = 50,
    cursor: str | None = None,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    await svc.ensure_session_owner(session_id, current_user, db)

    if limit < 1:
        raise HTTPException(status_code=400, detail="limit must be >= 1")

    safe_limit = min(limit, 200)
    base_query: Dict[str, Any] = {"session_id": session_id}
    query: Dict[str, Any] = dict(base_query)

    if cursor:
        cursor_ts, cursor_oid = decode_cursor_str(cursor)
        query = {
            "session_id": session_id,
            "$or": [
                {"timestamp": {"$lt": cursor_ts}},
                {"timestamp": cursor_ts, "_id": {"$lt": cursor_oid}},
            ],
        }

    docs_desc = await (
        db["lexi_messages"]
        .find(query)
        .sort([("timestamp", -1), ("_id", -1)])
        .limit(safe_limit + 1)
        .to_list(length=safe_limit + 1)
    )

    has_more = len(docs_desc) > safe_limit
    docs_desc = docs_desc[:safe_limit]
    docs = list(reversed(docs_desc))
    messages = [_serialize_lexi_message(doc) for doc in docs]

    total_count = await db["lexi_messages"].count_documents(base_query)
    next_cursor = encode_cursor(docs[0]) if has_more and docs else None
    prev_cursor = encode_cursor(docs[-1]) if docs else None
    window_start_ts = to_iso_timestamp(docs[0].get("timestamp")) if docs else None
    window_end_ts = to_iso_timestamp(docs[-1].get("timestamp")) if docs else None

    return {
        "success": True,
        "session_id": session_id,
        "messages": messages,
        "pagination": build_pagination(
            total_count=total_count,
            returned=len(messages),
            has_more=has_more,
            next_cursor=next_cursor,
            prev_cursor=prev_cursor,
            window_start_ts=window_start_ts,
            window_end_ts=window_end_ts,
        ),
    }


@router.get("/sessions/{session_id}/messages/metadata")
async def get_lexi_messages_metadata(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    await svc.ensure_session_owner(session_id, current_user, db)

    base_query: Dict[str, Any] = {"session_id": session_id}
    total_count = await db["lexi_messages"].count_documents(base_query)

    if total_count == 0:
        return {
            "success": True,
            "session_id": session_id,
            "metadata": {
                "total_count": 0,
                "has_messages": False,
                "latest_cursor": None,
                "oldest_cursor": None,
                "latest_ts": None,
                "oldest_ts": None,
                "has_more": False,
                "next_cursor": None,
                "prev_cursor": None,
                "window_start_ts": None,
                "window_end_ts": None,
            },
        }

    latest_docs = await (
        db["lexi_messages"]
        .find(base_query)
        .sort([("timestamp", -1), ("_id", -1)])
        .limit(1)
        .to_list(length=1)
    )
    oldest_docs = await (
        db["lexi_messages"]
        .find(base_query)
        .sort([("timestamp", 1), ("_id", 1)])
        .limit(1)
        .to_list(length=1)
    )

    latest = latest_docs[0]
    oldest = oldest_docs[0]
    latest_cursor = encode_cursor(latest)
    oldest_cursor = encode_cursor(oldest)
    latest_ts = to_iso_timestamp(latest.get("timestamp"))
    oldest_ts = to_iso_timestamp(oldest.get("timestamp"))

    return {
        "success": True,
        "session_id": session_id,
        "metadata": {
            "total_count": total_count,
            "has_messages": True,
            "latest_cursor": latest_cursor,
            "oldest_cursor": oldest_cursor,
            "latest_ts": latest_ts,
            "oldest_ts": oldest_ts,
            "has_more": total_count > 0,
            "next_cursor": oldest_cursor,
            "prev_cursor": latest_cursor,
            "window_start_ts": oldest_ts,
            "window_end_ts": latest_ts,
        },
    }


@router.get("/sessions/user/{user_id}", response_model=LexiSessionListResponse)
async def list_lexi_sessions(
    user_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> LexiSessionListResponse:
    enforce_user_scope(current_user, user_id)
    try:
        cursor = db["lexi_sessions"].find({"user_id": user_id}).sort("updated_at", -1)
        rows = await cursor.to_list(length=100)
    except Exception as exc:
        msg = str(exc).lower()
        if not (isinstance(exc, OperationFailure) and ("order-by item is excluded" in msg or "index path corresponding" in msg)):
            raise
        rows = await db["lexi_sessions"].find({"user_id": user_id}).limit(100).to_list(length=100)
        rows.sort(key=lambda row: row.get("updated_at") or row.get("created_at") or "", reverse=True)
    sessions = [
        LexiSessionSummary(
            session_id=row.get("session_id", ""),
            user_id=row.get("user_id", user_id),
            title=row.get("title", "Lexi Chat"),
            created_at=row.get("created_at", datetime.now(timezone.utc).isoformat()),
            updated_at=row.get("updated_at", row.get("created_at", datetime.now(timezone.utc).isoformat())),
            message_count=int(row.get("message_count", 0)),
        )
        for row in rows
        if row.get("session_id")
    ]
    return LexiSessionListResponse(sessions=sessions)


@router.post("/sessions/{session_id}/rename")
async def rename_lexi_session(
    session_id: str,
    request: LexiSessionRenameRequest,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    await svc.ensure_session_owner(session_id, current_user, db)

    title = request.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="Title cannot be empty")

    now = datetime.now(timezone.utc).isoformat()
    result = await db["lexi_sessions"].update_one(
        {"session_id": session_id},
        {"$set": {"title": title, "updated_at": now}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Session not found")

    sess = await svc.lexi_store.get_session(session_id)
    if sess:
        sess["title"] = title
        sess["updated_at"] = now
        await svc.lexi_store.set_session(session_id, sess)

    return {"success": True, "session_id": session_id, "title": title}


@router.post("/sessions/{session_id}/delete")
async def delete_lexi_session(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    await svc.ensure_session_owner(session_id, current_user, db)

    await db["lexi_sessions"].delete_one({"session_id": session_id})
    await db["lexi_messages"].delete_many({"session_id": session_id})
    await svc.lexi_store.delete_session(session_id)
    await svc.lexi_store.delete_messages(session_id)
    return {"success": True, "session_id": session_id}


@router.get("/health")
async def lexi_health() -> Dict[str, Any]:
    """Health check for Lexi chat service."""
    return {
        "status": "ok",
        "service": "lexi-chat",
        "persona": "lexi-the-parrot",
        "capabilities": ["text-chat", "voice-input", "tts-output", "trace-cag-retrieval"],
    }
