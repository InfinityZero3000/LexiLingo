"""
LexiLingo AI Service

API for Chat, STT, TTS with ModelGateway for lazy loading.
Supports Qwen (local), OpenRouter, or Gemini (cloud) for chat.
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Body, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, JSONResponse
from contextlib import asynccontextmanager
from starlette.middleware.base import BaseHTTPMiddleware
import logging
import os
import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel
from motor.motor_asyncio import AsyncIOMotorClient

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load .env file
from dotenv import load_dotenv
load_dotenv()


# ============================================================
# Private Network Access Middleware (Chrome CORS-RFC1918)
# ============================================================
class PrivateNetworkAccessMiddleware(BaseHTTPMiddleware):
    """
    Middleware to handle Chrome's Private Network Access (CORS-RFC1918).
    
    Chrome 94+ requires Access-Control-Allow-Private-Network: true header
    on BOTH the OPTIONS preflight AND the actual request response.
    Without this header on the actual request, Chrome blocks it with 'Failed to fetch'.
    """
    async def dispatch(self, request: Request, call_next):
        # Check if this is a private network access request
        has_pna_header = (
            request.headers.get("access-control-request-private-network") == "true"
        )
        
        response = await call_next(request)
        
        # Add PNA header to response if request had it (for both OPTIONS and actual requests)
        if has_pna_header or request.method == "OPTIONS":
            response.headers["Access-Control-Allow-Private-Network"] = "true"
        
        return response


# Environment
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
USE_GATEWAY = os.getenv("USE_GATEWAY", "true").lower() == "true"
USE_QWEN = os.getenv("USE_QWEN", "true").lower() == "true"
QWEN_MODEL = os.getenv("QWEN_MODEL_NAME", "Qwen/Qwen3-1.7B")
MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", os.getenv("MONGODB_DB_NAME", "lexilingo"))
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")

# Ollama config
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "lexilingo-qwen3-1.7b")
OLLAMA_TIMEOUT = int(os.getenv("OLLAMA_TIMEOUT", "120"))
OLLAMA_NUM_THREADS = int(os.getenv("OLLAMA_NUM_THREADS", "8"))
OLLAMA_MAX_TOKENS = int(os.getenv("OLLAMA_MAX_TOKENS", "128"))
OLLAMA_CONTEXT_LENGTH = int(os.getenv("OLLAMA_CONTEXT_LENGTH", "512"))

# Global Qwen engine (legacy - for fallback if gateway not used)
qwen_engine = None

# Gateway instance (lazy initialized)
_gateway_initialized = False

# MongoDB client (for admin config)
_mongo_client: Optional[AsyncIOMotorClient] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    global _gateway_initialized, _mongo_client
    
    # Startup
    # Initialize MongoDB client
    try:
        _mongo_client = AsyncIOMotorClient(MONGODB_URI)
        await _mongo_client.admin.command('ping')
        logger.info("✓ MongoDB connected")
    except Exception as e:
        logger.warning(f"MongoDB connection failed: {e}")
        _mongo_client = None
    
    if USE_GATEWAY:
        try:
            from api.services.gateway_setup import setup_gateway
            await setup_gateway(
                max_memory_mb=int(os.getenv("MAX_MEMORY_MB", "8000")),
                enable_auto_unload=True,
                use_gemini_fallback=bool(GEMINI_API_KEY),
            )
            _gateway_initialized = True
            logger.info("✓ ModelGateway initialized")
        except Exception as e:
            logger.warning(f"Failed to initialize gateway: {e}, using legacy mode")
            _gateway_initialized = False
    
    yield
    
    # Shutdown
    if _mongo_client:
        _mongo_client.close()
        logger.info("MongoDB client closed")
    
    if _gateway_initialized:
        try:
            from api.services.gateway_setup import shutdown_gateway
            await shutdown_gateway()
        except Exception as e:
            logger.warning(f"Gateway shutdown error: {e}")


# FastAPI App
app = FastAPI(
    title="LexiLingo AI Service",
    description="AI Service for Chat, STT, TTS with ModelGateway",
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:5173",
        "http://localhost:5176",  # Admin Dashboard
        "http://localhost:8080",
        "http://localhost:8000",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Private Network Access (Chrome CORS-RFC1918)
app.add_middleware(PrivateNetworkAccessMiddleware)

# ============================================================
# Include Topic Chat Router
# ============================================================
try:
    import importlib, types, sys, os
    # Pre-register a stub package for api.routes to prevent __init__.py from 
    # loading all heavy route modules (ai.py → v3_pipeline → sentence_transformers)
    if "api.routes" not in sys.modules:
        _stub = types.ModuleType("api.routes")
        _stub.__path__ = [os.path.join(os.path.dirname(__file__), "routes")]
        _stub.__package__ = "api.routes"
        sys.modules["api.routes"] = _stub
    _topic_module = importlib.import_module("api.routes.topic_chat")
    topic_chat_router = _topic_module.router
    app.include_router(
        topic_chat_router,
        prefix="/api/v1/topics",
        tags=["Topic-Based Conversation"],
    )
    logger.info("✓ Topic Chat routes registered")
except Exception as e:
    logger.warning(f"Failed to register topic chat routes: {e}")

# ============================================================
# Include Admin Router
# ============================================================
try:
    _admin_module = importlib.import_module("api.routes.admin")
    admin_router = _admin_module.router
    app.include_router(
        admin_router,
        prefix="/api/v1/admin",
        tags=["Admin Configuration"],
    )
    logger.info("✓ Admin routes registered")
except Exception as e:
    logger.warning(f"Failed to register admin routes: {e}")

# ============================================================
# Request & Response Models
# ============================================================

class CreateSessionRequest(BaseModel):
    user_id: str
    title: Optional[str] = None


class SessionData(BaseModel):
    session_id: str
    user_id: str
    title: str
    created_at: str
    last_activity: str


class CreateSessionResponse(BaseModel):
    success: bool
    data: SessionData


class SendMessageRequest(BaseModel):
    user_id: str
    session_id: str
    message: str


class MessageData(BaseModel):
    message_id: str
    session_id: str
    user_message: str
    ai_response: str
    model_used: Optional[str] = None
    created_at: str


class SendMessageResponse(BaseModel):
    success: bool
    data: MessageData


# ============================================================
# In-memory storage (for development)
# ============================================================
sessions = {}
messages = {}


# ============================================================
# Helper Functions
# ============================================================

async def get_active_gemini_key() -> Optional[str]:
    """
    Get active Gemini API key with priority:
    1. Stored key from MongoDB (if exists)
    2. Environment variable GEMINI_API_KEY
    
    Returns:
        Active API key or None if not available
    """
    global _mongo_client
    
    # Try to get from database first
    if _mongo_client:
        try:
            db = _mongo_client[MONGODB_DATABASE]
            config = await db.admin_config.find_one({"_id": "ai_config"})
            if config and config.get("gemini_api_key"):
                logger.info("Using Gemini API key from database")
                return config["gemini_api_key"]
        except Exception as e:
            logger.warning(f"Failed to fetch API key from database: {e}")
    
    # Fallback to environment variable
    if GEMINI_API_KEY:
        logger.info("Using Gemini API key from environment variable")
        return GEMINI_API_KEY
    
    return None

# ============================================================
#  Groq Rate Limiter (sliding window)
#  Free tier: 30 RPM, 12K TPM, 14.4K RPD
# ============================================================
import time
import collections

class GroqRateLimiter:
    """
    Sliding-window rate limiter for Groq free tier.
    Limits: 30 RPM, 12,000 TPM, 14,400 RPD.
    Falls back (returns False) at 90% of each limit.
    """
    RPM_LIMIT   = 30
    TPM_LIMIT   = 12_000
    RPD_LIMIT   = 14_400
    SAFETY      = 0.90   # trigger fallback at 90% to be safe

    def __init__(self):
        # (timestamp, tokens) deques
        self._minute_reqs: collections.deque = collections.deque()
        self._minute_toks: collections.deque = collections.deque()
        self._day_reqs:    collections.deque = collections.deque()

    def _evict(self):
        now = time.monotonic()
        minute_ago = now - 60
        day_ago    = now - 86_400

        while self._minute_reqs and self._minute_reqs[0] < minute_ago:
            self._minute_reqs.popleft()
        while self._minute_toks and self._minute_toks[0][0] < minute_ago:
            self._minute_toks.popleft()
        while self._day_reqs and self._day_reqs[0] < day_ago:
            self._day_reqs.popleft()

    def can_request(self, estimated_tokens: int = 600) -> bool:
        """Return True if the request is safe to send."""
        self._evict()
        rpm = len(self._minute_reqs)
        tpm = sum(t for _, t in self._minute_toks)
        rpd = len(self._day_reqs)

        if rpm  >= self.RPM_LIMIT * self.SAFETY:
            logger.warning(f"Groq RPM limit near ({rpm}/{self.RPM_LIMIT}), skipping")
            return False
        if tpm + estimated_tokens >= self.TPM_LIMIT * self.SAFETY:
            logger.warning(f"Groq TPM limit near ({tpm}/{self.TPM_LIMIT}), skipping")
            return False
        if rpd  >= self.RPD_LIMIT * self.SAFETY:
            logger.warning(f"Groq RPD limit near ({rpd}/{self.RPD_LIMIT}), skipping")
            return False
        return True

    def record(self, tokens_used: int):
        """Record a completed request."""
        now = time.monotonic()
        self._minute_reqs.append(now)
        self._minute_toks.append((now, tokens_used))
        self._day_reqs.append(now)
        self._evict()
        logger.debug(
            f"Groq usage — RPM: {len(self._minute_reqs)}/{self.RPM_LIMIT}, "
            f"TPM: {sum(t for _,t in self._minute_toks)}/{self.TPM_LIMIT}, "
            f"RPD: {len(self._day_reqs)}/{self.RPD_LIMIT}"
        )

_groq_limiter = GroqRateLimiter()

# ============================================================
#  Get Groq API Key
# ============================================================
async def get_groq_key() -> Optional[str]:
    
    global _mongo_client
    
    # Try to get Groq API key from database first
    if _mongo_client:
        try:
            db = _mongo_client[MONGODB_DATABASE]
            config = await db.admin_config.find_one({"_id": "ai_config"})
            if config and config.get("groq_api_key"):
                logger.info("Using Groq API key from database")
                return config["groq_api_key"]
        except Exception as e:
            logger.warning(f"Failed to fetch Groq API key from database: {e}")
            
    # Fallback to environment variable
    if GROQ_API_KEY:
        logger.info("Using Groq API key from environment variable")
        return GROQ_API_KEY
    return None
    

# ============================================================
#  Groq API (LPU — fast free tier)
# ============================================================

async def get_groq_response(message: str) -> Optional[str]:
    """Get response from Groq Cloud API (OpenAI-compatible, LPU inference)."""
    active_api_key = await get_groq_key()
    
    if not active_api_key:
        return None

    # Estimate tokens: ~4 chars/token, system prompt ~50 tokens
    estimated_tokens = len(message) // 4 + 50 + 512  # input + max output
    if not _groq_limiter.can_request(estimated_tokens):
        logger.warning("Groq rate limit guard triggered, falling back to next provider")
        return None
    
    try:
        import httpx
        
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {active_api_key}",
        }
        payload = {
            "model": GROQ_MODEL,
            "messages": [
                {
                    "role": "system",
                    "content": "You are LexiLingo, a friendly AI English tutor. Help users learn English clearly and concisely."
                },
                {
                    "role": "user",
                    "content": message,
                }
            ],
            "max_tokens": 512,
            "temperature": 0.7,
        }
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(url, json=payload, headers=headers)
            if response.status_code == 200:
                data = response.json()
                choices = data.get("choices", [])
                if choices:
                    content = choices[0].get("message", {}).get("content", "")
                    # Record actual token usage from response
                    usage = data.get("usage", {})
                    tokens_used = usage.get("total_tokens", estimated_tokens)
                    _groq_limiter.record(tokens_used)
                    return content
            elif response.status_code == 429:
                logger.warning(f"Groq 429 rate limited: {response.text[:200]}")
                return None
            else:
                logger.error(f"Groq API error: {response.status_code} - {response.text}")
                return None
                
    except Exception as e:
        logger.error(f"Groq API error: {e}")
        return None

# ============================================================
# Ollama Local Response Helper
# ============================================================

async def get_ollama_response(message: str) -> Optional[str]:
    """Get response from local Ollama model (qwen3:4b)."""
    try:
        from api.services.ollama_service import OllamaService
        
        logger.info(f"  → Trying Ollama local ({OLLAMA_MODEL})...")
        
        ollama = OllamaService(
            base_url=OLLAMA_BASE_URL,
            model=OLLAMA_MODEL,
            timeout=float(OLLAMA_TIMEOUT),
        )
        
        # Check health first
        is_healthy = await ollama.health_check()
        if not is_healthy:
            logger.warning("  → Ollama server not running")
            await ollama.close()
            return None
        
        result = await ollama.chat(
            messages=[
                {
                    "role": "system",
                    "content": "You are LexiLingo, an AI English tutor helping ESL learners. "
                               "Respond helpfully and encourage the user to practice English. "
                               "Keep responses concise and friendly. /no_think"
                },
                {"role": "user", "content": message},
            ],
            temperature=0.7,
            max_tokens=OLLAMA_MAX_TOKENS,
            num_ctx=OLLAMA_CONTEXT_LENGTH,
            num_thread=OLLAMA_NUM_THREADS,
        )
        
        await ollama.close()
        
        # Strip <think>...</think> tags from Qwen3 thinking output
        content = None
        if isinstance(result, dict):
            content = result.get("message", {}).get("content") or result.get("response")
        elif isinstance(result, str):
            content = result
        
        if content:
            # Remove thinking tags and their content (full blocks and stray closing tags)
            import re
            content = re.sub(r'<think>.*?</think>\s*', '', content, flags=re.DOTALL)
            content = re.sub(r'</think>\s*', '', content).strip()
            if content:
                logger.info(f"  → Ollama response OK (length: {len(content)} chars)")
                return content
        
        return None
        
    except Exception as e:
        logger.warning(f"  → Ollama error: {e}")
        return None


# ============================================================
# AI Response Helper (via ModelGateway - legacy)
# ============================================================

async def get_ai_response(message: str) -> Optional[str]:
    """Get response from AI model via ModelGateway (legacy)."""
    global _gateway_initialized
    
    if not _gateway_initialized:
        return None
    
    try:
        from api.services.gateway_setup import execute_task
        
        result = await execute_task(
            task_type="chat",
            params={
                "text": message,
                "system_prompt": """You are LexiLingo, an AI English tutor helping ESL learners.
