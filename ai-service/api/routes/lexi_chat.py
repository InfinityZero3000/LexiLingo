"""
Lexi Chat Route — Story-driven conversational AI with the parrot mascot.

Pipeline:
  1. STT (if voice input) → Whisper transcription
  2. TraceCAG pipeline → KG expansion + diagnosis + retrieval
    3. TraceCAG generation (internal model fallback handled by TraceCAG)
  4. TTS synthesis → gTTS / Piper for Lexi's voice
  5. Return structured response with audio, story context, corrections

Integrates with the existing TraceCAG system for document retrieval
and knowledge graph expansion to make conversations contextually rich.
"""

import asyncio
import logging
import re
import io
import json
import uuid
import time
import base64
import hashlib
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import AsyncGenerator, Optional, List, Dict, Any

from fastapi import APIRouter, HTTPException, Depends, Query, Header, Request
from fastapi.responses import StreamingResponse
from motor.motor_asyncio import AsyncIOMotorDatabase
from bson import ObjectId
from pymongo.errors import OperationFailure
from pydantic import BaseModel, Field
from api.core.auth import AuthenticatedUser, enforce_user_scope, get_current_user
from api.core.audit_emitter import emit_ai_audit_event
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
from api.core.database import get_database

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/lexi", tags=["lexi-chat"])


# ─── Redis-backed session store with in-memory fallback ──────────────────────
class _LexiStore:
    """
    Persists Lexi sessions & messages in Redis.
    Falls back to in-memory dicts when Redis is unavailable so the
    chat endpoint still works during local dev without Redis.
    """

    _SESSION_PREFIX = "lexi:session:"
    _MSG_PREFIX = "lexi:msgs:"
    _TTL = timedelta(hours=24)

    def __init__(self):
        self._mem_sessions: Dict[str, Dict[str, Any]] = {}
        self._mem_messages: Dict[str, List[Dict[str, Any]]] = {}

    # ── helpers ──────────────────────────────────────────────────────────
    async def _redis(self):
        """Get Redis client, return None on failure."""
        try:
            from api.core.redis_client import get_redis
            r = await get_redis()
            await r.ping()
            return r
        except Exception:
            return None

    # ── sessions ─────────────────────────────────────────────────────────
    async def get_session(self, sid: str) -> Optional[Dict[str, Any]]:
        r = await self._redis()
        if r:
            raw = await r.get(f"{self._SESSION_PREFIX}{sid}")
            if raw:
                return json.loads(raw)
            return None
        return self._mem_sessions.get(sid)

    async def set_session(self, sid: str, data: Dict[str, Any]):
        r = await self._redis()
        if r:
            await r.set(
                f"{self._SESSION_PREFIX}{sid}",
                json.dumps(data),
                ex=self._TTL,
            )
        else:
            self._mem_sessions[sid] = data

    async def has_session(self, sid: str) -> bool:
        return (await self.get_session(sid)) is not None

    # ── messages ─────────────────────────────────────────────────────────
    async def get_messages(self, sid: str) -> List[Dict[str, Any]]:
        r = await self._redis()
        if r:
            raw_list = await r.lrange(f"{self._MSG_PREFIX}{sid}", 0, -1)
            return [json.loads(m) for m in raw_list] if raw_list else []
        return self._mem_messages.get(sid, [])

    async def append_message(self, sid: str, msg: Dict[str, Any]):
        r = await self._redis()
        if r:
            key = f"{self._MSG_PREFIX}{sid}"
            await r.rpush(key, json.dumps(msg))
            await r.expire(key, self._TTL)
        else:
            self._mem_messages.setdefault(sid, []).append(msg)

    async def init_messages(self, sid: str):
        """Ensure the message list exists (no-op for Redis, inits list for mem)."""
        r = await self._redis()
        if not r:
            if sid not in self._mem_messages:
                self._mem_messages[sid] = []

    async def delete_session(self, sid: str):
        r = await self._redis()
        if r:
            await r.delete(f"{self._SESSION_PREFIX}{sid}")
        self._mem_sessions.pop(sid, None)

    async def delete_messages(self, sid: str):
        r = await self._redis()
        if r:
            await r.delete(f"{self._MSG_PREFIX}{sid}")
        self._mem_messages.pop(sid, None)


_store = _LexiStore()


