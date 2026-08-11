"""
Chat routes

Endpoints for chat functionality with TraceCAG-first orchestration.
"""

from fastapi import APIRouter, Depends, HTTPException, Response, status
from motor.motor_asyncio import AsyncIOMotorDatabase
from pymongo.errors import OperationFailure
import uuid
import asyncio
import time
import logging
from datetime import datetime, timezone
from typing import List, Dict, Any

from api.utils.cursor import (
    build_pagination,
    decode_cursor_dt,
    encode_cursor,
    load_full_cursor,
    to_iso_timestamp,
)

from api.core.database import get_database
from api.core.auth import AuthenticatedUser, enforce_user_scope, get_current_user
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
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


def _is_cosmos_order_by_index_error(exc: Exception) -> bool:
    """Detect Cosmos Mongo API ORDER BY errors caused by missing index paths."""
    if not isinstance(exc, OperationFailure):
        return False
    msg = str(exc).lower()
    return "order-by item is excluded" in msg or "index path corresponding" in msg


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
        "timestamp": to_iso_timestamp(doc.get("timestamp")),
    }


async def _ensure_chat_session_owner(
    session_id: str,
    current_user: AuthenticatedUser,
    db: AsyncIOMotorDatabase,
) -> Dict[str, Any]:
    session = await db["chat_sessions"].find_one({"session_id": session_id})
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    owner_user_id = str(session.get("user_id") or "")
    if not owner_user_id or owner_user_id != current_user.user_id:
        raise HTTPException(status_code=403, detail="Forbidden: session ownership mismatch")
    return session