Respond helpfully and encourage the user to practice English.
Keep responses concise and friendly.""",
            },
            fallback=True,
        )
        
        if result.get("success"):
            data = result.get("data", {})
            response = data.get("response") or str(data)
            return response
        
        return None
        
    except Exception as e:
        logger.warning(f"  → Gateway error: {e}")
        return None


async def get_qwen_response_legacy(message: str) -> Optional[str]:
    """Legacy: Get response from Qwen model (direct loading)."""
    global qwen_engine
    
    if not USE_QWEN:
        return None
    
    try:
        # Lazy load Qwen engine
        if qwen_engine is None:
            logger.info(f"Loading Qwen model: {QWEN_MODEL}...")
            from api.services.qwen_engine import QwenEngine
            
            qwen_engine = QwenEngine(
                model_name=QWEN_MODEL,
                device="cpu",  # Use CPU for macOS compatibility
                load_in_8bit=False,
            )
            await qwen_engine.initialize()
            logger.info("✅ Qwen model loaded successfully")
        
        # Build prompt for dialogue task
        prompt = f"""You are LexiLingo, an AI English tutor helping ESL learners.
Respond helpfully and encourage the user to practice English.

User: {message}
Assistant:"""
        
        # Generate response using Qwen
        result = await qwen_engine.generate(
            prompt=prompt,
            max_new_tokens=256,
            temperature=0.7,
        )
        
        # Extract response text
        if isinstance(result, dict):
            return result.get("response") or result.get("text") or result.get("raw_output")
        return str(result)
        
    except Exception as e:
        logger.warning(f"Qwen error: {e}, falling back to Gemini")
        return None


# ============================================================
# Health Endpoints
# ============================================================

@app.get("/health")
async def health_check():
    """Health check with gateway status."""
    gateway_status = None
    
    if _gateway_initialized:
        try:
            from api.services.model_gateway import get_gateway
            gateway = await get_gateway()
            gateway_status = gateway.get_status()  # Sync method, not async
        except Exception as e:
            gateway_status = {"error": str(e)}
    
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "2.0.0",
        "gateway_enabled": USE_GATEWAY,
        "gateway_initialized": _gateway_initialized,
        "gateway_status": gateway_status,
        "gemini_configured": bool(GEMINI_API_KEY),
    }

@app.get("/ping")
async def ping():
    return {"pong": True}

@app.get("/")
async def root():
    return {"message": "LexiLingo AI Service with ModelGateway"}


# ============================================================
# Chat Endpoints
# ============================================================

@app.post("/api/v1/chat/sessions", response_model=CreateSessionResponse)
async def create_session(request: CreateSessionRequest) -> CreateSessionResponse:
    """Create a new chat session."""
    session_id = str(uuid.uuid4())
    created_at = datetime.utcnow()
    
    session = SessionData(
        session_id=session_id,
        user_id=request.user_id,
        title=request.title or "New Conversation",
        created_at=created_at.isoformat(),
        last_activity=created_at.isoformat(),
    )
    sessions[session_id] = session.model_dump()
    
    return CreateSessionResponse(success=True, data=session)


@app.post("/api/v1/chat/messages", response_model=SendMessageResponse)
async def send_message(request: SendMessageRequest) -> SendMessageResponse:
    """Send a message and get AI response.
    
    Fallback chain:
      1. Groq API (llama-3.3-70b, LPU fast free tier)
      2. Gemini API (gemini-2.0-flash)
      3. Ollama local (lexilingo-qwen3-1.7b)
      4. Static fallback message
    """
    session_id = request.session_id
    ai_response = None
    model_used = None
    
    logger.info(f"📨 Chat request received - session: {session_id[:8]}..., message: '{request.message[:50]}...'")
    
    # ── Step 1: Groq API (fast LPU, free tier) ──
    logger.info(f"🔄 [1/3] Trying Groq ({GROQ_MODEL})...")
    ai_response = await get_groq_response(request.message)
    if ai_response:
        model_used = f"groq/{GROQ_MODEL}"
        logger.info(f"✅ Groq response received (length: {len(ai_response)} chars)")
    
    # ── Step 2: Gemini API (cloud fallback) ──
    if ai_response is None:
        active_api_key = await get_active_gemini_key()
        if active_api_key:
            logger.info("🔄 [2/3] Groq failed, trying Gemini API...")
            try:
                import httpx
                
                url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={active_api_key}"
                
                payload = {
                    "contents": [{
                        "parts": [{
                            "text": f"You are LexiLingo, an AI English tutor. Help the user learn English. User message: {request.message}"
                        }]
                    }]
                }
                
                async with httpx.AsyncClient(timeout=30.0) as client:
                    response = await client.post(url, json=payload)
                    
                    if response.status_code == 200:
                        data = response.json()
                        candidates = data.get("candidates", [])
                        if candidates:
                            content = candidates[0].get("content", {})
                            parts = content.get("parts", [])
                            if parts:
                                ai_response = parts[0].get("text", "")
                    else:
                        logger.error(f"❌ Gemini API error: {response.status_code} - {response.text}")
                
                if ai_response:
                    model_used = "gemini-2.0-flash"
                    logger.info(f"✅ Gemini response received (length: {len(ai_response)} chars)")
                        
            except Exception as e:
                logger.error(f"❌ Gemini error: {e}")
    
    # ── Step 3: Ollama local (offline fallback) ──
    if ai_response is None:
        logger.info("🔄 [3/3] Cloud APIs failed, trying Ollama local...")
        ai_response = await get_ollama_response(request.message)
        if ai_response:
            model_used = f"ollama/{OLLAMA_MODEL}"
            logger.info(f"✅ Ollama response received (length: {len(ai_response)} chars)")
    
    # ── Step 4: Static fallback ──
    if ai_response is None:
        ai_response = "Hello! I'm LexiLingo AI. All AI providers are currently unavailable. Please check your configuration."
        model_used = "fallback"
        logger.warning("⚠️ All AI providers failed, using static fallback")
    
    logger.info(f"🤖 Model used: {model_used}")
    
    # Store messages
    if session_id not in messages:
        messages[session_id] = []
    
    message_id = str(uuid.uuid4())
    timestamp = datetime.utcnow()
    
    # User message
    messages[session_id].append({
        "id": str(uuid.uuid4()),
        "session_id": session_id,
        "content": request.message,
        "role": "user",
        "timestamp": timestamp.isoformat(),
    })
    
    # AI message
    messages[session_id].append({
        "id": message_id,
        "session_id": session_id,
        "content": ai_response,
        "role": "ai",
        "timestamp": datetime.utcnow().isoformat(),
    })
    
    message_data = MessageData(
        message_id=message_id,
        session_id=session_id,
        user_message=request.message,
        ai_response=ai_response,
        model_used=model_used,
        created_at=timestamp.isoformat(),
    )
    
    return SendMessageResponse(success=True, data=message_data)


@app.get("/api/v1/chat/sessions/{session_id}/messages")
async def get_messages(session_id: str):
    """Get all messages in a session."""
    return {
        "success": True,
        "data": messages.get(session_id, []),
    }


@app.get("/api/v1/chat/sessions/user/{user_id}")
async def get_user_sessions(user_id: str):
    """Get all sessions for a user."""
    user_sessions = [s for s in sessions.values() if s.get("user_id") == user_id]
    return {
        "success": True,
        "data": user_sessions,
    }


# ============================================================
# STT Endpoints  
# ============================================================

@app.post("/api/v1/stt/transcribe")
async def transcribe_audio(
    audio: UploadFile = File(...),
    language: Optional[str] = "en",
):
    """
    Transcribe audio to text.
    
    For web clients, recommend using Web Speech API directly for real-time STT.
    This endpoint is for file-based transcription.
    """
    import tempfile
    
    try:
        # Save uploaded file
        with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{audio.filename}") as tmp:
            content = await audio.read()
            tmp.write(content)
            tmp_path = tmp.name
        
        try:
            # Try faster-whisper first
            from faster_whisper import WhisperModel
            
            # Use base model for speed, can change to large-v3 for accuracy
            model = WhisperModel("base", device="cpu", compute_type="int8")
            segments, info = model.transcribe(tmp_path, language=language)
            
            text = " ".join([segment.text for segment in segments])
            
            return {
                "success": True,
                "text": text.strip(),
                "language": info.language,
                "model": "whisper-base",
            }
            
        except ImportError:
            logger.warning("faster-whisper not available")
            # Return guidance to use Web Speech API
            return {
                "success": True,
                "text": "",
                "fallback": True,
                "message": "Server STT unavailable. Use Web Speech API on client for real-time transcription.",
                "web_speech_api": {
                    "supported": True,
                    "code_example": """
