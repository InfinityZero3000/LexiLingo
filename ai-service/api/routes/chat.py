"""
Chat routes

Endpoints for chat functionality with GraphCAG-first orchestration.
"""

from fastapi import APIRouter, Depends, HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
from bson import ObjectId
import base64
import json
import uuid
import time
import logging
from datetime import datetime
from typing import List, Dict, Any

from api.core.database import get_database
from api.models.schemas import (
    CreateSessionRequest,
    CreateSessionResponse,
    SendMessageRequest,
    SendMessageResponse,
    ChatMessage,
    MessageRole
)

router = APIRouter()

logger = logging.getLogger(__name__)

SAFE_FIXED_RESPONSE = (
    "I'm sorry, I'm temporarily unavailable right now. "
    "Please try again in a moment."
)


def _build_conversation_history(messages: List[Dict[str, Any]]) -> List[Dict[str, str]]:
    history: List[Dict[str, str]] = []
    for msg in messages:
        role_value = msg.get("role", "user")
        if isinstance(role_value, MessageRole):
            role_raw = role_value.value
        else:
            role_raw = str(role_value).lower()
        role = "assistant" if role_raw == MessageRole.ASSISTANT.value else "user"
        history.append({"role": role, "content": str(msg.get("content", ""))})
    return history


async def _load_full_cursor(cursor, batch_size: int = 500) -> List[Dict[str, Any]]:
    """Read all documents from a Mongo cursor in bounded batches."""
    rows: List[Dict[str, Any]] = []
    while True:
        batch = await cursor.to_list(length=batch_size)
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < batch_size:
            break
    return rows


