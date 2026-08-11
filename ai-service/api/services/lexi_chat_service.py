"""
Lexi chat pipeline service — owns the actual conversation turn orchestration
(session bootstrapping, STT, TraceCAG, TTS, persistence) so the route module
only has to parse requests and shape responses.

Extracted from api/routes/lexi_chat.py so /chat and /stream share one
implementation without the orchestration living in a route handler.
"""

import asyncio
import json
import logging
import os
import time
import uuid
from contextlib import suppress
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, AsyncGenerator, Dict, List, Optional

from fastapi import HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
from pydantic import BaseModel, Field

from api.core.auth import AuthenticatedUser
from api.utils.cursor import to_iso_timestamp
from api.services.lexi_session_store import LexiSessionStore, get_lexi_store
from api.services.lexi_idempotency_store import LexiIdempotencyStore, get_lexi_idempotency_store
from api.services.lexi_pipeline_helpers import (
    sanitize_lexi_response as _sanitize_lexi_response,
    synthesize_tts as _synthesize_tts,
    transcribe_audio as _transcribe_audio,
)

logger = logging.getLogger(__name__)

lexi_store: LexiSessionStore = get_lexi_store()
lexi_idempotency_store: LexiIdempotencyStore = get_lexi_idempotency_store()

SAFE_FIXED_RESPONSE = (
    "Squawk! I'm temporarily unavailable right now. "
    "Please try again in a moment."
)

# SSE stream settings
HEARTBEAT_INTERVAL_S = 2.5  # how often to send a heartbeat to keep proxies alive


def env_float(name: str, default: float, minimum: float = 0.0) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return max(minimum, float(raw))
    except ValueError:
        return default


# ─── Request / Response Models ───────────────────────────────────────────────
class LexiChatRequest(BaseModel):
    """Request to chat with Lexi."""
    user_id: str = Field(default="demo_user", description="User identifier")
    session_id: Optional[str] = Field(default=None, description="Existing session ID")
    message: str = Field(..., min_length=1, description="User message text")
    input_type: str = Field(default="text", description="'text' or 'voice'")
    audio_base64: Optional[str] = Field(default=None, description="Base64 audio for STT")
    enable_tts: bool = Field(default=True, description="Generate TTS audio response")
    learner_level: str = Field(default="B1", description="CEFR level: A1-C2")
    native_language: str = Field(default="vi", description="ISO 639-1 code, e.g. vi/en/ja")
    story_context: Optional[str] = Field(default=None, description="Story/adventure context")


class LexiCorrection(BaseModel):
    """A grammar/vocabulary correction."""
    error_span: str = ""
    correction: str = ""
    error_type: str = ""
    explanation: str = ""


class LexiSuggestedPractice(BaseModel):
    """A one-tap follow-up practice prompt tied to the concept behind the
    mistake just made (not a generic weak-spot scan)."""
    concept_id: str
    concept_title: str
    prompt: str


class LexiChatResponse(BaseModel):
    """Structured response from Lexi."""
    success: bool = True
    session_id: str
    message_id: str
    lexi_response: str
    audio_base64: Optional[str] = None
    corrections: List[LexiCorrection] = []
    linked_concepts: List[str] = []
    suggested_practice: Optional[LexiSuggestedPractice] = None
    native_hint: Optional[str] = None
    scores: Optional[Dict[str, Any]] = None
    story_context: Optional[str] = None
    metadata: Dict[str, Any] = {}


class LexiSessionResponse(BaseModel):
    """Response for session creation."""
    success: bool = True
    session_id: str
    created_at: str
    persona: str = "lexi"


class LexiSessionRequest(BaseModel):
    """Request to create a Lexi session."""
    user_id: str = Field(default="demo_user", description="User identifier")


class LexiSessionRenameRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=120)


class LexiSessionSummary(BaseModel):
    session_id: str
    user_id: str
    title: str
    created_at: str
    updated_at: str
    message_count: int = 0


class LexiSessionListResponse(BaseModel):
    success: bool = True
    sessions: List[LexiSessionSummary] = []