// JavaScript Web Speech API
const recognition = new (window.SpeechRecognition || window.webkitSpeechRecognition)();
recognition.lang = 'en-US';
recognition.continuous = true;
recognition.onresult = (event) => {
    const transcript = event.results[event.results.length - 1][0].transcript;
    console.log(transcript);
};
recognition.start();
""",
                }
            }
        finally:
            try:
                os.unlink(tmp_path)
            except:
                pass
                
    except Exception as e:
        logger.error(f"STT error: {e}")
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": str(e),
            }
        )


# Endpoint for checking STT/TTS capabilities
@app.get("/api/v1/voice/capabilities")
async def get_voice_capabilities():
    """Check available voice capabilities on this server."""
    
    stt_available = False
    tts_available = False
    
    try:
        from faster_whisper import WhisperModel
        stt_available = True
    except ImportError:
        pass
    
    try:
        from gtts import gTTS
        tts_available = True
    except ImportError:
        pass
    
    return {
        "success": True,
        "capabilities": {
            "stt": {
                "available": stt_available,
                "engine": "whisper" if stt_available else "web_speech_api",
                "languages": ["en", "vi", "fr", "de", "es", "ja", "ko", "zh"] if stt_available else ["browser_default"],
            },
            "tts": {
                "available": tts_available,
                "engine": "gtts" if tts_available else "web_speech_api",
                "languages": ["en", "vi", "fr", "de", "es", "ja", "ko", "zh"],
                "format": "audio/mpeg",
            },
            "web_speech_api": {
                "recommended_for_realtime": True,
                "note": "Use browser's Web Speech API for real-time voice input/output",
            }
        }
    }


# ============================================================
# TTS Endpoints
# ============================================================

@app.post("/api/v1/tts/synthesize")
async def synthesize_speech(text: str = Body(..., embed=True)):
    """Synthesize speech from text using gTTS (Google Text-to-Speech)."""
    try:
        from gtts import gTTS
        import io
        
        # Generate speech using Google TTS
        tts = gTTS(text=text, lang='en', slow=False)
        
        # Save to BytesIO
        audio_io = io.BytesIO()
        tts.write_to_fp(audio_io)
        audio_io.seek(0)
        
        logger.info(f"TTS generated for: {text[:50]}...")
        
        return Response(
            content=audio_io.getvalue(),
            media_type="audio/mpeg",
            headers={
                "Content-Disposition": f"attachment; filename=speech.mp3"
            }
        )
        
    except ImportError:
        # Fallback: return JSON indicating to use Web Speech Synthesis
        return JSONResponse(
            content={
                "success": True,
                "text": text,
                "fallback": True,
                "message": "Server TTS unavailable. Use Web Speech API on client.",
                "web_speech_api": {
                    "supported": True,
                    "instruction": "Use browser's SpeechSynthesis API with text",
                }
            }
        )
    except Exception as e:
        logger.error(f"TTS error: {e}")
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": str(e),
            }
        )


# ============================================================
# AI Analysis Endpoints (Placeholder)
# ============================================================

@app.post("/api/v1/ai/analyze")
async def analyze_text(text: str = Body(..., embed=True)):
    """Placeholder for AI text analysis."""
    return {
        "success": True,
        "data": {
            "text": text,
            "fluency": 0.0,
            "grammar_score": 0.0,
            "vocabulary_level": "intermediate",
            "suggestions": [],
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
