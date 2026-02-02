"""
Topic Chat Routes

Endpoints for topic-based conversation feature.
Includes starting topic sessions and sending messages within topic context.
"""

from fastapi import APIRouter, Depends, HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
import google.generativeai as genai
from datetime import datetime
import uuid
import time
import logging

from api.core.database import get_database
from api.core.config import settings
from api.models.story_schemas import (
    StartTopicSessionRequest,
    StartTopicSessionResponse,
    TopicChatRequest,
    TopicChatResponse,
    ListStoriesRequest,
    ListStoriesResponse,
    StoryListItem,
    EducationalHints,
    GrammarCorrection,
    VocabularyHint,
    DifficultyLevel,
)
from api.services.story_service import StoryService
from api.services.topic_prompt_builder import TopicPromptBuilder

logger = logging.getLogger(__name__)
router = APIRouter()

# Configure Gemini API
if settings.GEMINI_API_KEY:
    genai.configure(api_key=settings.GEMINI_API_KEY)
    gemini_model = genai.GenerativeModel('gemini-pro')
else:
    gemini_model = None


@router.get(
    "/stories",
    response_model=ListStoriesResponse,
    summary="List available stories/topics"
)
async def list_stories(
    category: str | None = None,
    difficulty_level: DifficultyLevel | None = None,
    limit: int = 20,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get a list of available stories/topics for topic-based conversation.
    
    Supports filtering by category and difficulty level.
    """
    try:
        story_service = StoryService(db)
        stories, total = await story_service.list_stories(
            category=category,
            difficulty_level=difficulty_level,
            limit=limit
        )
        
        return ListStoriesResponse(stories=stories, total=total)
        
    except Exception as e:
        logger.error(f"Failed to list stories: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to list stories: {str(e)}"
        )


@router.get(
    "/stories/{story_id}",
    summary="Get story details"
)
async def get_story(
    story_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get full details of a specific story."""
    story_service = StoryService(db)
    story = await story_service.get_story_by_id(story_id)
    
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    
    return story


@router.post(
    "/topic-sessions",
    response_model=StartTopicSessionResponse,
    summary="Start a topic-based chat session"
)
async def start_topic_session(
    request: StartTopicSessionRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Start a new topic-based conversation session.
    
    This endpoint:
    1. Fetches story metadata from MongoDB
    2. Builds a dynamic system prompt with story context
    3. Creates a new session linked to the story
    4. Returns the AI's opening message
    """
    try:
        # Fetch story
        story_service = StoryService(db)
        story = await story_service.get_story_by_id(request.story_id)
        
        if not story:
            raise HTTPException(status_code=404, detail="Story not found")
        
        # Build system prompt
        system_prompt = TopicPromptBuilder.build_master_prompt(story)
        
        # Create session
        session_id = str(uuid.uuid4())
        created_at = datetime.utcnow()
        
        session = {
            "session_id": session_id,
            "user_id": request.user_id,
            "story_id": request.story_id,
            "title": request.session_title or story.title.en,
            "system_prompt": system_prompt,
            "session_type": "topic_based",
            "difficulty_level": story.difficulty_level.value,
            "created_at": created_at,
            "last_activity": created_at,
            "message_count": 0
        }
        
        await db["chat_sessions"].insert_one(session)
        
        # Get opening message from story
        opening_message = story.conversation_flow.opening_prompt
        
        # Store opening message as AI message
        ai_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": session_id,
            "content": opening_message,
            "role": "assistant",
            "timestamp": created_at,
            "is_opening": True
        }
        await db["chat_messages"].insert_one(ai_message)
        
        # Build response
        story_list_item = StoryListItem(
            story_id=story.story_id,
            title=story.title,
            difficulty_level=story.difficulty_level,
            category=story.category,
            estimated_minutes=story.estimated_minutes,
            cover_image_url=story.cover_image_url,
            tags=story.tags
        )
        
        return StartTopicSessionResponse(
            session_id=session_id,
            story=story_list_item,
            role_persona=story.role_persona,
            opening_message=opening_message,
            vocabulary_preview=story.vocabulary_list[:5],  # First 5 vocab items
            created_at=created_at
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to start topic session: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to start topic session: {str(e)}"
        )


@router.post(
    "/topic-sessions/{session_id}/messages",
    response_model=TopicChatResponse,
    summary="Send message in topic session"
)
async def send_topic_message(
    session_id: str,
    request: TopicChatRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Send a message in a topic-based conversation.
    
    The AI will respond in character based on the story's role persona,
    and provide educational hints (grammar/vocabulary) when appropriate.
    """
    if not gemini_model:
        raise HTTPException(
            status_code=503,
            detail="AI service not configured (Gemini API key missing)"
        )
    
    try:
        start_time = time.time()
        
        # Get session
        session = await db["chat_sessions"].find_one({"session_id": session_id})
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        if session.get("session_type") != "topic_based":
            raise HTTPException(
                status_code=400, 
                detail="This endpoint is only for topic-based sessions"
            )
        
        # Get conversation history
        history_cursor = db["chat_messages"].find(
            {"session_id": session_id}
        ).sort("timestamp", 1).limit(10)
        history = await history_cursor.to_list(length=10)
        
        # Build prompt with context
        system_prompt = session.get("system_prompt", "")
        
        # Format conversation for Gemini
        conversation_text = ""
        for msg in history:
            role_label = "User" if msg.get("role") == "user" else "Assistant"
            conversation_text += f"{role_label}: {msg.get('content', '')}\n"
        
        conversation_text += f"User: {request.message}\n"
        
        # Create the full prompt
        full_prompt = f"""[SYSTEM INSTRUCTIONS]
{system_prompt}

[CONVERSATION SO FAR]
{conversation_text}

[YOUR RESPONSE]
Respond as your character. Include [💡 Tip] or [📘] notes if the user made errors or asked about vocabulary."""
        
        # Get AI response
        response = gemini_model.generate_content(full_prompt)
        ai_response = response.text
        
        # Save user message
        user_message = {
            "message_id": str(uuid.uuid4()),
            "session_id": session_id,
            "user_id": request.user_id,
            "content": request.message,
            "role": "user",
            "timestamp": datetime.utcnow()
        }
        await db["chat_messages"].insert_one(user_message)
        
        # Save AI message
        ai_message_id = str(uuid.uuid4())
        ai_message_doc = {
            "message_id": ai_message_id,
            "session_id": session_id,
            "content": ai_response,
            "role": "assistant",
            "timestamp": datetime.utcnow()
        }
        await db["chat_messages"].insert_one(ai_message_doc)
        
        # Update session
        await db["chat_sessions"].update_one(
            {"session_id": session_id},
            {
                "$set": {"last_activity": datetime.utcnow()},
                "$inc": {"message_count": 2}
            }
        )
        
        processing_time = int((time.time() - start_time) * 1000)
        
        # Parse educational hints from response (basic extraction)
        educational_hints = _extract_educational_hints(ai_response)
        
        return TopicChatResponse(
            message_id=ai_message_id,
            ai_response=ai_response,
            educational_hints=educational_hints,
            processing_time_ms=processing_time
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to send topic message: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to send message: {str(e)}"
        )


def _extract_educational_hints(response: str) -> EducationalHints | None:
    """
    Extract educational hints from AI response.
    
    Looks for [💡 Tip: ...] and [📘 ...] patterns.
    """
    import re
    
    tips = re.findall(r'\[💡\s*Tip:\s*([^\]]+)\]', response)
    vocab_hints = re.findall(r"\[📘\s*'([^']+)'\s*means\s*([^\]]+)\]", response)
    
    if not tips and not vocab_hints:
        return None
    
    hints = EducationalHints()
    
    for tip in tips:
        hints.grammar_corrections.append(
            GrammarCorrection(
                original="",  # Would need more parsing to extract
                corrected="",
                explanation=tip.strip()
            )
        )
    
    for term, definition in vocab_hints:
        hints.vocabulary_hints.append(
            VocabularyHint(
                term=term.strip(),
                definition=definition.strip()
            )
        )
    
    return hints if (hints.grammar_corrections or hints.vocabulary_hints) else None
