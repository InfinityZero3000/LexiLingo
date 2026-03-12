"""
Lexi Chat Route — Story-driven conversational AI with the parrot mascot.

Pipeline:
  1. STT (if voice input) → Whisper transcription
  2. GraphCAG pipeline → KG expansion + diagnosis + retrieval
  3. Persona-injected LLM generation (Groq → Gemini → Ollama fallback)
  4. TTS synthesis → gTTS / Piper for Lexi's voice
  5. Return structured response with audio, story context, corrections

Integrates with the existing GraphCAG system for document retrieval
and knowledge graph expansion to make conversations contextually rich.
"""

import logging
import os
import re
import io
import json
import uuid
import time
import base64
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

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
    _TTL = timedelta(hours=4)

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


_store = _LexiStore()


# ─── Lexi Persona System Prompt ─────────────────────────────────────────────
LEXI_PERSONA = """You are Lexi 🦜, a cheerful, witty parrot who is an expert English tutor.
You speak in a warm, encouraging tone — like a fun game character guiding an adventure.

Personality traits:
- Playful and humorous, but always educational
- Uses short, clear sentences appropriate to the learner's level
- Celebrates small victories with enthusiasm ("Squawk! Great job! 🎉")
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


# ─── Helper: Build conversation messages for LLM ────────────────────────────
def _build_llm_messages(
    user_message: str,
    history: List[Dict[str, Any]],
    graph_context: str = "",
    learner_level: str = "B1",
    story_context: Optional[str] = None,
) -> List[Dict[str, str]]:
    """Build the message array for the LLM with Lexi's persona."""
    system_prompt = LEXI_PERSONA
    
    if graph_context:
        system_prompt += f"\n\n--- Knowledge Graph Context ---\n{graph_context}"
    
    if story_context:
        system_prompt += f"\n\n--- Current Story/Adventure ---\n{story_context}"
    
    system_prompt += f"\n\nThe learner's current CEFR level is: {learner_level}"

    messages = [{"role": "system", "content": system_prompt}]

    # Add recent history (last 10 messages for context window)
    for msg in history[-10:]:
        messages.append({
            "role": msg.get("role", "user"),
            "content": msg.get("content", ""),
        })

    messages.append({"role": "user", "content": user_message})
    return messages


# ─── Helper: Get LLM response with fallback chain ───────────────────────────
async def _get_lexi_llm_response(messages: List[Dict[str, str]]) -> tuple[str, str]:
    """
    Get LLM response using Groq → Gemini → Ollama fallback chain.
    Returns (response_text, model_used).
    """
    # ── 1. Groq (fast, free tier) ──
    groq_key = os.getenv("GROQ_API_KEY", "")
    groq_model = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
    if groq_key:
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(
                    "https://api.groq.com/openai/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {groq_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": groq_model,
                        "messages": messages,
                        "max_tokens": 512,
                        "temperature": 0.7,
                    },
                )
                if resp.status_code == 200:
                    data = resp.json()
                    text = data["choices"][0]["message"]["content"]
                    logger.info(f"✅ Lexi: Groq response ({len(text)} chars)")
                    return text, f"groq/{groq_model}"
        except Exception as e:
            logger.warning(f"Groq failed for Lexi: {e}")

    # ── 2. Gemini (cloud fallback) ──
    gemini_key = os.getenv("GEMINI_API_KEY", "")
    if gemini_key:
        try:
            # Convert messages to Gemini multi-turn format
            # Separate system instruction from conversation turns
            system_instruction = ""
            gemini_contents = []
            for m in messages:
                if m["role"] == "system":
                    system_instruction = m["content"]
                elif m["role"] == "user":
                    gemini_contents.append({"role": "user", "parts": [{"text": m["content"]}]})
                else:
                    gemini_contents.append({"role": "model", "parts": [{"text": m["content"]}]})
            
            url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={gemini_key}"
            request_body: Dict[str, Any] = {"contents": gemini_contents}
            if system_instruction:
                request_body["systemInstruction"] = {"parts": [{"text": system_instruction}]}
            
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(url, json=request_body)
                if resp.status_code == 200:
                    data = resp.json()
                    candidates = data.get("candidates", [])
                    if candidates:
                        text = candidates[0]["content"]["parts"][0]["text"]
                        logger.info(f"✅ Lexi: Gemini response ({len(text)} chars)")
                        return text, "gemini-2.0-flash"
        except Exception as e:
            logger.warning(f"Gemini failed for Lexi: {e}")

    # ── 3. Ollama local (offline fallback) ──
    ollama_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
    ollama_model = os.getenv("OLLAMA_MODEL", "qwen3:4b")
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                f"{ollama_url}/api/chat",
                json={
                    "model": ollama_model,
                    "messages": messages,
                    "stream": False,
                    "options": {"num_predict": 256, "temperature": 0.7},
                },
            )
            if resp.status_code == 200:
                text = resp.json().get("message", {}).get("content", "")
                if text:
                    logger.info(f"✅ Lexi: Ollama response ({len(text)} chars)")
                    return text, f"ollama/{ollama_model}"
    except Exception as e:
        logger.warning(f"Ollama failed for Lexi: {e}")

    # ── 4. Static fallback ──
    return (
        "Squawk! 🦜 I'm having a little trouble right now. "
        "My feathers got ruffled — try again in a moment!",
        "fallback",
    )


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
        logger.info(f"✅ Lexi TTS: {len(audio_b64)} bytes base64")
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
        logger.info(f"✅ Lexi STT: '{text[:50]}...'")
        return text if text else None
    except Exception as e:
        logger.warning(f"STT failed: {e}")
        return None