async def _build_session_recap(
    db: AsyncIOMotorDatabase,
    user_id: str,
    current_session_id: str,
) -> Optional[str]:
    """A short reminder of what the learner was talking about last time,
    fed into the system prompt so Lexi can open a fresh session like it
    remembers them — mirrors what a human tutor would naturally do.

    Only meaningful on a genuinely fresh conversation (empty history), so
    callers should skip this for any session that already has turns.
    """
    try:
        last_session = await db["lexi_sessions"].find_one(
            {
                "user_id": user_id,
                "session_id": {"$ne": current_session_id},
                "message_count": {"$gt": 0},
            },
            sort=[("updated_at", -1)],
        )
        if not last_session:
            return None

        last_user_message = await db["lexi_messages"].find_one(
            {"session_id": last_session["session_id"], "role": "user"},
            sort=[("timestamp", -1)],
        )
        if not last_user_message:
            return None

        content = str(last_user_message.get("content") or "").strip()
        if not content:
            return None
        return content[:150]
    except Exception as exc:
        # warning, not debug: this is a purely optional enhancement, but a
        # silent debug-level swallow here would hide a real bug (wrong
        # field name, schema drift) with zero production visibility.
        logger.warning("[lexi_chat] session recap lookup failed: %s", exc)
        return None


def _build_suggested_practice(
    weak_concepts: List[str],
    has_correction: bool,
) -> Optional[LexiSuggestedPractice]:
    """One-tap practice follow-up tied to the concept behind *this turn's*
    mistake — not a generic "you're weak at X" scan (that's what
    KnowledgeGraphServiceV3.get_recommended_concepts() does, and it has no
    idea what the learner just got wrong). Only offered when there actually
    was a correction this turn, so a clean sentence doesn't get nagged.
    """
    if not has_correction or not weak_concepts:
        return None
    try:
        from api.services.kg_service_v3 import get_kg_service

        concept_id = str(weak_concepts[0])
        meta = get_kg_service().get_concepts().get(concept_id, {})
        title = str(meta.get("title") or concept_id)
        return LexiSuggestedPractice(
            concept_id=concept_id,
            concept_title=title,
            prompt=f"Cho tôi thêm 1 câu ví dụ để luyện tập '{title}'.",
        )
    except Exception as exc:
        # warning, not debug: same reasoning as _build_session_recap above —
        # this must stay visible in production logs, not silently vanish.
        logger.warning("[lexi_chat] suggested_practice lookup failed: %s", exc)
        return None


def idempotency_request_hash(request: "LexiChatRequest") -> str:
    import hashlib

    payload = {
        "user_id": request.user_id,
        "session_id": request.session_id,
        "message": request.message,
        "input_type": request.input_type,
        "audio_base64": request.audio_base64,
        "enable_tts": request.enable_tts,
        "learner_level": request.learner_level,
        "native_language": request.native_language,
        "story_context": request.story_context,
    }
    normalized = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


# ─── Session bootstrapping ───────────────────────────────────────────────────
async def ensure_session_owner(
    session_id: str,
    current_user: AuthenticatedUser,
    db: AsyncIOMotorDatabase,
) -> Dict[str, Any]:
    session_doc = await db["lexi_sessions"].find_one({"session_id": session_id})
    if not session_doc:
        raise HTTPException(status_code=404, detail="Session not found")

    owner_user_id = str(session_doc.get("user_id") or "")
    if owner_user_id and owner_user_id != current_user.user_id:
        raise HTTPException(status_code=403, detail="Forbidden: session ownership mismatch")
    return session_doc


def assert_cached_session_owner(
    cached_session: Dict[str, Any] | None,
    current_user: AuthenticatedUser,
) -> None:
    if not cached_session:
        return
    owner_user_id = str(cached_session.get("user_id") or "")
    if owner_user_id and owner_user_id != current_user.user_id:
        raise HTTPException(status_code=403, detail="Forbidden: session ownership mismatch")


async def get_cached_session_with_messages(
    session_id: str,
) -> tuple[Dict[str, Any] | None, List[Dict[str, Any]]]:
    if callable(getattr(type(lexi_store), "get_session_with_messages", None)):
        return await lexi_store.get_session_with_messages(session_id)

    cached_session, cached_messages = await asyncio.gather(
        lexi_store.get_session(session_id),
        lexi_store.get_messages(session_id),
    )
    return cached_session, cached_messages


async def prepare_existing_lexi_session(
    session_id: str,
    current_user: AuthenticatedUser,
    db: AsyncIOMotorDatabase,
) -> List[Dict[str, Any]]:
    cached_session, cached_messages = await get_cached_session_with_messages(session_id)
    cached_owner = str((cached_session or {}).get("user_id") or "")
    if cached_session and cached_owner:
        assert_cached_session_owner(cached_session, current_user)
        return cached_messages

    try:
        await ensure_session_owner(session_id, current_user, db)
    except HTTPException as exc:
        if exc.status_code != 404:
            raise
        assert_cached_session_owner(cached_session, current_user)
        if not cached_session:
            raise
        return cached_messages

    assert_cached_session_owner(cached_session, current_user)
    if cached_session:
        return cached_messages

    docs = await (
        db["lexi_messages"]
        .find({"session_id": session_id})
        .sort("timestamp", -1)
        .limit(10)
        .to_list(length=10)
    )
    docs.reverse()
    return [
        {
            "id": doc.get("id") or doc.get("message_id") or str(doc.get("_id", "")),
            "role": doc.get("role", "user"),
            "content": doc.get("content", ""),
            "timestamp": to_iso_timestamp(doc.get("timestamp")),
        }
        for doc in docs
    ]


