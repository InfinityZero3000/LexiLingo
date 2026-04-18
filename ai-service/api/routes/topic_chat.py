"""
Topic Chat Routes

Endpoints for topic-based conversation feature.
Includes starting topic sessions and sending messages within topic context.
"""

import asyncio
from fastapi import APIRouter, Depends, HTTPException, Request
from motor.motor_asyncio import AsyncIOMotorDatabase
from bson import ObjectId
import base64
import json
from datetime import datetime
import uuid
import time
import logging
import re

from api.core.database import get_database
from api.core.auth import AuthenticatedUser, enforce_user_scope, get_current_user
from api.core.audit_emitter import emit_ai_audit_event
from api.core.config import settings
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
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

TOPIC_GRAPHCAG_TIMEOUT_SEC = float(getattr(settings, "TOPIC_GRAPHCAG_TIMEOUT_SEC", 12.0))
TOPIC_GRAPHCAG_RETRY_TIMEOUT_SEC = float(
    getattr(settings, "TOPIC_GRAPHCAG_RETRY_TIMEOUT_SEC", 6.0)
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


def _to_iso_timestamp(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _serialize_topic_message(doc: dict) -> dict:
    return {
        "id": doc.get("message_id") or str(doc.get("_id", "")),
        "message_id": doc.get("message_id") or str(doc.get("_id", "")),
        "session_id": doc.get("session_id", ""),
        "content": doc.get("content", ""),
        "role": doc.get("role", "user"),
        "timestamp": _to_iso_timestamp(doc.get("timestamp")),
    }


def _encode_cursor(doc: dict) -> str:
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
) -> dict:
    return {
        "total_count": total_count,
        "returned": returned,
        "has_more": has_more,
        "next_cursor": next_cursor,
        "prev_cursor": prev_cursor,
        "window_start_ts": window_start_ts,
        "window_end_ts": window_end_ts,
    }


def _sanitize_topic_response(text: str) -> str:
    """Best-effort cleanup for malformed JSON tails leaked by model outputs."""
    candidate = (text or "").strip()
    if not candidate:
        return candidate

    # Common case: normal sentence followed by broken JSON tail like `],"e":[]}`.
    last_sentence_end = max(candidate.rfind("."), candidate.rfind("!"), candidate.rfind("?"))
    if 0 <= last_sentence_end < len(candidate) - 1:
        tail = candidate[last_sentence_end + 1 :].strip()
        has_json_punct = any(ch in tail for ch in "{}[]") and ":" in tail
        long_alpha_tokens = re.findall(r"[A-Za-z]{2,}", tail)
        if tail and has_json_punct and not long_alpha_tokens:
            candidate = candidate[: last_sentence_end + 1].strip()

    return candidate


async def _ensure_topic_session_owner(
    session_id: str,
    current_user: AuthenticatedUser,
    db: AsyncIOMotorDatabase,
) -> dict:
    session = await db["chat_sessions"].find_one({"session_id": session_id})
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
    request_context: Request,
    session_id: str,
    request: TopicChatRequest,
    db: AsyncIOMotorDatabase = Depends(get_database),
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
        
        # Get session
        session = await _ensure_topic_session_owner(session_id, current_user, db)
        
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
            graph_result = await asyncio.wait_for(
                orchestrator.process(
                    user_input=request.message,
                    session_id=session_id,
                    user_id=request.user_id,
                    learner_profile={"level": session.get("difficulty_level", "B1")},
                    conversation_history=conversation_history[-6:],
                    retrieval_policy="rapid",
                    diagnosis_policy="rules",
                    generation_policy="auto",
                ),
                timeout=TOPIC_GRAPHCAG_TIMEOUT_SEC,
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
                retry_result = await asyncio.wait_for(
                    orchestrator.process(
                        user_input=request.message,
                        session_id=session_id,
                        user_id=request.user_id,
                        learner_profile={"level": session.get("difficulty_level", "B1")},
                        conversation_history=[],
                        cache_policy="off",
                        retrieval_policy="rapid",
                        diagnosis_policy="rules",
                        generation_policy="auto",
                    ),
                    timeout=TOPIC_GRAPHCAG_RETRY_TIMEOUT_SEC,
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
        
        # Parse educational hints and sanitize response before persisting/displaying
        clean_response, parsed_hints = EducationalHintsParser.parse(ai_response)
        display_response = _sanitize_topic_response(clean_response or ai_response)

        # Save AI message
        ai_message_id = str(uuid.uuid4())
        ai_message_doc = {
            "message_id": ai_message_id,
            "session_id": session_id,
            "content": display_response,
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
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Get details of a specific topic session."""
    session = await _ensure_topic_session_owner(session_id, current_user, db)
    
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
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Get all messages in a topic session."""
    # Verify session exists
    await _ensure_topic_session_owner(session_id, current_user, db)
    
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
    await _ensure_topic_session_owner(session_id, current_user, db)

    if limit < 1:
        raise HTTPException(status_code=400, detail="limit must be >= 1")

    safe_limit = min(limit, 200)
    base_query: dict = {"session_id": session_id}
    query: dict = dict(base_query)

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
    messages = [_serialize_topic_message(doc) for doc in docs]

    total_count = await db["chat_messages"].count_documents(base_query)
    next_cursor = _encode_cursor(docs[0]) if has_more and docs else None
    prev_cursor = _encode_cursor(docs[-1]) if docs else None
    window_start_ts = _to_iso_timestamp(docs[0].get("timestamp")) if docs else None
    window_end_ts = _to_iso_timestamp(docs[-1].get("timestamp")) if docs else None

    return {
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
    "/topic-sessions/{session_id}/messages/metadata",
    summary="Get topic message metadata",
)
async def get_topic_messages_metadata(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    await _ensure_topic_session_owner(session_id, current_user, db)

    base_query: dict = {"session_id": session_id}
    total_count = await db["chat_messages"].count_documents(base_query)

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