class _LexiIdempotencyStore:
    _PREFIX = "lexi:idempotency:"
    _TTL = timedelta(hours=24)

    def __init__(self):
        self._mem: Dict[str, Dict[str, Any]] = {}

    async def _redis(self):
        try:
            from api.core.redis_client import get_redis

            return await get_redis()
        except Exception:
            return None

    def _key(self, user_id: str, session_id: str, idempotency_key: str) -> str:
        return f"{self._PREFIX}{user_id}:{session_id}:{idempotency_key}"

    def _cleanup_mem(self):
        now = datetime.utcnow()
        stale = [
            k
            for k, v in self._mem.items()
            if isinstance(v.get("expires_at"), datetime)
            and v.get("expires_at") <= now
        ]
        for k in stale:
            self._mem.pop(k, None)

    async def get(
        self,
        *,
        user_id: str,
        session_id: str,
        idempotency_key: str,
        request_hash: str,
    ) -> Optional[Dict[str, Any]]:
        key = self._key(user_id, session_id, idempotency_key)
        r = await self._redis()
        if r:
            raw = await r.get(key)
            if not raw:
                return None
            data = json.loads(raw)
            if data.get("request_hash") != request_hash:
                raise HTTPException(
                    status_code=409,
                    detail="Idempotency key reused with different payload",
                )
            return data.get("response")

        self._cleanup_mem()
        data = self._mem.get(key)
        if not data:
            return None
        if data.get("request_hash") != request_hash:
            raise HTTPException(
                status_code=409,
                detail="Idempotency key reused with different payload",
            )
        return data.get("response")

    async def set(
        self,
        *,
        user_id: str,
        session_id: str,
        idempotency_key: str,
        request_hash: str,
        response: Dict[str, Any],
    ) -> None:
        key = self._key(user_id, session_id, idempotency_key)
        payload = {"request_hash": request_hash, "response": response}
        r = await self._redis()
        if r:
            await r.set(key, json.dumps(payload), ex=self._TTL)
            return

        self._cleanup_mem()
        self._mem[key] = {
            **payload,
            "expires_at": datetime.utcnow() + self._TTL,
        }


_idempotency_store = _LexiIdempotencyStore()

SAFE_FIXED_RESPONSE = (
    "Squawk! I'm temporarily unavailable right now. "
    "Please try again in a moment."
)


def _idempotency_request_hash(request: "LexiChatRequest") -> str:
    payload = {
        "user_id": request.user_id,
        "session_id": request.session_id,
        "message": request.message,
        "input_type": request.input_type,
        "audio_base64": request.audio_base64,
        "enable_tts": request.enable_tts,
        "learner_level": request.learner_level,
        "story_context": request.story_context,
    }
    normalized = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


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