async def persist_duplex_voice_turn(
    db: AsyncIOMotorDatabase,
    *,
    session_id: str,
    user_id: str,
    turn_id: str,
    user_text: str,
    assistant_text: str,
) -> None:
    """Idempotently persist one completed duplex turn."""
    timestamp = datetime.now(timezone.utc).isoformat()
    messages = [
        {"id": f"voice-user-{turn_id}", "role": "user", "content": user_text, "timestamp": timestamp},
        {"id": f"voice-assistant-{turn_id}", "role": "assistant", "content": assistant_text, "timestamp": timestamp},
    ]
    results = await asyncio.gather(
        *(
            db["lexi_messages"].update_one(
                {"id": message["id"], "session_id": session_id},
                {"$setOnInsert": {**message, "session_id": session_id, "user_id": user_id}},
                upsert=True,
            )
            for message in messages
        )
    )
    inserted = [
        message for message, result in zip(messages, results) if result.upserted_id
    ]
    if not inserted:
        return
    await asyncio.gather(
        append_lexi_messages(session_id, inserted),
        db["lexi_sessions"].update_one(
            {"session_id": session_id, "user_id": user_id},
            {
                "$set": {"updated_at": timestamp},
                "$inc": {"message_count": len(inserted)},
            },
        ),
    )


async def create_lexi_session_for_user(
    session_id: str,
    user_id: str,
    story_context: Optional[str],
    db: AsyncIOMotorDatabase,
) -> None:
    now_iso = datetime.now(timezone.utc).isoformat()
    await asyncio.gather(
        lexi_store.set_session(session_id, {
            "session_id": session_id,
            "user_id": user_id,
            "created_at": now_iso,
            "updated_at": now_iso,
            "title": "Lexi Chat",
            "message_count": 0,
            "persona": "lexi",
            "story_context": story_context,
        }),
        lexi_store.init_messages(session_id),
        db["lexi_sessions"].update_one(
            {"session_id": session_id},
            {
                "$set": {
                    "session_id": session_id,
                    "user_id": user_id,
                    "title": "Lexi Chat",
                    "created_at": now_iso,
                    "updated_at": now_iso,
                    "message_count": 0,
                    "persona": "lexi",
                }
            },
            upsert=True,
        ),
    )


async def append_lexi_messages(
    session_id: str,
    messages: List[Dict[str, Any]],
) -> None:
    if callable(getattr(type(lexi_store), "append_messages", None)):
        await lexi_store.append_messages(session_id, messages)
        return

    await asyncio.gather(
        *(lexi_store.append_message(session_id, message) for message in messages)
    )


# ─── Pipeline result ─────────────────────────────────────────────────────────
@dataclass
class PipelineResult:
    lexi_response: str
    user_text: str
    message_id: str
    session_id: str
    corrections: List["LexiCorrection"] = field(default_factory=list)
    linked_concepts: List[str] = field(default_factory=list)
    suggested_practice: Optional["LexiSuggestedPractice"] = None
    native_hint: Optional[str] = None
    scores: Optional[Dict[str, Any]] = None
    model_used: str = "trace-cag"
    story_ctx: Optional[str] = None
    audio_b64: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


