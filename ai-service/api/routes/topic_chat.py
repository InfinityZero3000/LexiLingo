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
    DifficultyLevel,
    WarmTopicCacheRequest,
    WarmTopicCacheResponse,
)
from api.services.story_service import StoryService
from api.services.topic_catalog_service import get_topic_catalog_service
from api.services.topic_preloader import get_topic_preloader
from api.services.topic_prompt_builder import TopicPromptBuilder
from api.core.redis_client import get_redis
from api.services.topic_llm_gateway import get_topic_llm_gateway
from api.services.educational_hints_parser import (
    EducationalHintsParser,
)

logger = logging.getLogger(__name__)
router = APIRouter()

# Configure Gemini API as fallback (gateway handles primary Qwen + Gemini fallback)
try:
    if settings.GEMINI_API_KEY:
        genai.configure(api_key=settings.GEMINI_API_KEY)  # type: ignore[attr-defined]
        gemini_model = genai.GenerativeModel('gemini-pro')  # type: ignore[attr-defined]
    else:
        gemini_model = None
except Exception:
    gemini_model = None

# Initialize LLM Gateway
_llm_gateway = None

def get_llm_gateway():
    global _llm_gateway
    if _llm_gateway is None:
        _llm_gateway = get_topic_llm_gateway()
    return _llm_gateway


@router.get(
    "/stories",
    response_model=ListStoriesResponse,
    summary="List available stories/topics"
)
async def list_stories(
    category: str | None = None,
    difficulty_level: DifficultyLevel | None = None,
    limit: int = 20,
    catalog_service = Depends(get_topic_catalog_service)
):
    """
    Get a list of available stories/topics for topic-based conversation.
    
    Uses TopicCatalogService with Redis caching for snappier responses.
    """
    try:
        all_stories = await catalog_service.get_topics()
        
        filtered = all_stories
        if category:
            filtered = [s for s in filtered if s.category == category]
        if difficulty_level:
            filtered = [s for s in filtered if s.difficulty_level == difficulty_level]
            
        return ListStoriesResponse(stories=filtered[:limit], total=len(filtered))
        
    except Exception as e:
        logger.error(f"Failed to list stories: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to list stories: {str(e)}"
        )


