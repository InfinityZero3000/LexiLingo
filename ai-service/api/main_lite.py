"""
LexiLingo AI Service - Lite Version

Simplified API for Chat, STT, TTS only.
Avoids heavy ML dependencies for easier development.
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
# Health Endpoints
# ============================================================

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0-lite",
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
    
    # Initialize Gemini if available
    if GEMINI_API_KEY:
        try:
            import google.generativeai as genai
            genai.configure(api_key=GEMINI_API_KEY)
            model = genai.GenerativeModel('gemini-pro')
            
            # Get AI response
            response = model.generate_content(request.message)
            ai_response = response.text
        except Exception as e:
            logger.error(f"Gemini error: {e}")
            ai_response = f"I apologize, but I'm having trouble processing your request. Error: {str(e)}"
    else:
        # Fallback response
        ai_response = "Hello! I'm LexiLingo AI. The Gemini API is not configured yet, so I can't provide intelligent responses. Please set up GEMINI_API_KEY."
    
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
    language: Optional[str] = None,
):
    """Transcribe audio to text using Whisper."""
    try:
        # Try to use faster-whisper
        from faster_whisper import WhisperModel
        import tempfile
        
        # Save uploaded file
        with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{audio.filename}") as tmp:
            content = await audio.read()
            tmp.write(content)
            tmp_path = tmp.name
        
        try:
            model = WhisperModel("base", device="cpu", compute_type="int8")
            segments, info = model.transcribe(tmp_path, language=language)
            
            text = " ".join([segment.text for segment in segments])
            
            return {
                "success": True,
                "text": text.strip(),
                "language": info.language,
            }
        finally:
            os.unlink(tmp_path)
            
    except ImportError:
        return JSONResponse(
            status_code=501,
            content={
                "success": False,
                "error": "STT not available. Install: pip install faster-whisper",
            }
        )
    except Exception as e:
        logger.error(f"STT error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# TTS Endpoints
# ============================================================

@app.post("/api/v1/tts/synthesize")
async def synthesize_speech(text: str = Body(..., embed=True)):
    """Synthesize speech from text using Piper."""
    try:
        from piper import PiperVoice
        import io
        
        # Model paths
        model_path = os.getenv(
            "TTS_MODEL_PATH",
            "./models/piper/en_US-lessac-medium.onnx"
        )
        config_path = os.getenv(
            "TTS_CONFIG_PATH", 
            "./models/piper/en_US-lessac-medium.onnx.json"
        )
        
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"TTS model not found: {model_path}")
        
        voice = PiperVoice.load(model_path, config_path=config_path)
        
        wav_io = io.BytesIO()
        voice.synthesize(text, wav_io)
        
        return Response(
            content=wav_io.getvalue(),
            media_type="audio/wav",
        )
        
    except ImportError:
        return JSONResponse(
            status_code=501,
            content={
                "success": False,
                "error": "TTS not available. Install: pip install piper-tts",
            }
        )
    except FileNotFoundError as e:
        return JSONResponse(
            status_code=404,
            content={
                "success": False,
                "error": str(e),
            }
        )
    except Exception as e:
        logger.error(f"TTS error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


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