def _to_iso_timestamp(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _serialize_chat_message(doc: Dict[str, Any]) -> Dict[str, Any]:
    role_value = doc.get("role", "user")
    if isinstance(role_value, MessageRole):
        role = role_value.value
    else:
        role = str(role_value)

    return {
        "id": doc.get("message_id") or str(doc.get("_id", "")),
        "session_id": doc.get("session_id", ""),
        "content": doc.get("content", ""),
        "role": role,
        "timestamp": _to_iso_timestamp(doc.get("timestamp")),
    }


def _encode_cursor(doc: Dict[str, Any]) -> str:
    ts = _to_iso_timestamp(doc.get("timestamp"))
    oid = str(doc.get("_id", ""))
    payload = json.dumps({"ts": ts, "oid": oid}, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(payload).decode("utf-8")


def _decode_cursor(cursor: str) -> tuple[datetime, ObjectId]:
    try:
        padding = "=" * (-len(cursor) % 4)
        raw = base64.urlsafe_b64decode(f"{cursor}{padding}".encode("utf-8"))
        data = json.loads(raw.decode("utf-8"))
        ts_raw = str(data["ts"])
        ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
        if ts.tzinfo is not None:
            ts = ts.astimezone().replace(tzinfo=None)
        oid = ObjectId(str(data["oid"]))
        return ts, oid
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid cursor") from exc


def _build_pagination(
    *,
    total_count: int,
    returned: int,
    has_more: bool,
    next_cursor: str | None,
    prev_cursor: str | None,
    window_start_ts: str | None,
    window_end_ts: str | None,
) -> Dict[str, Any]:
    return {
        "total_count": total_count,
        "returned": returned,
        "has_more": has_more,
        "next_cursor": next_cursor,
        "prev_cursor": prev_cursor,
        "window_start_ts": window_start_ts,
        "window_end_ts": window_end_ts,
    }


@router.post(
    "/sessions",
    response_model=CreateSessionResponse,
    summary="Create chat session"
)
async def create_session(
    request: CreateSessionRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Create a new chat session in MongoDB."""
    try:
        session_id = str(uuid.uuid4())
        now = datetime.utcnow()
        
        session = {
            "session_id": session_id,
            "user_id": request.user_id,
            "title": request.title or "New Conversation",
            "created_at": now,
            "last_activity": now,
            "message_count": 0
        }
        
        await db["chat_sessions"].insert_one(session)
        
        return CreateSessionResponse(
            session_id=session_id,
            created_at=now
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/messages",
    response_model=SendMessageResponse,
    summary="Send chat message"
)
async def send_message(
    msg_req: SendMessageRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Send message and get AI response via GraphCAG."""
    try:
        start_time = time.time()

        session = await db["chat_sessions"].find_one({"session_id": msg_req.session_id})
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")

        history_cursor = db["chat_messages"].find(
            {"session_id": msg_req.session_id}
        ).sort("timestamp", -1).limit(10)
        history_docs = await history_cursor.to_list(length=10)
        history_docs.reverse()
        conversation_history = _build_conversation_history(history_docs)
        
        # 1. Save user message
        user_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": msg_req.session_id,
            "user_id": msg_req.user_id,
            "content": msg_req.message,
            "role": MessageRole.USER.value,
            "timestamp": datetime.utcnow()
        }
        await db["chat_messages"].insert_one(user_message)
        
        # 2. GraphCAG-first response
        graph_metadata: Dict[str, Any] = {}
        model_used = "graphcag"
        try:
            from api.services.orchestrator import get_orchestrator

            orchestrator = await get_orchestrator()
            graph_result = await orchestrator.process(
                user_input=msg_req.message,
                session_id=msg_req.session_id,
                user_id=msg_req.user_id,
                learner_profile={"level": "B1"},
                conversation_history=conversation_history,
            )
            ai_response = str(graph_result.get("tutor_response") or "").strip()
            graph_metadata = graph_result.get("metadata", {}) or {}
            if not ai_response:
                raise RuntimeError("GraphCAG returned empty tutor_response")
            models_used = graph_metadata.get("models_used") or ["graphcag"]
            model_used = ", ".join(models_used)
        except Exception as graph_err:
            logger.error("GraphCAG failed in /chat/messages (primary): %s", graph_err)
            try:
                from api.services.orchestrator import get_orchestrator

                orchestrator = await get_orchestrator()
                retry_result = await orchestrator.process(
                    user_input=msg_req.message,
                    session_id=msg_req.session_id,
                    user_id=msg_req.user_id,
                    learner_profile={"level": "B1"},
                    conversation_history=[],
                    cache_policy="off",
                    retrieval_policy="rapid",
                    diagnosis_policy="rules",
                    generation_policy="auto",
                )
                ai_response = str(retry_result.get("tutor_response") or "").strip()
                retry_meta = retry_result.get("metadata", {}) or {}
                if not ai_response:
                    raise RuntimeError("GraphCAG degraded retry returned empty tutor_response")
                model_used = ", ".join(retry_meta.get("models_used") or ["graphcag_retry"])
                graph_metadata = {
                    **retry_meta,
                    "fallback_used": True,
                    "retry_mode": "graphcag_degraded",
                    "primary_error": str(graph_err),
                }
            except Exception as retry_err:
                logger.error("GraphCAG failed in /chat/messages (degraded retry): %s", retry_err)
                ai_response = SAFE_FIXED_RESPONSE
                model_used = "graphcag_safe_response"
                graph_metadata = {
                    "path": "safe_fixed_response",
                    "cache_hit": False,
                    "fallback_used": True,
                    "primary_error": str(graph_err),
                    "retry_error": str(retry_err),
                }
        
        # 3. Save AI message
        ai_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": msg_req.session_id,
            "content": ai_response,
            "role": MessageRole.ASSISTANT.value,
            "timestamp": datetime.utcnow(),
            "model": model_used
        }
        await db["chat_messages"].insert_one(ai_message)
        
        # 4. Update session
        await db["chat_sessions"].update_one(
            {"session_id": msg_req.session_id},
            {
                "$set": {"last_activity": datetime.utcnow()},
                "$inc": {"message_count": 2}
            }
        )
        
        processing_time = int((time.time() - start_time) * 1000)

        # Keep ConversationCache synchronized for GraphCAG next-turn reuse.
        try:
            from api.core.redis_client import ConversationCache, RedisClient

            redis_client = await RedisClient.get_instance()
            conv_cache = ConversationCache(redis_client)
            await conv_cache.add_turn(
                session_id=msg_req.session_id,
                user_message=msg_req.message,
                ai_response=ai_response,
                metadata={
                    "model": model_used,
                    "latency_ms": processing_time,
                },
            )
        except Exception as cache_err:
            logger.debug("ConversationCache sync skipped: %s", cache_err)
        
        return SendMessageResponse(
            message_id=ai_message["message_id"],
            response=ai_response,
            metadata={
                "processing_time_ms": processing_time,
                "model_used": model_used,
                "graphcag": graph_metadata,
            },
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get(
    "/sessions/{session_id}/messages",
    response_model=List[ChatMessage],
    summary="Get session messages"
)
async def get_session_messages(
    session_id: str,
    limit: int = 0,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get all messages in a session."""
    try:
        if limit < 0:
            raise HTTPException(status_code=400, detail="limit must be >= 0")

        cursor = db["chat_messages"].find(
            {"session_id": session_id}
        ).sort("timestamp", 1)

        if limit > 0:
            cursor = cursor.limit(limit)
            messages = await cursor.to_list(length=limit)
        else:
            messages = await _load_full_cursor(cursor)
        
        return [
            ChatMessage(
                role=(
                    msg["role"].value
                    if isinstance(msg.get("role"), MessageRole)
                    else str(msg.get("role", "user"))
                ),
                content=msg["content"],
                timestamp=msg["timestamp"]
            ) for msg in messages
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get(
    "/sessions/{session_id}/messages/paged",
    summary="Get session messages with cursor pagination",
)
async def get_session_messages_paged(
    session_id: str,
    limit: int = 50,
    cursor: str | None = None,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    if limit < 1:
        raise HTTPException(status_code=400, detail="limit must be >= 1")

    safe_limit = min(limit, 200)
    base_query: Dict[str, Any] = {"session_id": session_id}
    query: Dict[str, Any] = dict(base_query)

    if cursor:
        cursor_ts, cursor_oid = _decode_cursor(cursor)
        query = {
            "session_id": session_id,
            "$or": [
                {"timestamp": {"$lt": cursor_ts}},
                {"timestamp": cursor_ts, "_id": {"$lt": cursor_oid}},
            ],
        }

    docs_desc = await (
        db["chat_messages"]
        .find(query)
        .sort([("timestamp", -1), ("_id", -1)])
        .limit(safe_limit + 1)
        .to_list(length=safe_limit + 1)
    )

    has_more = len(docs_desc) > safe_limit
    docs_desc = docs_desc[:safe_limit]
    docs = list(reversed(docs_desc))

    messages = [_serialize_chat_message(doc) for doc in docs]
    total_count = await db["chat_messages"].count_documents(base_query)

    next_cursor = _encode_cursor(docs[0]) if has_more and docs else None
    prev_cursor = _encode_cursor(docs[-1]) if docs else None
    window_start_ts = _to_iso_timestamp(docs[0].get("timestamp")) if docs else None
    window_end_ts = _to_iso_timestamp(docs[-1].get("timestamp")) if docs else None

    return {
        "success": True,
        "session_id": session_id,
        "messages": messages,
        "pagination": _build_pagination(
            total_count=total_count,
            returned=len(messages),
            has_more=has_more,
            next_cursor=next_cursor,
            prev_cursor=prev_cursor,
            window_start_ts=window_start_ts,
            window_end_ts=window_end_ts,
        ),
    }


@router.get(
    "/sessions/{session_id}/messages/metadata",
    summary="Get session message metadata",
)
async def get_session_messages_metadata(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    base_query: Dict[str, Any] = {"session_id": session_id}
    total_count = await db["chat_messages"].count_documents(base_query)

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
        db["chat_messages"]
        .find(base_query)
        .sort([("timestamp", -1), ("_id", -1)])
        .limit(1)
        .to_list(length=1)
    )
    oldest_docs = await (
        db["chat_messages"]
        .find(base_query)
        .sort([("timestamp", 1), ("_id", 1)])
        .limit(1)
        .to_list(length=1)
    )

    latest = latest_docs[0]
    oldest = oldest_docs[0]

    latest_cursor = _encode_cursor(latest)
    oldest_cursor = _encode_cursor(oldest)
    latest_ts = _to_iso_timestamp(latest.get("timestamp"))
    oldest_ts = _to_iso_timestamp(oldest.get("timestamp"))

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


@router.get(
    "/sessions/user/{user_id}",
    summary="Get user sessions"
)
async def get_user_sessions(
    user_id: str,
    limit: int = 20,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get all sessions for a user."""
    try:
        cursor = db["chat_sessions"].find(
            {"user_id": user_id}
        ).sort("last_activity", -1).limit(limit)
        
        sessions = await cursor.to_list(length=limit)
        for s in sessions:
            s["_id"] = str(s["_id"])
        return sessions
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