@router.post(
    "/stories/warm",
    response_model=WarmTopicCacheResponse,
    summary="Warm GraphCache for a specific topic"
)
async def warm_topic_cache(
    request: WarmTopicCacheRequest,
    preloader = Depends(get_topic_preloader)
):
    """
    Preload topic context into GraphCache (Redis).
    This makes the subsequent session start and first message instant.
    """
    try:
        import json
        bundle = await preloader.warm_cache(request.story_id, request.user_id)
        
        # Calculate size for metadata
        bundle_json = json.dumps(bundle)
        size_kb = len(bundle_json.encode('utf-8')) / 1024
        
        return WarmTopicCacheResponse(
            success=True,
            topic_id=request.story_id,
            message=f"Context warmed for '{bundle['title']}'",
            bundle_size_kb=round(size_kb, 2)
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.error(f"Failed to warm cache: {e}")
        raise HTTPException(status_code=500, detail="Internal warming failure")


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
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client = Depends(get_redis)
):
    """
    Start a new topic-based conversation session.
    
    This endpoint checks GraphCache for preloaded context to skip MongoDB lookups.
    """
    try:
        import json
        
        # 1. Check cache for preloaded context (Phase 2.4)
        cache_key = f"chat:context:{request.story_id}"
        cached_bundle = await redis_client.get(cache_key)
        
        story = None
        system_prompt = None
        
        if cached_bundle:
            logger.info(f"GraphCache HIT for topic: {request.story_id}")
            bundle = json.loads(cached_bundle)
            system_prompt = bundle.get("prime_prompt")
            # We still need the story object for metadata in the response
            # but we can try to skip full construction if we have enough info
        
        if not system_prompt or not story:
            # Fetch from DB if cache miss or need more data
            story_service = StoryService(db)
            story = await story_service.get_story_by_id(request.story_id)
            
            if not story:
                raise HTTPException(status_code=404, detail="Story not found")
            
            if not system_prompt:
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
    if not gemini_model and not get_llm_gateway():
        raise HTTPException(
            status_code=503,
            detail="AI service not configured (no LLM available)"
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
        
        # Get AI response via LLM Gateway (Qwen → Gemini fallback)
        ai_response = None
        llm_metadata = None
        gateway = get_llm_gateway()
        
        # Format conversation history for the gateway
        conversation_history = [
            {"role": msg.get("role", "user"), "content": msg.get("content", "")}
            for msg in history
        ]
        
        try:
            llm_response = await gateway.generate(
                system_prompt=system_prompt,
                user_message=request.message,
                conversation_history=conversation_history,
            )
            ai_response = llm_response.content
            llm_metadata = {
                "provider": llm_response.provider.value,
                "model": llm_response.model_name,
                "latency_ms": llm_response.latency_ms,
                "fallback_used": llm_response.fallback_used,
            }
            logger.info(
                f"Topic chat response via {llm_response.provider.value}, "
                f"latency={llm_response.latency_ms}ms, "
                f"fallback={'yes' if llm_response.fallback_used else 'no'}"
            )
        except Exception as gw_err:
            logger.warning(f"LLM gateway failed: {gw_err}, trying direct Gemini")
            # Direct Gemini fallback if gateway completely fails
            if gemini_model:
                response = gemini_model.generate_content(full_prompt)
                ai_response = response.text
                llm_metadata = {
                    "provider": "gemini",
                    "model": "gemini-pro",
                    "latency_ms": 0,
                    "fallback_used": True,
                }
            else:
                raise
        
        if not ai_response:
            raise HTTPException(status_code=500, detail="No response from AI")
        
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
        
        # Parse educational hints using enhanced parser
        clean_response, parsed_hints = EducationalHintsParser.parse(ai_response)
        
        # Convert parsed hints to dict for API response
        educational_hints_dict = None
        if parsed_hints and parsed_hints.has_hints():
            educational_hints_dict = parsed_hints.to_dict()
        
        return TopicChatResponse(
            message_id=ai_message_id,
            ai_response=ai_response,
            clean_response=clean_response,
            educational_hints=educational_hints_dict,
            processing_time_ms=processing_time,
            llm_metadata=llm_metadata,
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to send topic message: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to send message: {str(e)}"
        )


@router.get(
    "/categories",
    summary="Get available story categories"
)
async def get_categories(
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get list of available story categories."""
    try:
        story_service = StoryService(db)
        categories = await story_service.get_categories()
        return {"categories": categories}
    except Exception as e:
        logger.error(f"Failed to get categories: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get categories: {str(e)}"
        )


@router.get(
    "/topic-sessions/{session_id}",
    summary="Get topic session details"
)
async def get_topic_session(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get details of a specific topic session."""
    session = await db["chat_sessions"].find_one({"session_id": session_id})
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # Remove MongoDB _id field
    session.pop("_id", None)
    # Convert datetime fields to ISO strings
    for key in ("created_at", "last_activity"):
        if key in session and isinstance(session[key], datetime):
            session[key] = session[key].isoformat()
    
    return session


@router.get(
    "/topic-sessions/{session_id}/messages",
    summary="Get messages for a topic session"
)
async def get_topic_messages(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get all messages in a topic session."""
    # Verify session exists
    session = await db["chat_sessions"].find_one({"session_id": session_id})
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    cursor = db["chat_messages"].find(
        {"session_id": session_id}
    ).sort("timestamp", 1)
    messages = await cursor.to_list(length=200)
    
    # Clean up for response
    for msg in messages:
        msg.pop("_id", None)
        if "timestamp" in msg and isinstance(msg["timestamp"], datetime):
            msg["timestamp"] = msg["timestamp"].isoformat()
    
    return {"messages": messages}


@router.get(
    "/llm/health",
    summary="Check LLM service health"
)
async def check_llm_health():
    """Check the health status of the LLM services."""
    health = {
        "status": "ok",
        "gemini_configured": settings.GEMINI_API_KEY is not None,
        "ollama_url": getattr(settings, 'OLLAMA_BASE_URL', None),
    }
    
    # Check LLM gateway
    try:
        gateway = get_llm_gateway()
        health["gateway_available"] = gateway is not None
    except Exception:
        health["gateway_available"] = False
    
    return health