async def run_lexi_pipeline(
    request: "LexiChatRequest",
    session_id: str,
    history: List[Dict[str, Any]],
    db: AsyncIOMotorDatabase,
    quota: Any,
    start_time: float,
    skip_tts: bool = False,
) -> PipelineResult:
    """Execute the full Lexi pipeline (STT → TraceCAG → TTS → persist) and return results.

    Shared by both the regular /chat and the streaming /stream endpoints so
    they don't duplicate this logic.
    """
    metadata: Dict[str, Any] = {"pipeline_steps": ["session_ready"]}

    # ── STT ──
    user_text = request.message
    if request.input_type == "voice" and request.audio_base64:
        transcript = await _transcribe_audio(request.audio_base64)
        if transcript:
            user_text = transcript
            metadata["pipeline_steps"].append("stt_complete")
            metadata["stt_transcript"] = transcript
        else:
            metadata["pipeline_steps"].append("stt_failed")

    # ── TraceCAG pipeline ──
    lexi_response = ""
    corrections: List[LexiCorrection] = []
    linked_concepts: List[str] = []
    suggested_practice: Optional[LexiSuggestedPractice] = None
    native_hint: Optional[str] = None
    scores: Optional[Dict[str, Any]] = None
    model_used = "trace-cag"
    observation_trace_result: Dict[str, Any] = {}

    try:
        from api.services.orchestrator import get_orchestrator
        from api.utils.languages import iso_to_language_name

        # Run concurrently with orchestrator warmup — this Mongo lookup must
        # never add its own latency to the hot path the rest of this diff is
        # busy keeping non-blocking.
        recap_task = (
            asyncio.ensure_future(_build_session_recap(db, request.user_id, session_id))
            if not history
            else None
        )
        orchestrator = await get_orchestrator()
        session_recap = await recap_task if recap_task else None
        graph_result = await orchestrator.process(
            user_input=user_text,
            session_id=session_id,
            user_id=request.user_id,
            learner_profile={
                "level": request.learner_level,
                "native_language": iso_to_language_name(request.native_language),
                **({"session_recap": session_recap} if session_recap else {}),
            },
            conversation_history=history,
        )
        lexi_response = graph_result.get("tutor_response", "")
        for c in graph_result.get("corrections", []):
            corrections.append(LexiCorrection(
                error_span=c.get("error", ""),
                correction=c.get("correction", ""),
                error_type=c.get("type", ""),
                explanation=c.get("explanation", ""),
            ))
        linked_concepts = graph_result.get("linked_concepts", [])
        suggested_practice = _build_suggested_practice(
            graph_result.get("weak_concepts", []), bool(corrections)
        )
        native_hint = graph_result.get("native_hint")
        scores = graph_result.get("scores")
        metadata["pipeline_steps"].append("trace-cag_complete")
        metadata["trace-cag_metadata"] = graph_result.get("metadata", {})
        model_used = ", ".join(graph_result.get("metadata", {}).get("models_used", ["trace-cag"]))
        observation_trace_result = graph_result

    except Exception as e:
        logger.error("TraceCAG hard failure in Lexi pipeline (primary): %s", e)
        metadata["pipeline_steps"].append("trace-cag_failed_primary")
        try:
            from api.services.orchestrator import get_orchestrator
            from api.utils.languages import iso_to_language_name

            orchestrator = await get_orchestrator()
            retry_result = await orchestrator.process(
                user_input=user_text,
                session_id=session_id,
                user_id=request.user_id,
                learner_profile={
                    "level": request.learner_level,
                    "native_language": iso_to_language_name(request.native_language),
                },
                conversation_history=[],
                cache_policy="off",
                retrieval_policy="rapid",
                diagnosis_policy="rules",
                generation_policy="auto",
            )
            lexi_response = str(retry_result.get("tutor_response") or "").strip()
            if not lexi_response:
                raise RuntimeError("TraceCAG degraded retry returned empty tutor_response")
            retry_meta = retry_result.get("metadata", {}) or {}
            metadata["pipeline_steps"].append("trace-cag_retry_complete")
            metadata["trace-cag_metadata"] = {
                **retry_meta,
                "fallback_used": True,
                "retry_mode": "trace-cag_degraded",
                "primary_error": str(e),
            }
            model_used = ", ".join(retry_meta.get("models_used", ["trace-cag_retry"]))
            observation_trace_result = retry_result
        except Exception as retry_err:
            logger.error("TraceCAG hard failure in Lexi pipeline (degraded retry): %s", retry_err)
            metadata["pipeline_steps"].append("trace-cag_failed_hard")
            metadata["trace-cag_metadata"] = {
                "fallback_used": True,
                "primary_error": str(e),
                "retry_error": str(retry_err),
            }
            lexi_response = SAFE_FIXED_RESPONSE
            model_used = "trace-cag_safe_response"

    # ── Guards ──
    story_ctx = request.story_context
    if not story_ctx:
        _pre_sess = await lexi_store.get_session(session_id)
        if _pre_sess:
            story_ctx = _pre_sess.get("story_context")

    if not lexi_response:
        lexi_response = SAFE_FIXED_RESPONSE
        model_used = "trace-cag_safe_response"
        metadata["pipeline_steps"].append("trace-cag_empty_response_guard")

    lexi_response = _sanitize_lexi_response(lexi_response)
    metadata["model_used"] = model_used

    # ── TTS ──
    audio_b64: Optional[str] = None
    if request.enable_tts and not skip_tts:
        tts_timeout_s = env_float("LEXI_TTS_TIMEOUT_SECONDS", 8.0, minimum=0.5)
        try:
            audio_b64 = await asyncio.wait_for(
                _synthesize_tts(lexi_response),
                timeout=tts_timeout_s,
            )
            metadata["pipeline_steps"].append("tts_complete" if audio_b64 else "tts_skipped")
        except asyncio.TimeoutError:
            logger.warning("Lexi TTS timed out after %.1fs", tts_timeout_s)
            metadata["pipeline_steps"].append("tts_timeout")

    # ── Persist messages ──
    message_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()
    user_message = {
        "id": str(uuid.uuid4()),
        "role": "user",
        "content": user_text,
        "timestamp": timestamp,
    }
    assistant_message = {
        "id": message_id,
        "role": "assistant",
        "content": lexi_response,
        "timestamp": timestamp,
    }

    # Fire all independent writes concurrently: cache append + MongoDB writes.
    await asyncio.gather(
        append_lexi_messages(session_id, [user_message, assistant_message]),
        db["lexi_messages"].insert_many([
            {
                **user_message,
                "session_id": session_id,
                "user_id": request.user_id,
            },
            {
                **assistant_message,
                "session_id": session_id,
                "user_id": request.user_id,
            },
        ]),
        db["lexi_sessions"].update_one(
            {"session_id": session_id},
            {
                "$set": {
                    "updated_at": timestamp,
                    "user_id": request.user_id,
                },
                "$inc": {"message_count": 2},
                "$setOnInsert": {
                    "created_at": timestamp,
                    "title": "Lexi Chat",
                    "persona": "lexi",
                },
            },
            upsert=True,
        ),
    )

    # Read session (needed for message_count), then fire session update + conv cache concurrently
    cached_session = await lexi_store.get_session(session_id) or {}
    if not story_ctx:
        story_ctx = cached_session.get("story_context")
    cached_count = int(cached_session.get("message_count") or 0)

    async def _write_conv_cache():
        try:
            from api.core.redis_client import ConversationCache, RedisClient
            _redis_inst = await RedisClient.get_instance()
            _conv_cache = ConversationCache(_redis_inst)
            await _conv_cache.add_turn(
                session_id=session_id,
                user_message=user_text,
                ai_response=lexi_response,
                metadata={
                    "model": model_used,
                    "scores": scores,
                    "latency_ms": int((time.time() - start_time) * 1000),
                },
            )
        except Exception as _cc_err:
            logger.debug(f"ConversationCache write skipped: {_cc_err}")

    await asyncio.gather(
        lexi_store.set_session(session_id, {
            "session_id": session_id,
            "user_id": request.user_id,
            "created_at": cached_session.get("created_at", timestamp),
            "updated_at": timestamp,
            "title": cached_session.get("title", "Lexi Chat"),
            "message_count": cached_count + 2,
            "persona": cached_session.get("persona", "lexi"),
            "story_context": story_ctx,
        }),
        _write_conv_cache(),
    )

    try:
        from api.services.learner_observation_spool import persist_trace_observations

        metadata.update(
            await persist_trace_observations(
                user_id=request.user_id,
                session_id=session_id,
                turn_id=user_message["id"],
                trace_result=observation_trace_result,
            )
        )
    except Exception as observation_err:
        logger.error(
            "Lexi learner observation durability degraded: %s",
            type(observation_err).__name__,
        )
        metadata["observation_durability_degraded"] = True

    total_ms = int((time.time() - start_time) * 1000)
    metadata["latency_ms"] = total_ms
    metadata["quota"] = {
        "rpm_used": quota.rpm_used,
        "rpm_limit": quota.rpm_limit,
        "rpd_used": quota.rpd_used,
        "rpd_limit": quota.rpd_limit,
        "tpm_used": quota.tpm_used,
        "tpm_limit": quota.tpm_limit,
        "tpd_used": quota.tpd_used,
        "tpd_limit": quota.tpd_limit,
    }
    logger.info(
        f"Lexi pipeline complete — {total_ms}ms, model: {model_used}, "
        f"steps: {metadata['pipeline_steps']}"
    )

    return PipelineResult(
        lexi_response=lexi_response,
        user_text=user_text,
        message_id=message_id,
        session_id=session_id,
        corrections=corrections,
        linked_concepts=linked_concepts,
        suggested_practice=suggested_practice,
        native_hint=native_hint,
        scores=scores,
        model_used=model_used,
        story_ctx=story_ctx,
        audio_b64=audio_b64,
        metadata=metadata,
    )


