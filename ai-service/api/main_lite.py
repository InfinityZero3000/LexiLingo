"""
LexiLingo AI Service - Lite Version

Simplified API for Chat, STT, TTS.
Supports Qwen (local) or Gemini (cloud) for chat.
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, JSONResponse
import logging
import os
import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
USE_QWEN = os.getenv("USE_QWEN", "true").lower() == "true"
QWEN_MODEL = os.getenv("QWEN_MODEL_NAME", "Qwen/Qwen3-1.7B")

# Global Qwen engine (lazy loaded)
qwen_engine = None

# FastAPI App
app = FastAPI(
    title="LexiLingo AI Service (Lite)",
    description="Simplified AI Service for Chat, STT, TTS",
    version="1.0.0-lite",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:8000",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================
# Models
# ============================================================

class CreateSessionRequest(BaseModel):
    user_id: str
    title: Optional[str] = None

class SendMessageRequest(BaseModel):
    user_id: str
    session_id: str
    message: str


# ============================================================
# In-memory storage (for development)
# ============================================================
sessions = {}
messages = {}


# ============================================================
# Qwen Engine Helper
# ============================================================

async def get_qwen_response(message: str) -> Optional[str]:
    """Get response from Qwen model."""
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
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0-lite",
        "qwen_enabled": USE_QWEN,
        "qwen_model": QWEN_MODEL if USE_QWEN else None,
        "qwen_loaded": qwen_engine is not None and qwen_engine.is_loaded if qwen_engine else False,
        "gemini_configured": bool(GEMINI_API_KEY),
    }

@app.get("/ping")
async def ping():
    return {"pong": True}

@app.get("/")
async def root():
    return {"message": "LexiLingo AI Service (Lite)"}


# ============================================================
# Chat Endpoints
# ============================================================

@app.post("/api/v1/chat/sessions")
async def create_session(request: CreateSessionRequest):
    session_id = str(uuid.uuid4())
    created_at = datetime.utcnow()
    
    session = {
        "session_id": session_id,
        "user_id": request.user_id,
        "title": request.title or "New Conversation",
        "created_at": created_at.isoformat(),
        "last_activity": created_at.isoformat(),
    }
    sessions[session_id] = session
    
    return {
        "success": True,
        "data": session,
    }

@app.post("/api/v1/chat/messages")
async def send_message(request: SendMessageRequest):
    session_id = request.session_id
    ai_response = None
    model_used = None
    
    # 1. Try Qwen first (local model)
    if USE_QWEN:
        ai_response = await get_qwen_response(request.message)
        if ai_response:
            model_used = "qwen"
            logger.info("Using Qwen for response")
    
    # 2. Fallback to Gemini API
    if ai_response is None and GEMINI_API_KEY:
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
                    logger.error(f"Gemini API error: {response.status_code} - {response.text}")
                    ai_response = f"API error: {response.status_code}"
            
            if ai_response:
                model_used = "gemini"
                logger.info("Using Gemini for response")
                    
        except Exception as e:
            logger.error(f"Gemini error: {e}")
            ai_response = f"I apologize, but I'm having trouble processing your request. Error: {str(e)}"
    
    # 3. Final fallback if no model available
    if ai_response is None:
        ai_response = "Hello! I'm LexiLingo AI. No AI model is available. Please configure Qwen or Gemini API."
        model_used = "fallback"
    
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
    
    return {
        "success": True,
        "data": {
            "message_id": message_id,
            "ai_response": ai_response,
            "model_used": model_used,
            "processing_time_ms": 100,
        }
    }

@app.get("/api/v1/chat/sessions/{session_id}/messages")
async def get_messages(session_id: str):
    return {
        "success": True,
        "data": messages.get(session_id, []),
    }

@app.get("/api/v1/chat/sessions/user/{user_id}")
async def get_user_sessions(user_id: str):
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
