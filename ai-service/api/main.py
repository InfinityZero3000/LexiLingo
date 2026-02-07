"""
LexiLingo AI Service - Lite Version

Simplified API for Chat, STT, TTS with ModelGateway for lazy loading.
Supports Qwen (local) or Gemini (cloud) for chat.
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

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ============================================================
# Private Network Access Middleware (Chrome CORS-RFC1918)
# ============================================================
class PrivateNetworkAccessMiddleware(BaseHTTPMiddleware):
    """
    Middleware to handle Chrome's Private Network Access (CORS-RFC1918).
    
    When Chrome makes a cross-origin request to a private network (localhost, 
    192.168.x.x, etc.), it sends a preflight OPTIONS request with the header:
    Access-Control-Request-Private-Network: true
    
    The server must respond with:
    Access-Control-Allow-Private-Network: true
    
    Without this header, Chrome blocks all fetch() requests with:
    "Failed to fetch" error.
    """
    async def dispatch(self, request: Request, call_next):
        # For CORS preflight with PNA request
        if (
            request.method == "OPTIONS"
            and request.headers.get("access-control-request-private-network") == "true"
        ):
            response = await call_next(request)
            response.headers["Access-Control-Allow-Private-Network"] = "true"
            return response
        
        # For regular requests
        response = await call_next(request)
        return response


# Environment
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
USE_GATEWAY = os.getenv("USE_GATEWAY", "true").lower() == "true"
USE_QWEN = os.getenv("USE_QWEN", "true").lower() == "true"
QWEN_MODEL = os.getenv("QWEN_MODEL_NAME", "Qwen/Qwen3-1.7B")

# Global Qwen engine (legacy - for fallback if gateway not used)
qwen_engine = None

# Gateway instance (lazy initialized)
_gateway_initialized = False


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    global _gateway_initialized
    
    # Startup
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
    if _gateway_initialized:
        try:
            from api.services.gateway_setup import shutdown_gateway
            await shutdown_gateway()
        except Exception as e:
            logger.warning(f"Gateway shutdown error: {e}")


# FastAPI App
app = FastAPI(
    title="LexiLingo AI Service (Lite)",
    description="Simplified AI Service for Chat, STT, TTS with ModelGateway",
    version="2.0.0-lite",
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
# AI Response Helper (via ModelGateway)
# ============================================================

async def get_ai_response(message: str) -> Optional[str]:
    """Get response from AI model via ModelGateway."""
    global _gateway_initialized
    
    logger.info(f"  → get_ai_response: gateway_initialized={_gateway_initialized}")
    
    if _gateway_initialized:
        try:
            from api.services.gateway_setup import execute_task
            
            logger.info("  → Executing task via ModelGateway...")
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
            
            logger.info(f"  → Gateway result: success={result.get('success')}, model={result.get('model_used', 'unknown')}")
            
            if result.get("success"):
                data = result.get("data", {})
                response = data.get("response") or str(data)
                logger.info(f"  → Gateway response OK (length: {len(response)} chars)")
                return response
            
            logger.warning(f"  → Gateway response failed: {result.get('error')}")
            return None
            
        except Exception as e:
            logger.warning(f"  → Gateway error: {e}, falling back to legacy")
    
    # Fallback to legacy Qwen loading
    logger.info("  → Trying legacy Qwen...")
    return await get_qwen_response_legacy(message)


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
        "version": "2.0.0-lite",
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
    return {"message": "LexiLingo AI Service (Lite) with ModelGateway"}


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
    """Send a message and get AI response."""
    session_id = request.session_id
    ai_response = None
    model_used = None
    
    logger.info(f"📨 Chat request received - session: {session_id[:8]}..., message: '{request.message[:50]}...'")
    
    # 1. Try ModelGateway first (handles all routing)
    logger.info("🔄 Attempting ModelGateway...")
    ai_response = await get_ai_response(request.message)
    if ai_response:
        model_used = "gateway"
        logger.info(f"✅ ModelGateway response received (length: {len(ai_response)} chars)")
    
    # 2. Fallback to direct Gemini API
    if ai_response is None and GEMINI_API_KEY:
        logger.info("🔄 Gateway failed, trying direct Gemini API...")
        try:
            import httpx
            
            # Gemini API endpoint (use gemini-2.0-flash)
            url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={GEMINI_API_KEY}"
            
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
                    # Extract text from Gemini response
                    candidates = data.get("candidates", [])
                    if candidates:
                        content = candidates[0].get("content", {})
                        parts = content.get("parts", [])
                        if parts:
                            ai_response = parts[0].get("text", "I couldn't generate a response.")
                        else:
                            ai_response = "I couldn't generate a response."
                    else:
                        ai_response = "I couldn't generate a response."
                else:
                    logger.error(f"❌ Gemini API error: {response.status_code} - {response.text}")
                    ai_response = f"API error: {response.status_code}"
            
            if ai_response:
                model_used = "gemini-2.0-flash"
                logger.info(f"✅ Gemini response received (length: {len(ai_response)} chars)")
                    
        except Exception as e:
            logger.error(f"❌ Gemini error: {e}")
            ai_response = f"I apologize, but I'm having trouble processing your request. Error: {str(e)}"
    
    # 3. Final fallback if no model available
    if ai_response is None:
        ai_response = "Hello! I'm LexiLingo AI. No AI model is available. Please configure Qwen or Gemini API."
        model_used = "fallback"
        logger.warning("⚠️ No AI model available, using fallback response")
    
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
            "fluency": 0.8,
            "grammar_score": 0.9,
            "vocabulary_level": "intermediate",
            "suggestions": [],
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
