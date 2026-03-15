"""
LexiLingo AI Service

Main entry point for the AI Service. 
Initializes resources and includes modular routers.
"""

from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging
import os
import httpx
from datetime import datetime
from typing import Optional
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

# Core imports
from api.core.database import mongodb_manager, get_database
from api.core.redis_client import RedisClient, get_redis
from api.core.rate_limiter import RedisRateLimiter

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load .env file
from dotenv import load_dotenv
load_dotenv()


# Environment Configuration
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
USE_GATEWAY = os.getenv("USE_GATEWAY", "true").lower() == "true"
MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "")
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "lexilingo-qwen3-1.7b")

# Global clients
_gateway_initialized = False
_http_client: Optional[httpx.AsyncClient] = None
_groq_limiter: Optional[RedisRateLimiter] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    global _gateway_initialized, _http_client, _groq_limiter
    
    # Startup
    try:
        await mongodb_manager.connect()
        logger.info("✓ MongoDB connected")
    except Exception as e:
        logger.warning(f"MongoDB connection failed: {e}")
    
    try:
        redis_conn = await get_redis()
        _groq_limiter = RedisRateLimiter(
            redis_client=redis_conn,
            prefix="groq",
            rpm_limit=30,
            tpm_limit=12000,
            rpd_limit=14400
        )
        logger.info("✓ Redis & Rate Limiter initialized")
    except Exception as e:
        logger.warning(f"Redis initialization failed: {e}")

    _http_client = httpx.AsyncClient(timeout=30.0)
    
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
            logger.warning(f"Failed to initialize gateway: {e}")
    
    yield
    
    # Shutdown
    if _http_client:
        await _http_client.aclose()
    await mongodb_manager.disconnect()
    await RedisClient.close()
    if _gateway_initialized:
        from api.services.gateway_setup import shutdown_gateway
        await shutdown_gateway()


# FastAPI App
app = FastAPI(
    title="LexiLingo AI Service",
    description="AI Service for Chat, STT, TTS with ModelGateway",
    version="2.1.0",
    lifespan=lifespan,
)

# Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
        "http://localhost:5173",
        "https://lexilingo.vercel.app",
        "https://flutter-app-nine-pied.vercel.app",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Admin-Key"],
    allow_private_network=True,
)


# Helper Functions for Providers (re-exported for routers)
async def get_groq_response(message: str, db: AsyncIOMotorDatabase) -> Optional[str]:
    global _http_client, _groq_limiter
    if not GROQ_API_KEY or not _http_client or not _groq_limiter:
        return None
    if not await _groq_limiter.can_request():
        return None
    try:
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = {"Authorization": f"Bearer {GROQ_API_KEY}"}
        payload = {
            "model": GROQ_MODEL,
            "messages": [{"role": "user", "content": message}],
            "max_tokens": 512,
        }
        response = await _http_client.post(url, json=payload, headers=headers)
        if response.status_code == 200:
            data = response.json()
            content = data["choices"][0]["message"]["content"]
            await _groq_limiter.record(data.get("usage", {}).get("total_tokens", 500))
            return content
    except Exception as e:
        logger.error(f"Groq error: {e}")
    return None

async def get_gemini_response(message: str, db: AsyncIOMotorDatabase) -> Optional[str]:
    if not GEMINI_API_KEY or not _http_client:
        return None
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={GEMINI_API_KEY}"
        payload = {"contents": [{"parts": [{"text": message}]}]}
        response = await _http_client.post(url, json=payload)
        if response.status_code == 200:
            return response.json()["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        logger.error(f"Gemini error: {e}")
    return None

async def get_ollama_response(message: str) -> Optional[str]:
    try:
        from api.services.ollama_service import OllamaService
        async with OllamaService(base_url=OLLAMA_BASE_URL, model=OLLAMA_MODEL) as ollama:
            result = await ollama.chat(messages=[{"role": "user", "content": message}])
            return result.get("message", {}).get("content") if isinstance(result, dict) else result
    except Exception:
        return None


# Include Routers
from api.routes import chat, stt, tts, admin, ai, lexi_chat, topic_chat

app.include_router(chat.router, prefix="/api/v1/chat", tags=["Chat"])
app.include_router(stt.router, prefix="/api/v1/stt", tags=["STT"])
app.include_router(tts.router, prefix="/api/v1/tts", tags=["TTS"])
app.include_router(topic_chat.router, prefix="/api/v1/topics", tags=["Topic Chat"])
app.include_router(admin.router, prefix="/api/v1/admin", tags=["Admin"])
app.include_router(ai.router, prefix="/api/v1/ai", tags=["AI Analytics"])
app.include_router(lexi_chat.router, tags=["Lexi Chat"])


@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

@app.get("/")
async def root():
    return {"message": "LexiLingo AI Service API"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
