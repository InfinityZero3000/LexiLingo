"""
Chat routes

Endpoints for chat functionality with Google Gemini integration
"""

from fastapi import APIRouter, Depends, HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
import google.generativeai as genai
import os
from datetime import datetime
import uuid

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

# Configure Gemini API
if settings.GEMINI_API_KEY:
    genai.configure(api_key=settings.GEMINI_API_KEY)
    model = genai.GenerativeModel('gemini-pro')
else:
    model = None


@router.post(
    "/sessions",
    response_model=CreateSessionResponse,
    summary="Create chat session"
)
async def create_session(
    request: CreateSessionRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Create a new chat session.
    
    Similar to Flutter's createSession use case.
    """
    try:
        session_id = str(uuid.uuid4())
        created_at = datetime.utcnow()
        
        # Store session in MongoDB
        session = {
            "session_id": session_id,
            "user_id": request.user_id,
            "title": request.title,
            "created_at": created_at,
            "last_activity": created_at,
            "message_count": 0
        }
        
        await db["chat_sessions"].insert_one(session)
        
        return CreateSessionResponse(
            session_id=session_id,
            title=request.title or "New Conversation",
            created_at=created_at
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to create session: {str(e)}"
        )


@router.post(
    "/messages",
    response_model=SendMessageResponse,
    summary="Send chat message"
)
async def send_message(
    request: SendMessageRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Send message and get AI response.
    
    Similar to Flutter's sendMessage use case with Gemini integration.
    """
    if not model:
        raise HTTPException(
            status_code=503,
            detail="Gemini API not configured"
        )
    
    try:
        import time
        start_time = time.time()
        
        # Save user message to MongoDB
        user_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": request.session_id,
            "user_id": request.user_id,
            "content": request.message,
            "role": MessageRole.USER,
            "timestamp": datetime.utcnow()
        }
        await db["chat_messages"].insert_one(user_message)
        
        # Get AI response from Gemini
        response = model.generate_content(request.message)
        ai_response = response.text
        
        # Save AI message
        ai_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": request.session_id,
            "content": ai_response,
            "role": MessageRole.AI,
            "timestamp": datetime.utcnow()
        }
        await db["chat_messages"].insert_one(ai_message)
        
        # Update session
        await db["chat_sessions"].update_one(
            {"session_id": request.session_id},
            {
                "$set": {"last_activity": datetime.utcnow()},
                "$inc": {"message_count": 2}
            }
        )
        
        processing_time = int((time.time() - start_time) * 1000)
        
        return SendMessageResponse(
            message_id=ai_message["message_id"],
            ai_response=ai_response,
            analysis=None,  # TODO: Add AI analysis
            processing_time_ms=processing_time
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to send message: {str(e)}"
        )


@router.get(
    "/sessions/{session_id}/messages",
    response_model=list[ChatMessage],
    summary="Get session messages"
)
async def get_session_messages(
    session_id: str,
    limit: int = 100,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get all messages in a session.
    
    Similar to Flutter's getChatHistory.
    """
    try:
        cursor = db["chat_messages"].find(
            {"session_id": session_id}
        ).sort("timestamp", 1).limit(limit)
        
        messages = await cursor.to_list(length=limit)
        
        # Convert to ChatMessage model
        result = []
        for msg in messages:
            result.append(ChatMessage(
                id=msg["message_id"],
                session_id=msg["session_id"],
                content=msg["content"],
                role=MessageRole(msg["role"]),
                timestamp=msg["timestamp"]
            ))
        
        return result
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get messages: {str(e)}"
        )


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
        
        # Convert ObjectId to string
        for session in sessions:
            session["_id"] = str(session["_id"])
        
        return sessions
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get sessions: {str(e)}"
        )
