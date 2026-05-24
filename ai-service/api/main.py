"""
LexiLingo AI Service

Main entry point for the AI Service. 
Initializes resources and includes modular routers.
"""

from fastapi import FastAPI, HTTPException, Request, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse
from contextlib import asynccontextmanager
import logging
import os
import httpx
from datetime import datetime
from typing import Optional
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from pymongo import ASCENDING, DESCENDING
from pymongo.errors import OperationFailure

# Core imports
from api.core.database import mongodb_manager, get_database
from api.core.redis_client import RedisClient, get_redis
from api.core.rate_limiter import RedisRateLimiter
from api.core.config import get_settings

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load .env file
from dotenv import load_dotenv
load_dotenv()

# Settings (loaded after dotenv so env vars are available)
settings = get_settings()

# Load .env file
from dotenv import load_dotenv
load_dotenv()


# Environment Configuration
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
USE_GATEWAY = os.getenv("USE_GATEWAY", "true").lower() == "true"
MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "")
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "qwen/qwen3-32b")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "lexilingo-qwen3-1.7b")

# Global clients
_gateway_initialized = False
_http_client: Optional[httpx.AsyncClient] = None
_groq_limiter: Optional[RedisRateLimiter] = None


async def _ensure_mongo_indexes() -> None:
    """Create indexes for fast session/message lookup without risking migrated data loss."""
    db = mongodb_manager.db

    async def _create_index_safe(collection: str, keys, **kwargs) -> None:
        try:
            await db[collection].create_index(keys, **kwargs)
        except Exception as exc:
            logger.warning(
                "Skip index %s on %s due to error: %s",
                kwargs.get("name", "<unnamed>"),
                collection,
                exc,
            )

    async def _has_duplicate_string_values(collection: str, field: str, include_empty: bool = True) -> bool:
        match_filter = {field: {"$exists": True, "$type": "string"}}
        if not include_empty:
            match_filter = {field: {"$exists": True, "$type": "string", "$ne": ""}}

        pipeline = [
            {"$match": match_filter},
            {"$group": {"_id": f"${field}", "count": {"$sum": 1}}},
            {"$match": {"count": {"$gt": 1}}},
            {"$limit": 1},
        ]
        docs = await db[collection].aggregate(pipeline).to_list(length=1)
        return bool(docs)

    async def _ensure_session_unique_index(collection: str, field: str, name: str) -> None:
        # Keep query performance regardless of uniqueness enforceability.
        await _create_index_safe(
            collection,
            [(field, ASCENDING)],
            name=f"{collection}_{field}_idx",
        )

        # We keep the unique index scoped to string values. Since some Mongo-compatible
        # providers reject $ne inside partialFilterExpression, include empty strings in
        # duplicate checks and avoid using $ne in the index expression itself.
        if await _has_duplicate_string_values(collection, field, include_empty=True):
            logger.info(
                "Skip unique index %s on %s: duplicate string %s values detected in migrated data",
                name,
                collection,
                field,
            )
            return

        try:
            await db[collection].create_index(
                [(field, ASCENDING)],
                unique=True,
                name=name,
                partialFilterExpression={
                    field: {"$exists": True, "$type": "string"}
                },
            )
        except OperationFailure as exc:
            # Do not block startup when existing migrated data/index options conflict.
            logger.info("Skip unique index %s on %s: %s", name, collection, exc)

    await _ensure_session_unique_index(
        collection="chat_sessions",
        field="session_id",
        name="chat_sessions_session_id_uq",
    )
    await _create_index_safe(
        "chat_sessions",
        [("user_id", ASCENDING), ("last_activity", DESCENDING)],
        name="chat_sessions_user_last_activity_idx",
    )
    await _create_index_safe(
        "chat_messages",
        [("session_id", ASCENDING), ("timestamp", ASCENDING)],
        name="chat_messages_session_timestamp_idx",
    )

    await _ensure_session_unique_index(
        collection="lexi_sessions",
        field="session_id",
        name="lexi_sessions_session_id_uq",
    )
    await _create_index_safe(
        "lexi_sessions",
        [("user_id", ASCENDING), ("updated_at", DESCENDING)],
        name="lexi_sessions_user_updated_at_idx",
    )
    await _create_index_safe(
        "lexi_messages",
        [("session_id", ASCENDING), ("timestamp", ASCENDING)],
        name="lexi_messages_session_timestamp_idx",
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    global _gateway_initialized, _http_client, _groq_limiter
    
    # Startup
    try:
        await mongodb_manager.connect()
        await _ensure_mongo_indexes()
        logger.info(" MongoDB connected")
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
        logger.info(" Redis & Rate Limiter initialized")
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
            logger.info(" ModelGateway initialized")
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
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_origin_regex=settings.CORS_ALLOW_ORIGIN_REGEX or None,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Admin-Key", "X-Request-Id", "X-Api-Key"],
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
from api.routes import chat, stt, tts, admin, ai, lexi_chat, topic_chat, ollama_router

app.include_router(chat.router, prefix="/api/v1/chat", tags=["Chat"])
app.include_router(stt.router, prefix="/api/v1/stt", tags=["STT"])
app.include_router(tts.router, prefix="/api/v1/tts", tags=["TTS"])
app.include_router(topic_chat.router, prefix="/api/v1/topics", tags=["Topic Chat"])
app.include_router(admin.router, prefix="/api/v1/admin", tags=["Admin"])
app.include_router(ai.router, prefix="/api/v1/ai", tags=["AI Analytics"])
app.include_router(lexi_chat.router, tags=["Lexi Chat"])
app.include_router(ollama_router.router, prefix="/api/v1", tags=["Ollama"])

# Static files (dev tools / visualizers)
_static_dir = os.path.join(os.path.dirname(__file__), "..", "static")
if os.path.isdir(_static_dir):
    app.mount("/static", StaticFiles(directory=_static_dir), name="static")


@app.get("/visualizer", include_in_schema=False)
async def visualizer_redirect():
    """Redirect to the TraceCAG Node Visualizer HTML tool."""
    return RedirectResponse(url="/static/trace-cag-node-viz.html")


@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}


async def _run_model_warmup() -> None:
    """Best-effort warmup for AI models; errors are non-fatal."""
    try:
        from api.services.model_gateway import get_model_gateway
        gateway = get_model_gateway()
        await gateway.preload_models()
        logger.info("Warmup: model preload complete")
    except Exception as exc:
        logger.warning(f"Warmup: preload error (non-fatal): {exc}")


@app.post("/warmup")
@app.get("/warmup")
@app.post("/api/v1/warmup")
@app.get("/api/v1/warmup")
async def warmup(background_tasks: BackgroundTasks):
    """
    Trigger background model warmup.

    Supports legacy and versioned paths/methods for compatibility.
    """
    background_tasks.add_task(_run_model_warmup)
    return {"status": "warming_up", "message": "Model preload started in background"}

@app.get("/")
async def root():
    return {"message": "LexiLingo AI Service API"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
