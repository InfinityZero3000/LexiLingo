"""
LexiLingo AI Service

Main entry point for the AI Service. 
Initializes resources and includes modular routers.
"""

import sentry_sdk
import asyncio
from sentry_sdk.integrations.fastapi import FastApiIntegration
from fastapi import FastAPI, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse, RedirectResponse
from contextlib import asynccontextmanager
import logging
import os
import httpx
from dotenv import load_dotenv
from datetime import datetime, timezone
from typing import Optional
from pymongo import ASCENDING, DESCENDING
from pymongo.errors import OperationFailure

# Core imports
from api.core.database import mongodb_manager
from api.core.redis_client import RedisClient, get_redis
from api.core.groq_key_pool import build_groq_key_pool, GroqKeyPool
from api.core.config import get_settings

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

# Settings (loaded after dotenv so env vars are available)
settings = get_settings()

# Sentry — only active when DSN is configured
if settings.SENTRY_DSN:
    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        environment=settings.ENVIRONMENT,
        integrations=[FastApiIntegration()],
        traces_sample_rate=0.2,
        send_default_pii=False,
    )
    logger.info("Sentry error tracking enabled")

# Environment Configuration
GEMINI_API_KEY = settings.GEMINI_API_KEY
USE_GATEWAY = os.getenv("USE_GATEWAY", "true").lower() == "true"
MONGODB_URI = settings.MONGODB_URI
MONGODB_DATABASE = settings.MONGODB_DATABASE

# Global clients
_gateway_initialized = False
_http_client: Optional[httpx.AsyncClient] = None
_groq_pool: Optional[GroqKeyPool] = None


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
    await _create_index_safe(
        "lexi_messages",
        [("session_id", ASCENDING), ("id", ASCENDING)],
        name="lexi_messages_session_id_uq",
        unique=True,
        partialFilterExpression={"id": {"$exists": True, "$type": "string"}},
    )
    await _create_index_safe(
        "learner_observation_spool",
        [("event_id", ASCENDING)],
        name="learner_observation_spool_event_id_uq",
        unique=True,
    )
    await _create_index_safe(
        "learner_observation_spool",
        [("status", ASCENDING), ("available_at", ASCENDING)],
        name="learner_observation_spool_claim_idx",
    )
    # TTL applies only after delivery. Pending/retry rows have no delivered_at
    # and therefore never expire.
    await _create_index_safe(
        "learner_observation_spool",
        [("delivered_at", ASCENDING)],
        name="learner_observation_spool_delivered_ttl",
        expireAfterSeconds=90 * 24 * 60 * 60,
    )
    await _create_index_safe(
        "ai_interactions",
        [("indexed_at", ASCENDING)],
        name="ai_interactions_indexed_at_ttl",
        expireAfterSeconds=90 * 24 * 60 * 60,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    global _gateway_initialized, _http_client, _groq_pool

    # Startup
    try:
        await mongodb_manager.connect()
        await _ensure_mongo_indexes()
        logger.info(" MongoDB connected")
    except Exception as e:
        logger.error(f"MongoDB connection failed (critical): {e}")
        raise

    try:
        redis_conn = await get_redis()
        _groq_pool = build_groq_key_pool(redis_conn)
        if _groq_pool:
            logger.info(" Groq key pool initialized with %d key(s)", _groq_pool.count)
        else:
            logger.warning("No Groq API keys configured")
        logger.info(" Redis & Rate Limiter initialized")
    except Exception as e:
        _groq_pool = None
        if os.getenv("GROQ_REQUIRE_SEVEN_KEYS", "false").lower() == "true":
            raise RuntimeError("Strict Groq key-pool initialization failed") from e
        logger.warning(f"Redis initialization failed; continuing without cache/rate pool: {e}")

    _http_client = httpx.AsyncClient(timeout=30.0)

    if settings.LEARNER_STATE_MODE != "off":
        from api.services.learner_observation_spool import (
            start_learner_observation_forwarder,
        )

        start_learner_observation_forwarder()

    if settings.CONTENT_ETL_ENABLED:
        from api.services.content_etl.staleness import run_staleness_loop

        asyncio.create_task(run_staleness_loop())
        logger.info(" content_etl staleness watch started")

    if USE_GATEWAY:
        try:
            from api.services.gateway_setup import setup_gateway
            await setup_gateway(
                max_memory_mb=int(os.getenv("MAX_MEMORY_MB", "8000")),
                enable_auto_unload=True,
                use_gemini_fallback=bool(GEMINI_API_KEY),
                use_ollama=get_settings().OLLAMA_ENABLED,
            )
            _gateway_initialized = True
            logger.info(" ModelGateway initialized")
        except Exception as e:
            logger.warning(f"Failed to initialize gateway: {e}")

    # Warm the TraceCAG orchestrator (KG open + LangGraph compile) and
    # preload the CRITICAL/preload=True models (Qwen) here, at deploy time.
    # Without this, both only run lazily on the first /chat/messages or
    # /health request, which used to make the first real user pay the
    # multi-second KG/model cold-start cost inside their chat request.
    try:
        from api.services.orchestrator import get_orchestrator

        await asyncio.wait_for(
            asyncio.gather(get_orchestrator(), _run_model_warmup()),
            timeout=45.0,
        )
        logger.info(" AIOrchestrator + models warmed (KG + TraceCAG pipeline + Qwen)")
    except Exception as e:
        logger.warning(
            f"Startup warmup incomplete (KG/pipeline/models); will lazy-init on first request: {e}"
        )

    try:
        from api.services.stt.runtime import start_stt_runtime

        await start_stt_runtime()
        logger.info(" Streaming STT runtime initialized")
    except Exception as e:
        logger.warning(f"Failed to initialize streaming STT runtime: {e}")

    try:
        from api.services.tts_service import get_tts_service

        await asyncio.wait_for(
            asyncio.to_thread(get_tts_service().warmup),
            timeout=20.0,
        )
        logger.info(" Piper TTS warmed")
    except Exception as e:
        logger.warning(f"Piper TTS warmup failed; continuing without warm cache: {e}")

    if settings.VOICE_DUPLEX_ENABLED:
        from api.routes.voice import voice_readiness

        await voice_readiness()
        logger.info(" Duplex voice dependencies ready")
    
    yield
    
    # Shutdown
    if _http_client:
        await _http_client.aclose()
    try:
        from api.services.learner_observation_spool import (
            stop_learner_observation_forwarder,
        )

        await stop_learner_observation_forwarder()
    except Exception as e:
        logger.warning(f"Failed to stop learner observation forwarder cleanly: {e}")
    await mongodb_manager.disconnect()
    await RedisClient.close()
    try:
        from api.clients.learner_state_client import close_learner_state_client

        await close_learner_state_client()
    except Exception as e:
        logger.warning(f"Failed to close learner-state client cleanly: {e}")
    if _gateway_initialized:
        from api.services.gateway_setup import shutdown_gateway
        await shutdown_gateway()
    try:
        from api.services.stt.runtime import stop_stt_runtime

        await stop_stt_runtime()
    except Exception as e:
        logger.warning(f"Failed to stop streaming STT runtime cleanly: {e}")


# FastAPI App
app = FastAPI(
    title="LexiLingo AI Service",
    description="AI Service for Chat, STT, TTS with ModelGateway",
    version="2.1.0",
    docs_url=None if settings.ENVIRONMENT == "production" else "/docs",
    redoc_url=None if settings.ENVIRONMENT == "production" else "/redoc",
    openapi_url=None if settings.ENVIRONMENT == "production" else "/openapi.json",
    lifespan=lifespan,
)

# Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_origin_regex=settings.CORS_ALLOW_ORIGIN_REGEX or None,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "X-Admin-Key",
        "X-Request-Id",
        "X-Api-Key",
        "X-Idempotency-Key",
    ],
    allow_private_network=settings.CORS_ALLOW_PRIVATE_NETWORK,
)