# ─── Routes ──────────────────────────────────────────────────────────────────
@router.post("/sessions", response_model=LexiSessionResponse)
async def create_lexi_session(
    request: LexiSessionRequest = LexiSessionRequest(),
) -> LexiSessionResponse:
    """Create a new conversation session with Lexi."""
    session_id = str(uuid.uuid4())
    now = datetime.utcnow().isoformat()
    
    await _store.set_session(session_id, {
        "session_id": session_id,
        "user_id": request.user_id,
        "created_at": now,
        "persona": "lexi",
        "story_context": None,
    })
    await _store.init_messages(session_id)
    
    logger.info(f"🦜 Lexi session created: {session_id[:8]}... for user: {request.user_id}")
    return LexiSessionResponse(session_id=session_id, created_at=now)


@router.post("/chat", response_model=LexiChatResponse)
async def lexi_chat(request: LexiChatRequest) -> LexiChatResponse:
    """
    Chat with Lexi — the full AI pipeline.
    
    Pipeline flow:
      1. Session management (create if needed)
      2. STT transcription (if voice input)
      3. GraphCAG pipeline (KG expansion + retrieval)
      4. LLM generation with Lexi persona (Groq → Gemini → Ollama)
      5. TTS synthesis (if enabled)
      6. Return structured response
    """
    start_time = time.time()
    metadata: Dict[str, Any] = {"pipeline_steps": []}
    
    # ── 1. Session management ──
    session_id = request.session_id or str(uuid.uuid4())
    if not await _store.has_session(session_id):
        await _store.set_session(session_id, {
            "session_id": session_id,
            "user_id": request.user_id,
            "created_at": datetime.utcnow().isoformat(),
            "persona": "lexi",
            "story_context": request.story_context,
        })
        await _store.init_messages(session_id)
    
    history = await _store.get_messages(session_id)
    metadata["pipeline_steps"].append("session_ready")
    
    # ── 2. STT (if voice input) ──
    user_text = request.message
    if request.input_type == "voice" and request.audio_base64:
        transcript = await _transcribe_audio(request.audio_base64)
        if transcript:
            user_text = transcript
            metadata["pipeline_steps"].append("stt_complete")
            metadata["stt_transcript"] = transcript
        else:
            metadata["pipeline_steps"].append("stt_failed")
    
    # ── 3. GraphCAG pipeline (knowledge expansion + retrieval + LLM generation) ──
    # NOTE: GraphCAG generate_node now calls the LLM directly with persona,
    # so we use its tutor_response as the final Lexi response. No separate
    # LLM call is needed — this eliminates the double-LLM issue.
    lexi_response = ""
    corrections: List[LexiCorrection] = []
    linked_concepts: List[str] = []
    vietnamese_hint: Optional[str] = None
    scores: Optional[Dict[str, Any]] = None
    model_used = "graphcag"
    
    try:
        from api.services.graph_cag.graph import get_graph_cag
        
        pipeline = await get_graph_cag()
        graph_result = await pipeline.analyze(
            user_input=user_text,
            session_id=session_id,
            user_id=request.user_id,
            learner_profile={"level": request.learner_level},
            conversation_history=history,
        )
        
        # Use the GraphCAG tutor_response directly as Lexi's response
        lexi_response = graph_result.get("tutor_response", "")
        
        # Extract corrections
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
        
        metadata["pipeline_steps"].append("graphcag_complete")
        metadata["graphcag_metadata"] = graph_result.get("metadata", {})
        model_used = ", ".join(graph_result.get("metadata", {}).get("models_used", ["graphcag"]))
        
    except Exception as e:
        logger.warning(f"GraphCAG unavailable, using standalone LLM: {e}")
        metadata["pipeline_steps"].append("graphcag_failed")
    
    # ── 4. Fallback: standalone LLM only if GraphCAG didn't produce a response ──
    story_ctx = request.story_context
    if not story_ctx:
        sess_data = await _store.get_session(session_id)
        story_ctx = (sess_data or {}).get("story_context")
    if not lexi_response:
        llm_messages = _build_llm_messages(
            user_message=user_text,
            history=history,
            graph_context="",
            learner_level=request.learner_level,
            story_context=story_ctx,
        )
        lexi_response, model_used = await _get_lexi_llm_response(llm_messages)
        metadata["pipeline_steps"].append("llm_fallback_complete")
    
    metadata["model_used"] = model_used
    
    # ── 5. TTS synthesis ──
    audio_b64: Optional[str] = None
    if request.enable_tts:
        audio_b64 = await _synthesize_tts(lexi_response)
        if audio_b64:
            metadata["pipeline_steps"].append("tts_complete")
        else:
            metadata["pipeline_steps"].append("tts_skipped")
    
    # ── 6. Store messages (Redis-backed) ──
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

    # Write-back to ConversationCache so input_node gets real history on next turn
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
    
    # ── 7. Build response ──
    total_ms = int((time.time() - start_time) * 1000)
    metadata["latency_ms"] = total_ms
    
    logger.info(
        f"🦜 Lexi chat complete — {total_ms}ms, model: {model_used}, "
        f"steps: {metadata['pipeline_steps']}"
    )
    
    return LexiChatResponse(
        session_id=session_id,
        message_id=message_id,
        lexi_response=lexi_response,
        audio_base64=audio_b64,
        corrections=corrections,
        linked_concepts=linked_concepts,
        vietnamese_hint=vietnamese_hint,
        scores=scores,
        story_context=story_ctx,
        metadata=metadata,
    )


@router.get("/sessions/{session_id}/messages")
async def get_lexi_messages(session_id: str) -> Dict[str, Any]:
    """Get all messages in a Lexi session."""
    if not await _store.has_session(session_id):
        raise HTTPException(status_code=404, detail="Session not found")
    
    return {
        "success": True,
        "session_id": session_id,
        "messages": await _store.get_messages(session_id),
    }


@router.get("/health")
async def lexi_health() -> Dict[str, Any]:
    """Health check for Lexi chat service."""
    return {
        "status": "ok",
        "service": "lexi-chat",
        "persona": "lexi-the-parrot",
        "capabilities": ["text-chat", "voice-input", "tts-output", "graphcag-retrieval"],
    }