async def stream_lexi_chat(
    request: "LexiChatRequest",
    session_id: str,
    prechecked_history: Optional[List[Dict[str, Any]]],
    quota: Any,
    start_time: float,
    request_id: str,
    current_user: AuthenticatedUser,
    db: AsyncIOMotorDatabase,
) -> AsyncGenerator[str, None]:
    """SSE generator for the streaming Lexi chat pipeline. See lexi_stream_chat
    route docstring for the event sequence (thinking/heartbeat/chunk/done/error).
    """
    from api.core.audit_emitter import emit_ai_audit_event
    from api.services.orchestrator import get_orchestrator
    from api.services.trace_cag.nodes_v2 import build_generation_prompt, stream_llm_tokens
    from api.services.trace_cag.evaluation_agent import EvaluationAgent
    from api.utils.languages import iso_to_language_name

    user_text = request.message

    # 1. Open the SSE response before touching Redis/Mongo. This prevents a
    # degraded session store from holding the HTTP response until the edge
    # proxy returns a 504.
    yield "event: thinking\ndata: {}\n\n"

    # 2. Session management. Keep sending data events while Redis/Mongo is
    # slow so Cloudflare and nginx do not treat the stream as idle.
    if prechecked_history is not None:
        history = prechecked_history
    else:
        async def _prepare_session() -> List[Dict[str, Any]]:
            await create_lexi_session_for_user(
                session_id=session_id,
                user_id=request.user_id,
                story_context=request.story_context,
                db=db,
            )
            return []

        session_task = asyncio.create_task(_prepare_session())
        loop = asyncio.get_running_loop()
        session_timeout_s = env_float(
            "LEXI_STREAM_SESSION_TIMEOUT_SECONDS",
            15.0,
            minimum=HEARTBEAT_INTERVAL_S,
        )
        session_deadline = loop.time() + session_timeout_s
        while not session_task.done():
            if loop.time() >= session_deadline:
                session_task.cancel()
                with suppress(asyncio.CancelledError):
                    await session_task
                logger.error(
                    "Lexi /stream session preparation timed out after %.1fs",
                    session_timeout_s,
                )
                yield (
                    f"event: error\ndata: "
                    f"{json.dumps({'error': 'Chat session service is temporarily unavailable.'})}\n\n"
                )
                return
            try:
                await asyncio.wait_for(
                    asyncio.shield(session_task),
                    timeout=HEARTBEAT_INTERVAL_S,
                )
            except asyncio.TimeoutError:
                yield "event: heartbeat\ndata: {}\n\n"
            except Exception:
                break

        try:
            history = await session_task
        except Exception as exc:
            logger.error("Lexi /stream session preparation error: %s", exc)
            yield (
                f"event: error\ndata: "
                f"{json.dumps({'error': 'Chat session service is temporarily unavailable.'})}\n\n"
            )
            return

    # 3. Context preparation — KG + diagnose + retrieve, NO LLM generation.
    #    Heartbeat pings keep the SSE connection alive while this runs.
    #    get_orchestrator() may block on cold start (model loading); run it as
    #    a task so we can keep pinging while it initialises.
    try:
        orch_task = asyncio.create_task(get_orchestrator())
        # Started alongside orchestrator warmup (not after) — this Mongo
        # lookup must never add its own latency to the streaming hot path.
        recap_task = (
            asyncio.create_task(_build_session_recap(db, request.user_id, session_id))
            if not history
            else None
        )
        loop = asyncio.get_running_loop()
        orch_deadline = loop.time() + 45.0  # Reduced from 60s: total must fit within Cloudflare's 100s proxy timeout
        while not orch_task.done():
            if loop.time() >= orch_deadline:
                orch_task.cancel()
                yield (
                    f"event: error\ndata: "
                    f"{json.dumps({'error': 'Service is starting up. Please try again.'})}\n\n"
                )
                return
            try:
                await asyncio.wait_for(asyncio.shield(orch_task), timeout=HEARTBEAT_INTERVAL_S)
            except asyncio.TimeoutError:
                # Use proper SSE data event (not comment) — Cloudflare flushes data events
                # immediately but may buffer SSE comment lines (`: ping`).
                yield "event: heartbeat\ndata: {}\n\n"
            except Exception:
                break
        orchestrator = await orch_task
        session_recap = await recap_task if recap_task else None
        ctx_task = asyncio.create_task(
            orchestrator.pipeline.analyze_for_streaming(
                user_input=user_text,
                session_id=session_id,
                user_id=request.user_id,
                learner_profile={
                    "level": request.learner_level,
                    "native_language": iso_to_language_name(request.native_language),
                    **({"session_recap": session_recap} if session_recap else {}),
                },
                conversation_history=history,
            )
        )

        loop = asyncio.get_running_loop()
        ctx_deadline = loop.time() + 15.0  # Reduced from 25s: orch(45) + ctx(15) + LLM < 90s
        while not ctx_task.done():
            if loop.time() >= ctx_deadline:
                ctx_task.cancel()
                logger.error("Lexi /stream context prep timed out")
                yield (
                    f"event: error\ndata: "
                    f"{json.dumps({'error': 'Response timed out. Please try again.'})}\n\n"
                )
                return
            try:
                await asyncio.wait_for(
                    asyncio.shield(ctx_task), timeout=HEARTBEAT_INTERVAL_S
                )
            except asyncio.TimeoutError:
                # Use proper SSE data event — Cloudflare flushes data events immediately
                yield "event: heartbeat\ndata: {}\n\n"
            except Exception:
                break

        raw_state = await ctx_task

    except Exception as exc:
        logger.error("Lexi /stream context prep error: %s", exc)
        yield (
            f"event: error\ndata: "
            f"{json.dumps({'error': 'Pipeline failed. Please try again.'})}\n\n"
        )
        return

    # Extract corrections / concepts / scores from pipeline state
    diag_errors = list(raw_state.get("diagnosis_errors") or [])
    corrections = [
        LexiCorrection(
            error_span=str(e.get("span") or ""),
            correction=str(e.get("correction") or ""),
            error_type=str(e.get("type") or ""),
            explanation=str(e.get("explanation") or ""),
        )
        for e in diag_errors
    ]
    linked_concepts = list(raw_state.get("kg_seed_concepts") or [])
    suggested_practice = _build_suggested_practice(
        list(raw_state.get("diagnosis_root_causes") or []), bool(corrections)
    )
    native_hint = raw_state.get("native_hint")
    grammar_score = float(raw_state.get("grammar_score") or 0.8)
    fluency_score = float(raw_state.get("fluency_score") or 0.8)
    vocab_level = str(raw_state.get("vocabulary_level") or "B1")

    lexi_response = ""
    model_used = "stream_llm"
    cache_hit = bool(raw_state.get("cache_hit")) and bool(raw_state.get("tutor_response"))

    # 3. Token streaming
    if cache_hit:
        # Cache hit: deliver words quickly — no LLM round-trip needed.
        lexi_response = _sanitize_lexi_response(str(raw_state["tutor_response"]))
        model_used = f"cached_{raw_state.get('cache_layer', 'L0')}"
        for word in lexi_response.split(" "):
            yield f"event: chunk\ndata: {json.dumps({'text': word + ' '})}\n\n"
            await asyncio.sleep(0.012)
    else:
        # Cache miss: buffer provider tokens, sanitize the complete response,
        # then deliver it as SSE chunks so token-spanning internal markers
        # can never reach the client.
        provider_info: dict = {}
        try:
            system_prompt, llm_messages = build_generation_prompt(raw_state)
            tokens: list[str] = []
            async for token in stream_llm_tokens(
                system_prompt=system_prompt,
                messages=llm_messages,
                user_input=user_text,
                provider_info=provider_info,
            ):
                tokens.append(token)
            raw_response = "".join(tokens).strip()
            lexi_response = _sanitize_lexi_response(raw_response) if raw_response else ""
            for word in lexi_response.split(" ") if lexi_response else []:
                yield f"event: chunk\ndata: {json.dumps({'text': word + ' '})}\n\n"
        except Exception as gen_err:
            logger.error("Lexi /stream LLM generation error: %s", gen_err)

        if not lexi_response:
            lexi_response = SAFE_FIXED_RESPONSE
            model_used = "trace-cag_safe_response"
        else:
            # Reflects whichever provider actually served the tokens (Groq can
            # fail mid-stream and fall back to Gemini) instead of guessing from
            # GROQ_API_KEY's presence, which stays true even when Groq is down.
            model_used = f"{provider_info.get('provider', 'unknown')}/{provider_info.get('model', 'unknown')}"

    if not cache_hit and lexi_response and model_used != "trace-cag_safe_response":
        try:
            from api.services.trace_cag.benchmark.ranking import _update_ranker_from_generation
            from api.services.trace_cag.cache_utils import _write_cache_entry

            overall_for_cache = EvaluationAgent.compute_overall_score(
                grammar_score, fluency_score, vocab_level
            )
            _update_ranker_from_generation(
                question=user_text,
                response=lexi_response,
                retrieval_trace=list(raw_state.get("retrieval_trace") or []),
            )
            if raw_state.get("cache_policy", "on") == "on":
                await _write_cache_entry(
                    raw_state,
                    lexi_response,
                    str(raw_state.get("strategy") or "feedback"),
                    diag_errors,
                    overall_for_cache,
                    str(raw_state.get("retrieved_context") or ""),
                    model_used=model_used,
                )
        except Exception as side_effect_err:
            logger.debug("Lexi stream cache/ranker side effect skipped: %s", side_effect_err)

    # 4. TTS synthesis — after all chunks so TTFB is unaffected
    audio_b64: Optional[str] = None
    if request.enable_tts:
        try:
            audio_b64 = await asyncio.wait_for(
                _synthesize_tts(lexi_response), timeout=8.0
            )
        except Exception as tts_err:
            logger.warning("Lexi stream TTS failed: %s", tts_err)

    # 5. Persist messages (parallelised)
    message_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()
    user_message = {
        "id": str(uuid.uuid4()),
        "role": "user",
        "content": user_text,
        "timestamp": timestamp,
    }
    assistant_message = {
        "id": message_id,
        "role": "assistant",
        "content": lexi_response,
        "timestamp": timestamp,
    }

    async def _stream_persist():
        await asyncio.gather(
            append_lexi_messages(session_id, [user_message, assistant_message]),
            db["lexi_messages"].insert_many([
                {**user_message, "session_id": session_id, "user_id": request.user_id},
                {**assistant_message, "session_id": session_id, "user_id": request.user_id},
            ]),
            db["lexi_sessions"].update_one(
                {"session_id": session_id},
                {
                    "$set": {"updated_at": timestamp, "user_id": request.user_id},
                    "$inc": {"message_count": 2},
                    "$setOnInsert": {
                        "created_at": timestamp,
                        "title": "Lexi Chat",
                        "persona": "lexi",
                    },
                },
                upsert=True,
            ),
        )
        cached_sess = await lexi_store.get_session(session_id) or {}
        cached_count = int(cached_sess.get("message_count") or 0)
        await lexi_store.set_session(session_id, {
            "session_id": session_id,
            "user_id": request.user_id,
            "created_at": cached_sess.get("created_at", timestamp),
            "updated_at": timestamp,
            "title": cached_sess.get("title", "Lexi Chat"),
            "message_count": cached_count + 2,
            "persona": cached_sess.get("persona", "lexi"),
            "story_context": request.story_context,
        })

    try:
        await asyncio.wait_for(_stream_persist(), timeout=5.0)
    except Exception as persist_err:
        logger.warning("Lexi stream persist error: %s", persist_err)

    observation_meta: Dict[str, Any] = {}
    try:
        from api.services.learner_observation_spool import persist_trace_observations

        observation_meta = await persist_trace_observations(
            user_id=request.user_id,
            session_id=session_id,
            turn_id=user_message["id"],
            trace_result=raw_state,
        )
    except Exception as observation_err:
        logger.error(
            "Lexi stream learner observation durability degraded: %s",
            type(observation_err).__name__,
        )
        observation_meta = {"observation_durability_degraded": True}

    # 6. Done event
    overall_score = EvaluationAgent.compute_overall_score(
        grammar_score, fluency_score, vocab_level
    )
    scores = {
        "fluency": fluency_score,
        "grammar": grammar_score,
        "overall": overall_score,
        "vocabulary_level": vocab_level,
    }
    total_ms = int((time.time() - start_time) * 1000)
    done_payload = json.dumps({
        "message_id": message_id,
        "session_id": session_id,
        "lexi_response": lexi_response,
        "corrections": [
            {
                "error_span": c.error_span,
                "correction": c.correction,
                "error_type": c.error_type,
                "explanation": c.explanation,
            }
            for c in corrections
        ],
        "linked_concepts": linked_concepts,
        "suggested_practice": (
            suggested_practice.model_dump() if suggested_practice else None
        ),
        "native_hint": native_hint,
        "scores": scores,
        "story_context": request.story_context,
        "audio_base64": audio_b64,
        "metadata": {
            "latency_ms": total_ms,
            "model_used": model_used,
            "cache_hit": cache_hit,
            **observation_meta,
            "quota": {
                "rpm_used": quota.rpm_used,
                "rpm_limit": quota.rpm_limit,
                "rpd_used": quota.rpd_used,
                "rpd_limit": quota.rpd_limit,
            },
        },
    })
    yield f"event: done\ndata: {done_payload}\n\n"

    logger.info(
        "Lexi /stream complete — %dms, model: %s, cache_hit: %s",
        total_ms, model_used, cache_hit,
    )
    await emit_ai_audit_event({
        "request_id": request_id,
        "user_id": current_user.user_id,
        "endpoint": "lexi.stream",
        "status": "success",
        "session_id": session_id,
        "model_used": model_used,
        "latency_ms": total_ms,
        "quota": {"rpm_used": quota.rpm_used, "rpm_limit": quota.rpm_limit},
    })
