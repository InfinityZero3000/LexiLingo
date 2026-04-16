"""
Chat routes

Endpoints for chat functionality with multi-provider fallback and persistent storage.
"""

from fastapi import APIRouter, Depends, HTTPException, Request
from motor.motor_asyncio import AsyncIOMotorDatabase
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple
import base64

from api.core.database import get_database
from api.core.config import settings
from api.models.schemas import (
    CreateSessionRequest,
    CreateSessionResponse,
    SendMessageRequest,
    SendMessageResponse,
    ChatMessage,
    MessageRole
)

router = APIRouter()

# Helper to get the providers from app.state or direct import
# In a real app, these would be in a service layer

async def get_ai_response(request: Request, message: str, db: AsyncIOMotorDatabase) -> tuple[str, str]:
    """Get AI response using fallback chain."""
    # This logic is shared with main.py for now, but should ideally be in a service
    from api.main import get_groq_response, get_gemini_response, get_ollama_response
    
    # 1. Groq
    response = await get_groq_response(message, db)
    if response:
        return response, f"groq/{settings.GROQ_MODEL}"
    
    # 2. Gemini
    response = await get_gemini_response(message, db)
    if response:
        return response, "gemini-2.0-flash"
    
    # 3. Ollama
    response = await get_ollama_response(message)
    if response:
        return response, f"ollama/{settings.OLLAMA_MODEL}"
    
    return "I'm having trouble connecting to my brain. Please try again later.", "fallback"


def _encode_cursor(timestamp: datetime, message_id: str) -> str:
    payload = f"{timestamp.isoformat()}|{message_id}"
    return base64.urlsafe_b64encode(payload.encode("utf-8")).decode("utf-8")


def _decode_cursor(cursor: str) -> Tuple[datetime, str]:
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("utf-8")).decode("utf-8")
        ts_str, msg_id = raw.split("|", 1)
        return datetime.fromisoformat(ts_str), msg_id
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid cursor") from exc


def _cursor_filter(session_id: str, cursor: Optional[str]) -> Dict[str, Any]:
    base_query: Dict[str, Any] = {"session_id": session_id}
    if not cursor:
        return base_query

    cursor_ts, cursor_msg_id = _decode_cursor(cursor)
    base_query["$or"] = [
        {"timestamp": {"$lt": cursor_ts}},
        {
            "$and": [
                {"timestamp": cursor_ts},
                {"message_id": {"$lt": cursor_msg_id}},
            ]
        },
    ]
    return base_query


def _serialize_chat_message(msg: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": msg["message_id"],
        "session_id": msg["session_id"],
        "content": msg["content"],
        "role": MessageRole(msg["role"]),
        "timestamp": msg["timestamp"],
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
            title=session["title"],
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
    request: Request,
    msg_req: SendMessageRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Send message and get AI response with fallback."""
    try:
        import time
        start_time = time.time()
        
        # 1. Save user message
        user_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": msg_req.session_id,
            "user_id": msg_req.user_id,
            "content": msg_req.message,
            "role": MessageRole.USER,
            "timestamp": datetime.utcnow()
        }
        await db["chat_messages"].insert_one(user_message)
        
        # 2. Get AI response
        ai_response, model_used = await get_ai_response(request, msg_req.message, db)
        
        # 3. Save AI message
        ai_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": msg_req.session_id,
            "content": ai_response,
            "role": MessageRole.AI,
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
        
        return SendMessageResponse(
            message_id=ai_message["message_id"],
            ai_response=ai_response,
            processing_time_ms=processing_time
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
    limit: int = 100,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get all messages in a session."""
    try:
        cursor = db["chat_messages"].find(
            {"session_id": session_id}
        ).sort("timestamp", 1).limit(limit)
        
        messages = await cursor.to_list(length=limit)
        
        return [
            ChatMessage(
                id=msg["message_id"],
                session_id=msg["session_id"],
                content=msg["content"],
                role=MessageRole(msg["role"]),
                timestamp=msg["timestamp"]
            ) for msg in messages
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get(
    "/sessions/{session_id}/messages/metadata",
    summary="Get session messages metadata"
)
async def get_session_messages_metadata(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get metadata for session messages to support metadata-first restore."""
    try:
        session = await db["chat_sessions"].find_one({"session_id": session_id})
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")

        total_count = await db["chat_messages"].count_documents({"session_id": session_id})
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
                },
            }

        latest = await db["chat_messages"].find_one(
            {"session_id": session_id},
            sort=[("timestamp", -1), ("message_id", -1)],
        )
        oldest = await db["chat_messages"].find_one(
            {"session_id": session_id},
            sort=[("timestamp", 1), ("message_id", 1)],
        )

        latest_cursor = None
        latest_ts = None
        if latest:
            latest_cursor = _encode_cursor(latest["timestamp"], latest["message_id"])
            latest_ts = latest["timestamp"].isoformat()

        oldest_cursor = None
        oldest_ts = None
        if oldest:
            oldest_cursor = _encode_cursor(oldest["timestamp"], oldest["message_id"])
            oldest_ts = oldest["timestamp"].isoformat()

        return {
            "success": True,
            "session_id": session_id,
            "metadata": {
                "total_count": total_count,
                "has_messages": total_count > 0,
                "latest_cursor": latest_cursor,
                "oldest_cursor": oldest_cursor,
                "latest_ts": latest_ts,
                "oldest_ts": oldest_ts,
            },
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get(
    "/sessions/{session_id}/messages/paged",
    summary="Get paged session messages"
)
async def get_session_messages_paged(
    session_id: str,
    limit: int = 50,
    cursor: Optional[str] = None,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get session messages with cursor-based pagination (latest-first pages)."""
    try:
        safe_limit = max(1, min(limit, 200))
        query = _cursor_filter(session_id, cursor)

        raw_messages = await (
            db["chat_messages"]
            .find(query)
            .sort([("timestamp", -1), ("message_id", -1)])
            .limit(safe_limit + 1)
            .to_list(length=safe_limit + 1)
        )

        has_more = len(raw_messages) > safe_limit
        page_items = raw_messages[:safe_limit]
        page_items.reverse()

        messages = [_serialize_chat_message(msg) for msg in page_items]
        next_cursor = None
        if has_more and page_items:
            oldest = page_items[0]
            next_cursor = _encode_cursor(oldest["timestamp"], oldest["message_id"])

        window_start_ts = page_items[0]["timestamp"].isoformat() if page_items else None
        window_end_ts = page_items[-1]["timestamp"].isoformat() if page_items else None

        return {
            "success": True,
            "session_id": session_id,
            "messages": messages,
            "pagination": {
                "limit": safe_limit,
                "returned": len(messages),
                "has_more": has_more,
                "next_cursor": next_cursor,
                "window_start_ts": window_start_ts,
                "window_end_ts": window_end_ts,
            },
        }
    except HTTPException:
        raise
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