@router.post(
    "/sessions",
    response_model=CreateSessionResponse,
    summary="Create chat session"
)
async def create_session(
    request: CreateSessionRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Create a new chat session in MongoDB."""
    try:
        auth_user_id = enforce_user_scope(current_user, request.user_id)
        request = request.model_copy(update={"user_id": auth_user_id})
        session_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc)
        
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
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Chat request failed error=%s", type(e).__name__)
        raise HTTPException(status_code=500, detail="Unable to process chat request") from e


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
) -> Response:
    """Delete one owned session and its persisted messages."""
    await _ensure_chat_session_owner(session_id, current_user, db)
    await asyncio.gather(
        db["chat_messages"].delete_many({"session_id": session_id}),
        db["lexi_messages"].delete_many({"session_id": session_id}),
    )
    await asyncio.gather(
        db["chat_sessions"].delete_one({"session_id": session_id}),
        db["lexi_sessions"].delete_one({"session_id": session_id}),
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/messages",
    response_model=SendMessageResponse,
    summary="Send chat message"
)
async def send_message(
    msg_req: SendMessageRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Bound the complete request, including initialization, DB, and cache work."""
    try:
        return await asyncio.wait_for(
            _send_message_impl(msg_req, current_user, db), timeout=50.0
        )
    except asyncio.TimeoutError as exc:
        raise HTTPException(status_code=504, detail="Chat response timed out") from exc


async def _send_message_impl(
    msg_req: SendMessageRequest,
    current_user: AuthenticatedUser,
    db: AsyncIOMotorDatabase,
):
    """Send message and get AI response via TraceCAG."""
    try:
        start_time = time.time()

        auth_user_id = enforce_user_scope(current_user, msg_req.user_id)
        msg_req = msg_req.model_copy(update={"user_id": auth_user_id})
        await enforce_user_quota(
            current_user.user_id,
            "chat.messages",
            token_cost=default_token_cost_for_endpoint("chat.messages", text=msg_req.message),
            fail_closed=True,
        )

        await _ensure_chat_session_owner(msg_req.session_id, current_user, db)

        async def _fetch_history_docs() -> List[Dict[str, Any]]:
            try:
                cursor = db["chat_messages"].find(
                    {"session_id": msg_req.session_id}
                ).sort("timestamp", -1).limit(10)
                docs = await cursor.to_list(length=10)
            except Exception as exc:
                if not _is_cosmos_order_by_index_error(exc):
                    raise
                docs = await db["chat_messages"].find(
                    {"session_id": msg_req.session_id}
                ).limit(10).to_list(length=10)
            docs.reverse()
            return docs

        async def _fetch_learner_profile() -> Dict[str, Any]:
            # Resolve real learner level from Redis profile (don't hardcode B1).
            profile: Dict[str, Any] = {"level": "B1"}
            if not msg_req.user_id:
                return profile
            try:
                from api.core.redis_client import LearnerProfileCache, RedisClient
                _redis = await asyncio.wait_for(RedisClient.get_instance(), timeout=1.5)
                _cached = await asyncio.wait_for(
                    LearnerProfileCache(_redis).get_profile(msg_req.user_id), timeout=1.5
                )
                if _cached:
                    profile = {**profile, **_cached}
            except Exception as _lp_err:
                logger.debug("Learner profile Redis lookup skipped: %s", _lp_err)
            return profile

        # Independent lookups (Mongo history, Redis profile) — run concurrently
        # instead of paying their latency back-to-back on the request path.
        history_docs, learner_profile = await asyncio.gather(
            _fetch_history_docs(), _fetch_learner_profile()
        )
        conversation_history = _build_conversation_history(history_docs)

        # 1. Save user message (fire-and-forget — don't block the AI call)
        user_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": msg_req.session_id,
            "user_id": msg_req.user_id,
            "content": msg_req.message,
            "role": MessageRole.USER.value,
            "timestamp": datetime.now(timezone.utc)
        }
        import asyncio as _asyncio
        _save_user_msg_task = _asyncio.ensure_future(
            db["chat_messages"].insert_one(user_message)
        )

        # 2. TraceCAG-first response
        graph_metadata: Dict[str, Any] = {}
        observation_trace_result: Dict[str, Any] = {}
        model_used = "trace-cag"
        try:
            from api.services.orchestrator import get_orchestrator

            orchestrator = await get_orchestrator()
            graph_result = await _asyncio.wait_for(
                orchestrator.process(
                    user_input=msg_req.message,
                    session_id=msg_req.session_id,
                    user_id=msg_req.user_id,
                    learner_profile=learner_profile,
                    conversation_history=conversation_history,
                ),
                timeout=30.0,
            )
            ai_response = str(graph_result.get("tutor_response") or "").strip()
            graph_metadata = graph_result.get("metadata", {}) or {}
            observation_trace_result = graph_result
            if not ai_response:
                raise RuntimeError("TraceCAG returned empty tutor_response")
            models_used = graph_metadata.get("models_used") or ["trace-cag"]
            model_used = ", ".join(models_used)
        except Exception as graph_err:
            logger.error("TraceCAG failed in /chat/messages (primary): %s", graph_err)
            try:
                from api.services.orchestrator import get_orchestrator

                orchestrator = await get_orchestrator()
                retry_result = await _asyncio.wait_for(
                    orchestrator.process(
                        user_input=msg_req.message,
                        session_id=msg_req.session_id,
                        user_id=msg_req.user_id,
                        learner_profile=learner_profile,
                        conversation_history=[],
                        cache_policy="off",
                        retrieval_policy="rapid",
                        diagnosis_policy="rules",
                        generation_policy="auto",
                    ),
                    timeout=15.0,
                )
                ai_response = str(retry_result.get("tutor_response") or "").strip()
                retry_meta = retry_result.get("metadata", {}) or {}
                if not ai_response:
                    raise RuntimeError("TraceCAG degraded retry returned empty tutor_response")
                model_used = ", ".join(retry_meta.get("models_used") or ["trace-cag_retry"])
                graph_metadata = {
                    **retry_meta,
                    "fallback_used": True,
                    "retry_mode": "trace-cag_degraded",
                    "primary_error_type": type(graph_err).__name__,
                }
                observation_trace_result = retry_result
            except Exception as retry_err:
                logger.error("TraceCAG failed in /chat/messages (degraded retry): %s", retry_err)
                ai_response = SAFE_FIXED_RESPONSE
                model_used = "trace-cag_safe_response"
                graph_metadata = {
                    "path": "safe_fixed_response",
                    "cache_hit": False,
                    "fallback_used": True,
                    "primary_error_type": type(graph_err).__name__,
                    "retry_error_type": type(retry_err).__name__,
                }
        
        # 3. Save AI message + 4. Update session — run in parallel, also await user msg
        ai_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": msg_req.session_id,
            "content": ai_response,
            "role": MessageRole.ASSISTANT.value,
            "timestamp": datetime.now(timezone.utc),
            "model": model_used
        }
        _now = datetime.now(timezone.utc)
        persistence_results = await _asyncio.gather(
            _save_user_msg_task,
            db["chat_messages"].insert_one(ai_message),
            db["chat_sessions"].update_one(
                {"session_id": msg_req.session_id},
                {
                    "$set": {"last_activity": _now},
                    "$inc": {"message_count": 2}
                }
            ),
            return_exceptions=True,
        )
        persistence_errors = [result for result in persistence_results if isinstance(result, Exception)]
        if persistence_errors:
            logger.error(
                "Chat persistence failed operations=%d first_error=%s",
                len(persistence_errors),
                type(persistence_errors[0]).__name__,
            )
            raise RuntimeError("Chat persistence failed")

        observation_meta: Dict[str, Any] = {}
        try:
            from api.services.learner_observation_spool import (
                persist_trace_observations,
            )

            observation_meta = await persist_trace_observations(
                user_id=msg_req.user_id,
                session_id=msg_req.session_id,
                turn_id=user_message["message_id"],
                trace_result=observation_trace_result,
            )
        except Exception as observation_err:
            logger.error("Learner observation durability degraded: %s", observation_err)
            observation_meta = {"observation_durability_degraded": True}
        
        processing_time = int((time.time() - start_time) * 1000)

        # Keep ConversationCache synchronized for TraceCAG next-turn reuse.
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
                **observation_meta,
                "model_used": model_used,
                "trace-cag": graph_metadata,
            },
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Chat request failed error=%s", type(e).__name__)
        raise HTTPException(status_code=500, detail="Unable to process chat request") from e