def _to_iso_timestamp(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _serialize_lexi_message(doc: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": doc.get("id") or doc.get("message_id") or str(doc.get("_id", "")),
        "session_id": doc.get("session_id", ""),
        "role": doc.get("role", "user"),
        "content": doc.get("content", ""),
        "timestamp": _to_iso_timestamp(doc.get("timestamp")),
    }


def _encode_cursor(doc: Dict[str, Any]) -> str:
    ts = _to_iso_timestamp(doc.get("timestamp"))
    oid = str(doc.get("_id", ""))
    payload = json.dumps({"ts": ts, "oid": oid}, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(payload).decode("utf-8")


def _decode_cursor(cursor: str) -> tuple[str, ObjectId]:
    try:
        padding = "=" * (-len(cursor) % 4)
        raw = base64.urlsafe_b64decode(f"{cursor}{padding}".encode("utf-8"))
        data = json.loads(raw.decode("utf-8"))
        ts = str(data["ts"])
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
) -> Dict[str, Any]:
    return {
        "total_count": total_count,
        "returned": returned,
        "has_more": has_more,
        "next_cursor": next_cursor,
        "prev_cursor": prev_cursor,
        "window_start_ts": window_start_ts,
        "window_end_ts": window_end_ts,
    }


async def _ensure_session_owner(
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


def _normalize_markdown_for_lexi(text: str) -> str:
    """Normalize malformed markdown emphasis markers produced by model output."""
    if "**" not in text:
        return text

    out: List[str] = []
    in_bold = False
    open_idx: Optional[int] = None
    i = 0
    n = len(text)

    while i < n:
        is_double_star = text[i:i + 2] == "**"
        is_exact_pair = (
            is_double_star
            and (i == 0 or text[i - 1] != "*")
            and (i + 2 >= n or text[i + 2] != "*")
        )

        if not is_exact_pair:
            out.append(text[i])
            i += 1
            continue

        prev_ch = text[i - 1] if i > 0 else ""
        next_ch = text[i + 2] if i + 2 < n else ""
        can_open = bool(next_ch) and not next_ch.isspace()
        can_close = bool(prev_ch) and not prev_ch.isspace()

        if not in_bold:
            if can_open:
                open_idx = len(out)
                out.append("**")
                in_bold = True
        else:
            if can_close:
                out.append("**")
                in_bold = False
                open_idx = None

        i += 2

    if in_bold and open_idx is not None:
        out.pop(open_idx)

    return "".join(out)


def _sanitize_lexi_response(text: str) -> str:
    """Remove internal TraceCAG debug payloads from user-facing Lexi output."""
    cleaned = str(text or "")
    if not cleaned:
        return ""

    # Strip accidental reasoning/debug sections.
    cleaned = re.sub(r"<think\b[^>]*>[\s\S]*?</think>", "", cleaned, flags=re.IGNORECASE)

    # Remove JIT graph marker and trailing JSON payload if leaked.
    cleaned = re.sub(
        r"\[JIT_SOFT_GRAPH\]\s*(?:\n|\r\n?)?\s*\{[\s\S]*?\}\s*",
        "",
        cleaned,
        flags=re.IGNORECASE,
    )

    # Remove standalone graph-json lines (with optional escaped quotes).
    cleaned = re.sub(
        r"^\s*\{(?:\\?\"v\\?\"|\"v\")[\s\S]*?(?:\\?\"e\\?\"|\"e\")[\s\S]*?\}\s*$",
        "",
        cleaned,
        flags=re.IGNORECASE | re.MULTILINE,
    )

    # Normalize escaped markdown punctuation before balancing emphasis markers.
    cleaned = cleaned.replace("\\*", "*")
    cleaned = cleaned.replace("\\_", "_")

    cleaned = _normalize_markdown_for_lexi(cleaned)

    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()

    if not cleaned:
        return "Squawk! I lost my words for a second. Could you ask that again?"

    return cleaned


# ─── Lexi Persona System Prompt ─────────────────────────────────────────────
LEXI_PERSONA = """You are Lexi, a cheerful, witty parrot who is an expert English tutor.
You speak in a warm, encouraging tone — like a fun game character guiding an adventure.

Personality traits:
- Playful and humorous, but always educational
- Uses short, clear sentences appropriate to the learner's level
- Celebrates small victories with enthusiasm ("Squawk! Great job! ")
- Gently corrects mistakes with encouraging context
- Occasionally drops parrot-themed phrases ("Polly wants proper grammar!")
- Adapts difficulty based on learner's CEFR level
- Keeps conversations flowing like a story / adventure

Story context rules:
- Each conversation is an "adventure" with Lexi
- Reference previous topics to build continuity
- Use the knowledge graph context to teach related concepts
- When the learner makes errors, weave corrections into the story naturally

Response format:
- Keep responses concise (2-4 sentences for dialogue)
- Use markdown for emphasis when helpful
- Include a gentle correction if errors are found
- Always end with something that invites the learner to continue
"""


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
    story_context: Optional[str] = Field(default=None, description="Story/adventure context")


class LexiCorrection(BaseModel):
    """A grammar/vocabulary correction."""
    error_span: str = ""
    correction: str = ""
    error_type: str = ""
    explanation: str = ""


class LexiChatResponse(BaseModel):
    """Structured response from Lexi."""
    success: bool = True
    session_id: str
    message_id: str
    lexi_response: str
    audio_base64: Optional[str] = None
    corrections: List[LexiCorrection] = []
    linked_concepts: List[str] = []
    vietnamese_hint: Optional[str] = None
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


# ─── Helper: TTS synthesis ──────────────────────────────────────────────────
async def _synthesize_tts(text: str) -> Optional[str]:
    """Generate TTS audio and return base64-encoded MP3."""
    try:
        from gtts import gTTS
        
        # Clean text for TTS (remove markdown, emojis)
        clean = re.sub(r'[*_~`#]', '', text)
        clean = re.sub(r'[\U00010000-\U0010ffff]', '', clean, flags=re.UNICODE)
        clean = clean.strip()
        
        if not clean:
            return None
        
        tts = gTTS(text=clean, lang='en', slow=False)
        buf = io.BytesIO()
        tts.write_to_fp(buf)
        buf.seek(0)
        audio_b64 = base64.b64encode(buf.read()).decode('utf-8')
        logger.info(f" Lexi TTS: {len(audio_b64)} bytes base64")
        return audio_b64
    except Exception as e:
        logger.warning(f"TTS failed: {e}")
        return None


# ─── Helper: STT transcription ──────────────────────────────────────────────
async def _transcribe_audio(audio_base64: str) -> Optional[str]:
    """Transcribe base64 audio using ModelGateway Whisper."""
    try:
        from api.services.model_gateway import get_gateway
        
        audio_bytes = base64.b64decode(audio_base64)
        gateway = await get_gateway()
        result = await gateway.invoke("whisper", "transcribe", {"audio_bytes": audio_bytes})
        text = result.get("data", {}).get("text", "") if result.get("success") else ""
        if not text:
            text = result.get("text", "")
        logger.info(f" Lexi STT: '{text[:50]}...'")
        return text if text else None
    except Exception as e:
        logger.warning(f"STT failed: {e}")
        return None


# ─── Pipeline result ─────────────────────────────────────────────────────────

@dataclass
class _PipelineResult:
    lexi_response: str
    user_text: str
    message_id: str
    session_id: str
    corrections: List["LexiCorrection"] = field(default_factory=list)
    linked_concepts: List[str] = field(default_factory=list)
    vietnamese_hint: Optional[str] = None
    scores: Optional[Dict[str, Any]] = None
    model_used: str = "trace-cag"
    story_ctx: Optional[str] = None
    audio_b64: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


async def _run_lexi_pipeline(
    request: "LexiChatRequest",
    session_id: str,
    history: List[Dict[str, Any]],
    db: AsyncIOMotorDatabase,
    quota: Any,
    start_time: float,
) -> _PipelineResult:
    """Execute the full Lexi pipeline (STT → TraceCAG → TTS → persist) and return results.

    Extracted so both the regular /chat and the streaming /stream endpoints
    can share the same logic without duplication.
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
    vietnamese_hint: Optional[str] = None
    scores: Optional[Dict[str, Any]] = None
    model_used = "trace-cag"

    try:
        from api.services.orchestrator import get_orchestrator

        orchestrator = await get_orchestrator()
        graph_result = await orchestrator.process(
            user_input=user_text,
            session_id=session_id,
            user_id=request.user_id,
            learner_profile={"level": request.learner_level},
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
        vietnamese_hint = graph_result.get("vietnamese_hint")
        scores = graph_result.get("scores")
        metadata["pipeline_steps"].append("trace-cag_complete")
        metadata["trace-cag_metadata"] = graph_result.get("metadata", {})
        model_used = ", ".join(graph_result.get("metadata", {}).get("models_used", ["trace-cag"]))

    except Exception as e:
        logger.error("TraceCAG hard failure in Lexi pipeline (primary): %s", e)
        metadata["pipeline_steps"].append("trace-cag_failed_primary")
        try:
            from api.services.orchestrator import get_orchestrator

            orchestrator = await get_orchestrator()
            retry_result = await orchestrator.process(
                user_input=user_text,
                session_id=session_id,
                user_id=request.user_id,
                learner_profile={"level": request.learner_level},
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
        sess_data = await _store.get_session(session_id)
        story_ctx = (sess_data or {}).get("story_context")

    if not lexi_response:
        lexi_response = SAFE_FIXED_RESPONSE
        model_used = "trace-cag_safe_response"
        metadata["pipeline_steps"].append("trace-cag_empty_response_guard")

    lexi_response = _sanitize_lexi_response(lexi_response)
    metadata["model_used"] = model_used

    # ── TTS ──
    audio_b64: Optional[str] = None
    if request.enable_tts:
        audio_b64 = await _synthesize_tts(lexi_response)
        metadata["pipeline_steps"].append("tts_complete" if audio_b64 else "tts_skipped")

    # ── Persist messages ──
    message_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()

    await _store.append_message(session_id, {
        "id": str(uuid.uuid4()),
        "role": "user",
        "content": user_text,
        "timestamp": timestamp,
    })
    await _store.append_message(session_id, {
        "id": message_id,
        "role": "assistant",
        "content": lexi_response,
        "timestamp": timestamp,
    })

    await db["lexi_messages"].insert_many([
        {
            "id": str(uuid.uuid4()),
            "session_id": session_id,
            "user_id": request.user_id,
            "role": "user",
            "content": user_text,
            "timestamp": timestamp,
        },
        {
            "id": message_id,
            "session_id": session_id,
            "user_id": request.user_id,
            "role": "assistant",
            "content": lexi_response,
            "timestamp": timestamp,
        },
    ])

    await db["lexi_sessions"].update_one(
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
    )

    cached_session = await _store.get_session(session_id) or {}
    cached_count = int(cached_session.get("message_count") or 0)
    await _store.set_session(session_id, {
        "session_id": session_id,
        "user_id": request.user_id,
        "created_at": cached_session.get("created_at", timestamp),
        "updated_at": timestamp,
        "title": cached_session.get("title", "Lexi Chat"),
        "message_count": cached_count + 2,
        "persona": cached_session.get("persona", "lexi"),
        "story_context": story_ctx,
    })

    try:
        from api.core.redis_client import ConversationCache, RedisClient
        _redis = await RedisClient.get_instance()
        _conv_cache = ConversationCache(_redis)
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

    return _PipelineResult(
        lexi_response=lexi_response,
        user_text=user_text,
        message_id=message_id,
        session_id=session_id,
        corrections=corrections,
        linked_concepts=linked_concepts,
        vietnamese_hint=vietnamese_hint,
        scores=scores,
        model_used=model_used,
        story_ctx=story_ctx,
        audio_b64=audio_b64,
        metadata=metadata,
    )


# ─── Routes ──────────────────────────────────────────────────────────────────
@router.post("/sessions", response_model=LexiSessionResponse)
async def create_lexi_session(
    request: LexiSessionRequest = LexiSessionRequest(),
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> LexiSessionResponse:
    """Create a new conversation session with Lexi."""
    auth_user_id = enforce_user_scope(current_user, request.user_id)
    request = request.model_copy(update={"user_id": auth_user_id})

    session_id = str(uuid.uuid4())
    now = datetime.utcnow().isoformat()
    
    await _store.set_session(session_id, {
        "session_id": session_id,
        "user_id": request.user_id,
        "created_at": now,
        "updated_at": now,
        "title": "Lexi Chat",
        "message_count": 0,
        "persona": "lexi",
        "story_context": None,
    })
    await _store.init_messages(session_id)

    await db["lexi_sessions"].update_one(
        {"session_id": session_id},
        {
            "$set": {
                "session_id": session_id,
                "user_id": request.user_id,
                "title": "Lexi Chat",
                "created_at": now,
                "updated_at": now,
                "message_count": 0,
                "persona": "lexi",
            }
        },
        upsert=True,
    )
    
    logger.info(f" Lexi session created: {session_id[:8]}... for user: {request.user_id}")
    return LexiSessionResponse(session_id=session_id, created_at=now)


@router.post("/chat", response_model=LexiChatResponse)
async def lexi_chat(
    request_context: Request,
    request: LexiChatRequest,
    x_idempotency_key: Optional[str] = Header(
        default=None,
        alias="X-Idempotency-Key",
    ),
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> LexiChatResponse:
    """
    Chat with Lexi — the full AI pipeline.

    Pipeline flow:
      1. Session management (create if needed)
      2. STT transcription (if voice input)
      3. TraceCAG pipeline (KG expansion + retrieval)
      4. LLM generation with Lexi persona (Groq → Gemini → Ollama)
      5. TTS synthesis (if enabled)
      6. Return structured response
    """
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
    auth_user_id = enforce_user_scope(current_user, request.user_id)
    request = request.model_copy(update={"user_id": auth_user_id})

    quota = await enforce_user_quota(
        current_user.user_id,
        "lexi.chat",
        token_cost=default_token_cost_for_endpoint("lexi.chat", text=request.message),
        fail_closed=True,
    )

    # ── 1. Session management ──
    session_id = request.session_id or str(uuid.uuid4())
    if not await _store.has_session(session_id):
        await _store.set_session(session_id, {
            "session_id": session_id,
            "user_id": request.user_id,
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat(),
            "title": "Lexi Chat",
            "message_count": 0,
            "persona": "lexi",
            "story_context": request.story_context,
        })
        await _store.init_messages(session_id)

        await db["lexi_sessions"].update_one(
            {"session_id": session_id},
            {
                "$set": {
                    "session_id": session_id,
                    "user_id": request.user_id,
                    "title": "Lexi Chat",
                    "created_at": datetime.utcnow().isoformat(),
                    "updated_at": datetime.utcnow().isoformat(),
                    "message_count": 0,
                    "persona": "lexi",
                }
            },
            upsert=True,
        )

    request_hash = _idempotency_request_hash(request)
    if x_idempotency_key:
        cached_response = await _idempotency_store.get(
            user_id=request.user_id,
            session_id=session_id,
            idempotency_key=x_idempotency_key,
            request_hash=request_hash,
        )
        if cached_response:
            return LexiChatResponse(**cached_response)

    history = await _store.get_messages(session_id)

    # ── 2–6. Execute shared pipeline (STT → TraceCAG → TTS → persist) ──
    result = await _run_lexi_pipeline(
        request=request,
        session_id=session_id,
        history=history,
        db=db,
        quota=quota,
        start_time=start_time,
    )

    # ── 7. Build response ──
    logger.info(
        f" Lexi chat complete — {result.metadata['latency_ms']}ms, "
        f"model: {result.model_used}, steps: {result.metadata['pipeline_steps']}"
    )

    await emit_ai_audit_event(
        {
            "request_id": request_id,
            "user_id": current_user.user_id,
            "endpoint": "lexi.chat",
            "status": "success",
            "session_id": result.session_id,
            "model_used": result.model_used,
            "latency_ms": result.metadata["latency_ms"],
            "quota": result.metadata["quota"],
        }
    )

    response = LexiChatResponse(
        session_id=result.session_id,
        message_id=result.message_id,
        lexi_response=result.lexi_response,
        audio_base64=result.audio_b64,
        corrections=result.corrections,
        linked_concepts=result.linked_concepts,
        vietnamese_hint=result.vietnamese_hint,
        scores=result.scores,
        story_context=result.story_ctx,
        metadata=result.metadata,
    )

    if x_idempotency_key:
        await _idempotency_store.set(
            user_id=request.user_id,
            session_id=session_id,
            idempotency_key=x_idempotency_key,
            request_hash=request_hash,
            response=response.model_dump(),
        )

    return response


@router.post("/stream")
async def lexi_stream_chat(
    request_context: Request,
    request: LexiChatRequest,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> StreamingResponse:
    """
    Chat with Lexi — streaming SSE variant.

    Returns a text/event-stream response. Events:
      • ``thinking``  — sent immediately to signal the pipeline has started
      • ``chunk``     — one word at a time as the response is "typed out"
      • ``done``      — final event carrying message_id, corrections, audio, etc.
      • ``error``     — sent if the pipeline raises an unrecoverable error

    The full AI pipeline (TraceCAG + TTS) still runs to completion before
    streaming begins, so overall latency is the same as /chat.  The benefit
    is the typewriter typing-effect on the client side.
    """
    start_time = time.time()
    request_id = request_context.headers.get("X-Request-Id") or str(uuid.uuid4())
    auth_user_id = enforce_user_scope(current_user, request.user_id)
    request = request.model_copy(update={"user_id": auth_user_id})

    quota = await enforce_user_quota(
        current_user.user_id,
        "lexi.chat",
        token_cost=default_token_cost_for_endpoint("lexi.chat", text=request.message),
        fail_closed=True,
    )

    # ── Session management (same as /chat) ──
    session_id = request.session_id or str(uuid.uuid4())
    if not await _store.has_session(session_id):
        await _store.set_session(session_id, {
            "session_id": session_id,
            "user_id": request.user_id,
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat(),
            "title": "Lexi Chat",
            "message_count": 0,
            "persona": "lexi",
            "story_context": request.story_context,
        })
        await _store.init_messages(session_id)
        await db["lexi_sessions"].update_one(
            {"session_id": session_id},
            {
                "$set": {
                    "session_id": session_id,
                    "user_id": request.user_id,
                    "title": "Lexi Chat",
                    "created_at": datetime.utcnow().isoformat(),
                    "updated_at": datetime.utcnow().isoformat(),
                    "message_count": 0,
                    "persona": "lexi",
                }
            },
            upsert=True,
        )

    history = await _store.get_messages(session_id)

    async def _sse_generator() -> AsyncGenerator[str, None]:
        # Signal that the pipeline has started
        yield f"event: thinking\ndata: {{}}\n\n"

        try:
            result = await _run_lexi_pipeline(
                request=request,
                session_id=session_id,
                history=history,
                db=db,
                quota=quota,
                start_time=start_time,
            )
        except Exception as exc:
            logger.error("Lexi /stream pipeline error: %s", exc)
            err_payload = json.dumps({"error": "Pipeline failed. Please try again."})
            yield f"event: error\ndata: {err_payload}\n\n"
            return

        # Stream the response text word by word (typewriter effect, ~30ms/word)
        words = result.lexi_response.split(" ")
        for i, word in enumerate(words):
            chunk = word if i == 0 else f" {word}"
            yield f"event: chunk\ndata: {json.dumps({'text': chunk})}\n\n"
            await asyncio.sleep(0.03)

        # Final event with all metadata
        done_payload = json.dumps({
            "message_id": result.message_id,
            "session_id": result.session_id,
            "corrections": [
                {
                    "error_span": c.error_span,
                    "correction": c.correction,
                    "error_type": c.error_type,
                    "explanation": c.explanation,
                }
                for c in result.corrections
            ],
            "linked_concepts": result.linked_concepts,
            "vietnamese_hint": result.vietnamese_hint,
            "scores": result.scores,
            "story_context": result.story_ctx,
            "audio_base64": result.audio_b64,
            "metadata": result.metadata,
        })
        yield f"event: done\ndata: {done_payload}\n\n"

        logger.info(
            f" Lexi stream complete — {result.metadata['latency_ms']}ms, "
            f"model: {result.model_used}"
        )
        await emit_ai_audit_event(
            {
                "request_id": request_id,
                "user_id": current_user.user_id,
                "endpoint": "lexi.stream",
                "status": "success",
                "session_id": result.session_id,
                "model_used": result.model_used,
                "latency_ms": result.metadata["latency_ms"],
                "quota": result.metadata["quota"],
            }
        )

    return StreamingResponse(
        _sse_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",  # disable nginx proxy buffering for SSE
            "Connection": "keep-alive",
        },
    )


@router.get("/sessions/{session_id}/messages")
async def get_lexi_messages(
    session_id: str,
    limit: int = Query(100, ge=1, le=200),
    cursor: str | None = None,
    full: bool = Query(False, description="Set true to force full session history load"),
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    """Get messages in a Lexi session.

    By default this endpoint returns a bounded page to avoid heavy full-session scans.
    Set `full=true` only for maintenance/legacy flows that require the entire history.
    """
    if not full:
        return await get_lexi_messages_paged(
            session_id=session_id,
            limit=limit,
            cursor=cursor,
            db=db,
            current_user=current_user,
        )

    session_doc = await _ensure_session_owner(session_id, current_user, db)
    cached_session = await _store.get_session(session_id)
    cached_messages = await _store.get_messages(session_id) if cached_session else []

    expected_count = int((session_doc or {}).get("message_count") or 0)
    cache_is_complete = cached_session is not None and (
        expected_count == 0 or len(cached_messages) >= expected_count
    )

    if cache_is_complete:
        return {
            "success": True,
            "session_id": session_id,
            "messages": cached_messages,
        }

    if not session_doc:
        if cached_session is not None:
            return {
                "success": True,
                "session_id": session_id,
                "messages": cached_messages,
            }
        raise HTTPException(status_code=404, detail="Session not found")

    cursor = db["lexi_messages"].find({"session_id": session_id}).sort("timestamp", 1)
    messages = await _load_full_cursor(cursor)
    payload = [
        {
            "id": m.get("id", str(uuid.uuid4())),
            "role": m.get("role", "user"),
            "content": m.get("content", ""),
            "timestamp": m.get("timestamp", datetime.utcnow().isoformat()),
        }
        for m in messages
    ]

    # Rehydrate cache for faster next reads.
    await _store.set_session(session_id, {
        "session_id": session_doc.get("session_id"),
        "user_id": session_doc.get("user_id", "demo_user"),
        "created_at": session_doc.get("created_at", datetime.utcnow().isoformat()),
        "updated_at": session_doc.get("updated_at", datetime.utcnow().isoformat()),
        "title": session_doc.get("title", "Lexi Chat"),
        "message_count": session_doc.get("message_count", len(payload)),
        "persona": session_doc.get("persona", "lexi"),
        "story_context": session_doc.get("story_context"),
    })
    await _store.delete_messages(session_id)
    for item in payload:
        await _store.append_message(session_id, item)

    return {
        "success": True,
        "session_id": session_id,
        "messages": payload,
    }


@router.get("/sessions/{session_id}/messages/paged")
async def get_lexi_messages_paged(
    session_id: str,
    limit: int = 50,
    cursor: str | None = None,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    await _ensure_session_owner(session_id, current_user, db)

    if limit < 1:
        raise HTTPException(status_code=400, detail="limit must be >= 1")

    safe_limit = min(limit, 200)
    base_query: Dict[str, Any] = {"session_id": session_id}
    query: Dict[str, Any] = dict(base_query)

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
        db["lexi_messages"]
        .find(query)
        .sort([("timestamp", -1), ("_id", -1)])
        .limit(safe_limit + 1)
        .to_list(length=safe_limit + 1)
    )

    has_more = len(docs_desc) > safe_limit
    docs_desc = docs_desc[:safe_limit]
    docs = list(reversed(docs_desc))
    messages = [_serialize_lexi_message(doc) for doc in docs]

    total_count = await db["lexi_messages"].count_documents(base_query)
    next_cursor = _encode_cursor(docs[0]) if has_more and docs else None
    prev_cursor = _encode_cursor(docs[-1]) if docs else None
    window_start_ts = _to_iso_timestamp(docs[0].get("timestamp")) if docs else None
    window_end_ts = _to_iso_timestamp(docs[-1].get("timestamp")) if docs else None

    return {
        "success": True,
        "session_id": session_id,
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


@router.get("/sessions/{session_id}/messages/metadata")
async def get_lexi_messages_metadata(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    await _ensure_session_owner(session_id, current_user, db)

    base_query: Dict[str, Any] = {"session_id": session_id}
    total_count = await db["lexi_messages"].count_documents(base_query)

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
                "has_more": False,
                "next_cursor": None,
                "prev_cursor": None,
                "window_start_ts": None,
                "window_end_ts": None,
            },
        }

    latest_docs = await (
        db["lexi_messages"]
        .find(base_query)
        .sort([("timestamp", -1), ("_id", -1)])
        .limit(1)
        .to_list(length=1)
    )
    oldest_docs = await (
        db["lexi_messages"]
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
        "success": True,
        "session_id": session_id,
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
        },
    }


@router.get("/sessions/user/{user_id}", response_model=LexiSessionListResponse)
async def list_lexi_sessions(
    user_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> LexiSessionListResponse:
    enforce_user_scope(current_user, user_id)
    try:
        cursor = db["lexi_sessions"].find({"user_id": user_id}).sort("updated_at", -1)
        rows = await cursor.to_list(length=100)
    except Exception as exc:
        msg = str(exc).lower()
        if not (isinstance(exc, OperationFailure) and ("order-by item is excluded" in msg or "index path corresponding" in msg)):
            raise
        rows = await db["lexi_sessions"].find({"user_id": user_id}).limit(100).to_list(length=100)
        rows.sort(key=lambda row: row.get("updated_at") or row.get("created_at") or "", reverse=True)
    sessions = [
        LexiSessionSummary(
            session_id=row.get("session_id", ""),
            user_id=row.get("user_id", user_id),
            title=row.get("title", "Lexi Chat"),
            created_at=row.get("created_at", datetime.utcnow().isoformat()),
            updated_at=row.get("updated_at", row.get("created_at", datetime.utcnow().isoformat())),
            message_count=int(row.get("message_count", 0)),
        )
        for row in rows
        if row.get("session_id")
    ]
    return LexiSessionListResponse(sessions=sessions)


@router.post("/sessions/{session_id}/rename")
async def rename_lexi_session(
    session_id: str,
    request: LexiSessionRenameRequest,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    await _ensure_session_owner(session_id, current_user, db)

    title = request.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="Title cannot be empty")

    now = datetime.utcnow().isoformat()
    result = await db["lexi_sessions"].update_one(
        {"session_id": session_id},
        {"$set": {"title": title, "updated_at": now}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Session not found")

    sess = await _store.get_session(session_id)
    if sess:
        sess["title"] = title
        sess["updated_at"] = now
        await _store.set_session(session_id, sess)

    return {"success": True, "session_id": session_id, "title": title}


@router.post("/sessions/{session_id}/delete")
async def delete_lexi_session(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> Dict[str, Any]:
    await _ensure_session_owner(session_id, current_user, db)

    await db["lexi_sessions"].delete_one({"session_id": session_id})
    await db["lexi_messages"].delete_many({"session_id": session_id})
    await _store.delete_session(session_id)
    await _store.delete_messages(session_id)
    return {"success": True, "session_id": session_id}


@router.get("/health")
async def lexi_health() -> Dict[str, Any]:
    """Health check for Lexi chat service."""
    return {
        "status": "ok",
        "service": "lexi-chat",
        "persona": "lexi-the-parrot",
        "capabilities": ["text-chat", "voice-input", "tts-output", "trace-cag-retrieval"],
    }
