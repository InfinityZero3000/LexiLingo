"""
Chat routes

Endpoints for chat functionality with GraphCAG-first orchestration.
"""

from fastapi import APIRouter, Depends, HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
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
