"""
Chat routes

Endpoints for chat functionality with multi-provider fallback and persistent storage.
"""

from fastapi import APIRouter, Depends, HTTPException, Request
from motor.motor_asyncio import AsyncIOMotorDatabase
import uuid
from datetime import datetime
from typing import List, Optional

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