@router.get(
    "/sessions/{session_id}/messages",
    response_model=List[ChatMessage],
    summary="Get session messages"
)
async def get_session_messages(
    session_id: str,
    limit: int = 0,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get all messages in a session."""
    try:
        await _ensure_chat_session_owner(session_id, current_user, db)
        if limit < 0:
            raise HTTPException(status_code=400, detail="limit must be >= 0")

        try:
            cursor = db["chat_messages"].find(
                {"session_id": session_id}
            ).sort("timestamp", 1)

            if limit > 0:
                cursor = cursor.limit(limit)
                messages = await cursor.to_list(length=limit)
            else:
                messages = await load_full_cursor(cursor)
        except Exception as exc:
            if not _is_cosmos_order_by_index_error(exc):
                raise
            fallback_cursor = db["chat_messages"].find({"session_id": session_id})
            if limit > 0:
                fallback_cursor = fallback_cursor.limit(limit)
                messages = await fallback_cursor.to_list(length=limit)
            else:
                messages = await load_full_cursor(fallback_cursor)
            messages.sort(key=lambda row: row.get("timestamp") or datetime.min)
        
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
    except HTTPException:
        raise
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
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    await _ensure_chat_session_owner(session_id, current_user, db)

    if limit < 1:
        raise HTTPException(status_code=400, detail="limit must be >= 1")

    safe_limit = min(limit, 200)
    base_query: Dict[str, Any] = {"session_id": session_id}
    query: Dict[str, Any] = dict(base_query)

    if cursor:
        cursor_ts, cursor_oid = decode_cursor_dt(cursor)
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


@router.get(
    "/sessions/{session_id}/messages/metadata",
    summary="Get session message metadata",
)
async def get_session_messages_metadata(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    await _ensure_chat_session_owner(session_id, current_user, db)

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


@router.get(
    "/sessions/user/{user_id}",
    summary="Get user sessions"
)
async def get_user_sessions(
    user_id: str,
    limit: int = 20,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get all sessions for a user."""
    try:
        enforce_user_scope(current_user, user_id)
        cursor = db["chat_sessions"].find(
            {"user_id": user_id}
        ).sort("last_activity", -1).limit(limit)
        
        sessions = await cursor.to_list(length=limit)
        for s in sessions:
            s["_id"] = str(s["_id"])
        return sessions
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
