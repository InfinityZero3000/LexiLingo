"""
Topic Chat Routes

Endpoints for topic-based conversation feature.
Includes starting topic sessions and sending messages within topic context.
"""

from fastapi import APIRouter, Depends, HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
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
from api.services.educational_hints_parser import (
    EducationalHintsParser,
)

logger = logging.getLogger(__name__)
router = APIRouter()

SAFE_FIXED_RESPONSE = (
    "I'm sorry, I can't respond right now. "
    "Please try again shortly."
)


async def _load_full_cursor(cursor, batch_size: int = 500) -> list[dict]:
    """Read all documents from a Mongo cursor in bounded batches."""
    rows: list[dict] = []
    while True:
        batch = await cursor.to_list(length=batch_size)
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < batch_size:
            break
    return rows


@router.get(
    "/stories",
    response_model=ListStoriesResponse,
    summary="List available stories/topics"
)
async def list_stories(
    category: str | None = None,
    difficulty_level: DifficultyLevel | None = None,
    limit: int = 20,
    bypass_cache: bool = False,
    catalog_service = Depends(get_topic_catalog_service)
):
    """
    Get a list of available stories/topics for topic-based conversation.
    
    Uses TopicCatalogService with Redis caching for snappier responses.
    """
    try:
        all_stories = await catalog_service.get_topics(bypass_cache=bypass_cache)
        
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


@router.get(
    "/categories",
    summary="List available story categories"
)
async def list_categories(
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Return all available topic categories for filtering UI."""
    try:
        story_service = StoryService(db)
        categories = await story_service.get_categories()
        return {"categories": categories}
    except Exception as e:
        logger.error(f"Failed to list categories: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to list categories: {str(e)}"
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
        import traceback; traceback.print_exc(); logger.error(f"Failed to warm cache: {e}")
        raise HTTPException(status_code=500, detail=str(e))


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
            "preferred_llm": (request.preferred_llm or "qwen").lower(),
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
            suggested_prompts=story.suggested_prompts or [],
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
        ).sort("timestamp", -1).limit(10)
        history = await history_cursor.to_list(length=10)
        history.reverse()
        
        preferred_llm = str(session.get("preferred_llm") or "graphcag").lower()

        # Always run GraphCAG first for topic sessions.
        # preferred_llm is retained for backward compatibility/telemetry only.
        ai_response = None
        llm_metadata = None
        
        # Format conversation history for GraphCAG.
        conversation_history = [
            {"role": msg.get("role", "user"), "content": msg.get("content", "")}
            for msg in history
        ]

        try:
            from api.services.orchestrator import get_orchestrator

            graph_start = time.time()
            orchestrator = await get_orchestrator()
            graph_result = await orchestrator.process(
                user_input=request.message,
                session_id=session_id,
                user_id=request.user_id,
                learner_profile={"level": session.get("difficulty_level", "B1")},
                conversation_history=conversation_history,
                retrieval_policy="rapid",
            )

            ai_response = str(graph_result.get("tutor_response") or "").strip()
            graph_metadata = graph_result.get("metadata", {}) or {}
            if not ai_response:
                raise RuntimeError("GraphCAG returned empty tutor_response")

            llm_metadata = {
                "provider": "graphcag",
                "model": ", ".join(graph_metadata.get("models_used") or ["graphcag_pipeline"]),
                "latency_ms": int((time.time() - graph_start) * 1000),
                "fallback_used": preferred_llm != "graphcag",
            }
            logger.info("Topic chat response via GraphCAG")
        except Exception as graph_err:
            logger.error("GraphCAG failed for topic chat (primary): %s", graph_err)
            try:
                from api.services.orchestrator import get_orchestrator

                retry_start = time.time()
                orchestrator = await get_orchestrator()
                retry_result = await orchestrator.process(
                    user_input=request.message,
                    session_id=session_id,
                    user_id=request.user_id,
                    learner_profile={"level": session.get("difficulty_level", "B1")},
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
                llm_metadata = {
                    "provider": "graphcag",
                    "model": ", ".join(retry_meta.get("models_used") or ["graphcag_retry"]),
                    "latency_ms": int((time.time() - retry_start) * 1000),
                    "fallback_used": True,
                    "retry_mode": "graphcag_degraded",
                }
            except Exception as retry_err:
                logger.error("GraphCAG failed for topic chat (degraded retry): %s", retry_err)
                ai_response = SAFE_FIXED_RESPONSE
                llm_metadata = {
                    "provider": "graphcag_safe_response",
                    "model": "safe_fixed_response",
                    "latency_ms": 0,
                    "fallback_used": True,
                }
        
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
    limit: int = 0,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get all messages in a topic session."""
    # Verify session exists
    session = await db["chat_sessions"].find_one({"session_id": session_id})
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
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
    """Check GraphCAG and route orchestration health."""
    health = {
        "status": "ok",
        "graphcag_mode": "enforced",
        "gemini_configured": settings.GEMINI_API_KEY is not None,
        "ollama_url": getattr(settings, 'OLLAMA_BASE_URL', None),
    }
    
    # Check GraphCAG orchestrator
    try:
        from api.services.orchestrator import get_orchestrator

        orchestrator = await get_orchestrator()
        health["graphcag_ready"] = orchestrator.is_healthy()
        health["orchestrator_stats"] = orchestrator.get_stats()
    except Exception as e:
        health["status"] = "degraded"
        health["graphcag_ready"] = False
        health["graphcag_error"] = str(e)
    
    return health