# Include Routers
from api.routes import (  # noqa: E402
    admin,
    ai,
    chat,
    content_agent,
    error_diagnosis,
    ielts_grading,
    integration_trace_cag,
    lexi_chat,
    notification_agent as notification_agent_router,
    ollama_router,
    pronunciation,
    ranking_agent as ranking_agent_router,
    stt,
    topic_chat,
    translate,
    tts,
    voice,
)

app.include_router(chat.router, prefix="/api/v1/chat", tags=["Chat"])
app.include_router(stt.router, prefix="/api/v1/stt", tags=["STT"])
app.include_router(pronunciation.router, prefix="/api/v1/stt", tags=["STT"])
app.include_router(tts.router, prefix="/api/v1/tts", tags=["TTS"])
app.include_router(voice.router, prefix="/api/v1/voice", tags=["Voice"])
app.include_router(topic_chat.router, prefix="/api/v1/topics", tags=["Topic Chat"])
app.include_router(admin.router, prefix="/api/v1/admin", tags=["Admin"])
app.include_router(ai.router, prefix="/api/v1/ai", tags=["AI Analytics"])
app.include_router(translate.router, prefix="/api/v1/ai", tags=["Translate"])
app.include_router(lexi_chat.router, tags=["Lexi Chat"])
app.include_router(ollama_router.router, prefix="/api/v1", tags=["Ollama"])
app.include_router(content_agent.router, tags=["Internal Content Agent"])
app.include_router(integration_trace_cag.router)
app.include_router(notification_agent_router.router, tags=["Notification Agent"])
app.include_router(ranking_agent_router.router, tags=["Internal Ranking Agent"])
app.include_router(error_diagnosis.router, tags=["Internal Error Diagnosis"])
app.include_router(ielts_grading.router, tags=["Internal IELTS Grading"])

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
    try:
        from api.services.orchestrator import get_orchestrator

        orchestrator = await get_orchestrator()
        if not orchestrator.is_healthy():
            raise RuntimeError("AI orchestrator is not initialized")
        await orchestrator._kg.assert_runtime_namespace()
    except Exception as exc:
        logger.error("Health check failed: KG is not ready: %s", exc)
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "component": "knowledge_graph",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
        )
    return {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}


@app.get("/live")
async def liveness_check():
    """Constant-time process liveness; readiness remains available at /health."""
    return {"status": "alive"}


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
