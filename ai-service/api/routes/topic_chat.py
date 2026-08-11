"""
Topic Chat Routes

Endpoints for topic-based conversation feature.
Includes starting topic sessions and sending messages within topic context.
"""

import asyncio
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone
import json
import uuid
import time
import logging

from fastapi.responses import StreamingResponse

from api.utils.cursor import (
    build_pagination,
    decode_cursor_dt,
    encode_cursor,
    load_full_cursor,
    to_iso_timestamp,
)

from api.core.database import get_database
from api.core.auth import AuthenticatedUser, enforce_user_scope, get_current_user
from api.repositories.topic_chat_repository import TopicChatRepository
from api.core.audit_emitter import emit_ai_audit_event
from api.core.config import settings
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
from api.services.subgraph_hot_cache import warm_subgraph, get_subgraph
from api.models.story_schemas import (
    StartTopicSessionRequest,
    StartTopicSessionResponse,
    TopicChatRequest,
    TopicChatResponse,
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
from api.services.topic_chat_service import (
    call_tracecag_with_retry,
    persist_topic_turn,
    resolve_kg_seeds,
    sanitize_topic_response,
    stream_tracecag_topic_message,
)

logger = logging.getLogger(__name__)
router = APIRouter()

SAFE_FIXED_RESPONSE = (
    "I'm sorry, I can't respond right now. "
    "Please try again shortly."
)

from api.services.trace_cag.env_helpers import _env_float  # noqa: PLC2701

TOPIC_TRACECAG_TIMEOUT_SEC = _env_float("TOPIC_TRACECAG_TIMEOUT_SEC", 12.0)
TOPIC_TRACECAG_RETRY_TIMEOUT_SEC = _env_float("TOPIC_TRACECAG_RETRY_TIMEOUT_SEC", 6.0)


def _normalize_preferred_llm(value: str | None) -> str:
    normalized = str(value or "tracecag").strip().lower().replace("_", "-")
    if normalized in {"tracecag", "trace-cag"}:
        return "trace-cag"
    return normalized


def _story_list_item_payload(story: StoryListItem | dict) -> dict:
    if hasattr(story, "model_dump"):
        payload = story.model_dump(mode="json")
    else:
        payload = dict(story)

    title = payload.get("title")
    if isinstance(title, str):
        payload["title"] = {"en": title, "vi": title}

    difficulty = payload.get("difficulty_level")
    if hasattr(difficulty, "value"):
        payload["difficulty_level"] = difficulty.value

    payload.setdefault("estimated_minutes", 15)
    payload.setdefault("cover_image_url", None)
    payload.setdefault("suggested_prompts", [])
    payload.setdefault("tags", [])
    return payload


def _serialize_topic_message(doc: dict) -> dict:
    return {
        "id": doc.get("message_id") or str(doc.get("_id", "")),
        "message_id": doc.get("message_id") or str(doc.get("_id", "")),
        "session_id": doc.get("session_id", ""),
        "content": doc.get("content", ""),
        "role": doc.get("role", "user"),
        "timestamp": to_iso_timestamp(doc.get("timestamp")),
    }


async def _ensure_topic_session_owner(
    session_id: str,
    current_user: AuthenticatedUser,
    repo: TopicChatRepository,
) -> dict:
    session = await repo.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    owner_user_id = str(session.get("user_id") or "")
    if owner_user_id and owner_user_id != current_user.user_id:
        raise HTTPException(status_code=403, detail="Forbidden: session ownership mismatch")
    return session


@router.get(
    "/stories",
    response_model=ListStoriesResponse,
    summary="List available stories/topics"
)
async def list_stories(
    category: str | None = None,
    difficulty_level: DifficultyLevel | None = None,
    limit: int = 100,
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
            
        response_payload = {
            "stories": [_story_list_item_payload(story) for story in filtered[:limit]],
            "total": len(filtered),
        }
        return JSONResponse(content=response_payload)
        
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
    preloader = Depends(get_topic_preloader),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Preload topic context into GraphCache (Redis).
    This makes the subsequent session start and first message instant.
    """
    try:
        auth_user_id = enforce_user_scope(current_user, request.user_id)
        request = request.model_copy(update={"user_id": auth_user_id})

        import json
        bundle = await preloader.warm_cache(request.story_id, request.user_id)

        # Calculate size for metadata
        bundle_json = json.dumps(bundle, default=str)
        size_kb = len(bundle_json.encode('utf-8')) / 1024
        cache_metadata = bundle.get("cache_metadata", {}) or {}
        
        return WarmTopicCacheResponse(
            success=True,
            topic_id=request.story_id,
            message=f"Context warmed for '{bundle['title']}'",
            bundle_size_kb=round(size_kb, 2),
            context_cache_warmed=bool(cache_metadata.get("context_cache_warmed")),
            kg_cache_warmed=bool(cache_metadata.get("kg_cache_warmed")),
            kg_seed_count=int(cache_metadata.get("kg_seed_count") or 0),
            kg_node_count=int(cache_metadata.get("kg_node_count") or 0),
            kg_path_count=int(cache_metadata.get("kg_path_count") or 0),
        )
    except HTTPException:
        raise
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
    request_context: Request,
    request: StartTopicSessionRequest,
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client = Depends(get_redis),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Start a new topic-based conversation session.
    
    This endpoint checks GraphCache for preloaded context to skip MongoDB lookups.
    """
    try:
        request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
        auth_user_id = enforce_user_scope(current_user, request.user_id)
        request = request.model_copy(update={"user_id": auth_user_id})

        quota = await enforce_user_quota(
            current_user.user_id,
            "topic.start_session",
            token_cost=default_token_cost_for_endpoint("topic.start_session"),
            fail_closed=True,
        )

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
        
        # Always fetch story — needed for session metadata and to check freshness.
        story_service = StoryService(db)
        story = await story_service.get_story_by_id(request.story_id)
        if not story:
            raise HTTPException(status_code=404, detail="Story not found")

        # Use cached system_prompt if available; build from fresh story otherwise.
        if not system_prompt:
            system_prompt = TopicPromptBuilder.build_master_prompt(story)
        
        # Create session
        session_id = str(uuid.uuid4())
        created_at = datetime.now(timezone.utc)
        repo = TopicChatRepository(db)

        session = {
            "session_id": session_id,
            "user_id": request.user_id,
            "story_id": request.story_id,
            "title": request.session_title or story.title.en,
            "system_prompt": system_prompt,
            "session_type": "topic_based",
            "preferred_llm": _normalize_preferred_llm(request.preferred_llm),
            "difficulty_level": story.difficulty_level.value,
            "created_at": created_at,
            "last_activity": created_at,
            "message_count": 0,
        }

        await repo.create_session(session)

        # Warm KG subgraph for this topic in the background.
        # Seeds are stored in MongoDB session doc for use in send_topic_message.
        async def _warm_and_update_session():
            try:
                subgraph = await warm_subgraph(
                    story_id=request.story_id,
                    story_vocab=story.vocabulary_list,
                    story_grammar=story.grammar_points,
                    story_level=story.difficulty_level.value,
                    redis_client=redis_client,
                )
                kg_seeds = subgraph.get("seed_concepts", [])
                if kg_seeds:
                    await repo.update_session_kg(
                        session_id, kg_seeds, subgraph.get("topic_fingerprint", "")
                    )
            except Exception as exc:
                logger.warning("Background KG warm failed for session %s: %s", session_id, exc)

        asyncio.create_task(_warm_and_update_session())

        opening_message = story.conversation_flow.opening_prompt

        await repo.insert_message({
            "message_id": str(uuid.uuid4()),
            "session_id": session_id,
            "content": opening_message,
            "role": "assistant",
            "timestamp": created_at,
            "is_opening": True,
        })
        
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
        
        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "topic.start_session",
                "status": "success",
                "session_id": session_id,
                "story_id": request.story_id,
                "quota": {
                    "rpm_used": quota.rpm_used,
                    "rpm_limit": quota.rpm_limit,
                    "rpd_used": quota.rpd_used,
                    "rpd_limit": quota.rpd_limit,
                    "tpm_used": quota.tpm_used,
                    "tpm_limit": quota.tpm_limit,
                    "tpd_used": quota.tpd_used,
                    "tpd_limit": quota.tpd_limit,
                },
            }
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
        import traceback
        logger.error(f"Failed to start topic session: {e}\n{traceback.format_exc()}")
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
    request_context: Request,
    session_id: str,
    request: TopicChatRequest,
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client = Depends(get_redis),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Send a message in a topic-based conversation.
    
    The AI will respond in character based on the story's role persona,
    and provide educational hints (grammar/vocabulary) when appropriate.
    """
    try:
        start_time = time.time()
        request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
        auth_user_id = enforce_user_scope(current_user, request.user_id)
        request = request.model_copy(update={"user_id": auth_user_id})

        quota = await enforce_user_quota(
            current_user.user_id,
            "topic.send_message",
            token_cost=default_token_cost_for_endpoint("topic.send_message", text=request.message),
            fail_closed=True,
        )
        
        repo = TopicChatRepository(db)
        session = await _ensure_topic_session_owner(session_id, current_user, repo)

        if session.get("session_type") != "topic_based":
            raise HTTPException(status_code=400, detail="This endpoint is only for topic-based sessions")

        history = await repo.get_history(session_id, limit=10)
        
        preferred_llm = _normalize_preferred_llm(session.get("preferred_llm"))

        kg_seeds = await resolve_kg_seeds(session, redis_client)

        conversation_history = [
            {"role": msg.get("role", "user"), "content": msg.get("content", "")}
            for msg in history
        ]

        tracecag_result = await call_tracecag_with_retry(
            message=request.message,
            session_id=session_id,
            user_id=request.user_id,
            difficulty_level=session.get("difficulty_level", "B1"),
            conversation_history=conversation_history,
            kg_seeds=kg_seeds,
            preferred_llm=preferred_llm,
            topic_system_prompt=session.get("system_prompt"),
        )

        if not tracecag_result.ai_response:
            raise HTTPException(status_code=500, detail="No response from AI")

        clean_response, parsed_hints = EducationalHintsParser.parse(tracecag_result.ai_response)
        display_response = sanitize_topic_response(clean_response or tracecag_result.ai_response)

        ai_message_id = await persist_topic_turn(
            session_id=session_id,
            user_id=request.user_id,
            message=request.message,
            ai_response=display_response,
            repo=repo,
        )
        
        processing_time = int((time.time() - start_time) * 1000)
        
        # Convert parsed hints to dict for API response
        educational_hints_dict = None
        if parsed_hints and parsed_hints.has_hints():
            educational_hints_dict = parsed_hints.to_dict()
        
        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "topic.send_message",
                "status": "success",
                "session_id": session_id,
                "latency_ms": processing_time,
                "quota": {
                    "rpm_used": quota.rpm_used,
                    "rpm_limit": quota.rpm_limit,
                    "rpd_used": quota.rpd_used,
                    "rpd_limit": quota.rpd_limit,
                    "tpm_used": quota.tpm_used,
                    "tpm_limit": quota.tpm_limit,
                    "tpd_used": quota.tpd_used,
                    "tpd_limit": quota.tpd_limit,
                },
            }
        )

        return TopicChatResponse(
            message_id=ai_message_id,
            ai_response=display_response,
            clean_response=display_response,
            educational_hints=educational_hints_dict,
            processing_time_ms=processing_time,
            llm_metadata=tracecag_result.llm_metadata,
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to send topic message: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to send message: {str(e)}"
        )


TOPIC_STREAM_QUOTA_TIMEOUT_SEC = _env_float("TOPIC_STREAM_QUOTA_TIMEOUT_SEC", 5.0)


@router.post(
    "/topic-sessions/{session_id}/messages/stream",
    summary="Send message in topic session — streaming SSE variant",
)
async def send_topic_message_stream(
    request_context: Request,
    session_id: str,
    request: TopicChatRequest,
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client = Depends(get_redis),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> StreamingResponse:
    """
    Send a message in a topic-based conversation — streaming SSE variant.

    Same pipeline and 2-tier TraceCAG fallback as the JSON endpoint above,
    just with the response delivered as text/event-stream so the client can
    show a "thinking" state immediately and the reply word-by-word instead
    of waiting for the whole turn to finish. See
    `topic_chat_service.stream_tracecag_topic_message` for the event
    sequence (thinking/heartbeat/chunk/done/error).
    """
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
    auth_user_id = enforce_user_scope(current_user, request.user_id)
    request = request.model_copy(update={"user_id": auth_user_id})

    try:
        quota = await asyncio.wait_for(
            enforce_user_quota(
                current_user.user_id,
                "topic.send_message",
                token_cost=default_token_cost_for_endpoint(
                    "topic.send_message", text=request.message
                ),
                fail_closed=True,
            ),
            timeout=TOPIC_STREAM_QUOTA_TIMEOUT_SEC,
        )
    except asyncio.TimeoutError as exc:
        logger.error(
            "Topic /stream quota check timed out after %.1fs",
            TOPIC_STREAM_QUOTA_TIMEOUT_SEC,
        )
        raise HTTPException(
            status_code=503,
            detail="AI quota service is temporarily unavailable",
        ) from exc

    repo = TopicChatRepository(db)
    session = await _ensure_topic_session_owner(session_id, current_user, repo)
    if session.get("session_type") != "topic_based":
        raise HTTPException(status_code=400, detail="This endpoint is only for topic-based sessions")

    history = await repo.get_history(session_id, limit=10)
    kg_seeds = await resolve_kg_seeds(session, redis_client)
    conversation_history = [
        {"role": msg.get("role", "user"), "content": msg.get("content", "")}
        for msg in history
    ]

    return StreamingResponse(
        stream_tracecag_topic_message(
            message=request.message,
            session_id=session_id,
            user_id=request.user_id,
            difficulty_level=session.get("difficulty_level", "B1"),
            conversation_history=conversation_history,
            kg_seeds=kg_seeds,
            topic_system_prompt=session.get("system_prompt"),
            repo=repo,
            quota=quota,
            start_time=start_time,
            request_id=request_id,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get(
    "/topic-sessions/{session_id}",
    summary="Get topic session details"
)
async def get_topic_session(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Get details of a specific topic session."""
    repo = TopicChatRepository(db)
    session = await _ensure_topic_session_owner(session_id, current_user, repo)
    session.pop("_id", None)
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
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Get all messages in a topic session."""
    repo = TopicChatRepository(db)
    await _ensure_topic_session_owner(session_id, current_user, repo)

    if limit < 0:
        raise HTTPException(status_code=400, detail="limit must be >= 0")

    messages = await repo.get_messages(session_id, limit=limit)
    for msg in messages:
        msg.pop("_id", None)
        if "timestamp" in msg and isinstance(msg["timestamp"], datetime):
            msg["timestamp"] = msg["timestamp"].isoformat()
    return {"messages": messages}


@router.get(
    "/topic-sessions/{session_id}/messages/paged",
    summary="Get topic messages with cursor pagination",
)
async def get_topic_messages_paged(
    session_id: str,
    limit: int = 50,
    cursor: str | None = None,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    repo = TopicChatRepository(db)
    await _ensure_topic_session_owner(session_id, current_user, repo)

    if limit < 1:
        raise HTTPException(status_code=400, detail="limit must be >= 1")

    docs, has_more = await repo.get_messages_paged(session_id, limit=limit, cursor=cursor)
    messages = [_serialize_topic_message(doc) for doc in docs]
    total_count = await repo.count_messages(session_id)
    next_cursor = encode_cursor(docs[0]) if has_more and docs else None
    prev_cursor = encode_cursor(docs[-1]) if docs else None
    window_start_ts = to_iso_timestamp(docs[0].get("timestamp")) if docs else None
    window_end_ts = to_iso_timestamp(docs[-1].get("timestamp")) if docs else None

    return {
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
    "/topic-sessions/{session_id}/messages/metadata",
    summary="Get topic message metadata",
)
async def get_topic_messages_metadata(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    repo = TopicChatRepository(db)
    await _ensure_topic_session_owner(session_id, current_user, repo)

    total_count = await repo.count_messages(session_id)

    if total_count == 0:
        return {
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
            }
        }

    latest = await repo.get_latest_message(session_id)
    oldest = await repo.get_oldest_message(session_id)
    latest_cursor = encode_cursor(latest)
    oldest_cursor = encode_cursor(oldest)
    latest_ts = to_iso_timestamp(latest.get("timestamp"))
    oldest_ts = to_iso_timestamp(oldest.get("timestamp"))

    return {
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
        }
    }


@router.get(
    "/llm/health",
    summary="Check LLM service health"
)
async def check_llm_health():
    """Check TraceCAG and route orchestration health."""
    health = {
        "status": "ok",
        "trace-cag_mode": "enforced",
        "gemini_configured": settings.GEMINI_API_KEY is not None,
        "ollama_url": getattr(settings, 'OLLAMA_BASE_URL', None),
    }
    
    # Check TraceCAG orchestrator
    try:
        from api.services.orchestrator import get_orchestrator

        orchestrator = await get_orchestrator()
        health["trace-cag_ready"] = orchestrator.is_healthy()
        health["orchestrator_stats"] = orchestrator.get_stats()
    except Exception as e:
        health["status"] = "degraded"
        health["trace-cag_ready"] = False
        health["trace-cag_error"] = str(e)
    
    return health
