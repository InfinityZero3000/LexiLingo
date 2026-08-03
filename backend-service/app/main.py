"""
LexiLingo Backend App
FastAPI application for user management, courses, and progress tracking

Architecture: Clean Architecture
- Models: SQLAlchemy (PostgreSQL)
- Schemas: Pydantic validation
- Routes: API endpoints
- Services: Business logic
- Middleware: Rate limiting, error handling, request logging
"""

import logging
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.database import init_db, close_db
from app.core.redis import RedisClient
from app.core.middleware import (
    RateLimitMiddleware,
    RequestLoggingMiddleware,
    RequestIDMiddleware,
    PrivateNetworkAccessMiddleware,
    SecurityHeadersMiddleware,
)
from app.core.exceptions import (
    http_exception_handler,
    validation_exception_handler,
    unhandled_exception_handler
)
from fastapi.exceptions import RequestValidationError
from fastapi import FastAPI, Request, status, HTTPException
from app.routes import (
    health_router,
    auth_router,
    users_router,
    courses_router,
    integrations_router,
    progress_router,
    vocabulary_router,
    gamification_router,
)
from app.routes.learning import router as learning_router
from app.routes.admin_courses import router as admin_courses_router
from app.routes.admin_gamification import router as admin_gamification_router
from app.routes.admin_system import router as admin_system_router
from app.routes.content_agent import router as content_agent_router
from app.routes.notification_campaign import router as notification_campaign_router
from app.routes.ranking_agent import router as ranking_agent_router
from app.routes.devices import router as devices_router
from app.routes.challenges import router as challenges_router
from app.routes.course_categories import router as course_categories_router
from app.routes.proficiency import router as proficiency_router
from app.routes.rbac import router as rbac_router
from app.routes.analytics import router as analytics_router
from app.routes.user_management import router as user_management_router
from app.routes.youtube import router as youtube_router
from app.routes.news import router as news_router
from app.routes.podcasts import router as podcasts_router
from app.routes.games import router as games_router
from app.routes.xp import router as xp_router
from app.routes.books import router as books_router
from app.routes.ai_audit import router as ai_audit_router
from app.routes.monitoring import router as monitoring_router
from app.routes.notifications import router as notifications_router
from app.routes.reminders import router as reminders_router
from app.routes.referral import router as referral_router
from app.routes.learner_state import router as learner_state_router
from app.routes.concepts import router as concepts_router
from app.routes.mistakes import router as mistakes_router
from app.routes.well_known import router as well_known_router
from app.schemas.common import ErrorResponse, ErrorDetail, ErrorCodes

# Setup logging
logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Sentry — only active when DSN is configured
if settings.SENTRY_DSN:
    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        environment=settings.APP_ENV,
        integrations=[FastApiIntegration(), SqlalchemyIntegration()],
        traces_sample_rate=0.2,
        send_default_pii=False,
    )
    logger.info("Sentry error tracking enabled")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup/shutdown events."""
    # Startup
    logger.info(f"Starting {settings.APP_NAME}...")
    logger.info(f"Environment: {settings.APP_ENV}")
    logger.info(f"Debug mode: {settings.DEBUG}")
    
    # Initialize database (for development)
    # In production, use Alembic migrations
    if settings.is_development:
        try:
            await init_db()
            logger.info("Database initialized")
        except Exception as e:
            logger.error(f"Failed to initialize database: {e}")
    else:
        # Production migrations are handled by scripts/entrypoint.sh before Uvicorn starts.
        # Running Alembic from inside an active event loop can emit noisy coroutine warnings.
        logger.info("Skipping runtime Alembic check; migrations are managed by entrypoint")
    
    # Initialize Redis (rate limiting, token blacklist, caching)
    try:
        await RedisClient.connect()
    except Exception as e:
        logger.warning(f"Redis unavailable — rate limiting will use in-memory fallback: {e}")

    if settings.LEARNER_STATE_ENABLED:
        from app.services.learner_state_outbox import (
            start_learner_state_outbox_worker,
        )

        start_learner_state_outbox_worker()
    
    yield
    
    # Shutdown
    logger.info("Shutting down...")
    if settings.LEARNER_STATE_ENABLED:
        from app.services.learner_state_outbox import stop_learner_state_outbox_worker

        await stop_learner_state_outbox_worker()
    await RedisClient.close()
    await close_db()
    logger.info("Shutdown complete")


# Create FastAPI app
app = FastAPI(
    title=settings.APP_NAME,
    description="""
    ## LexiLingo Backend Service
    
    RESTful API service for user management, courses, vocabulary, and progress tracking.
    
    ### Features:
    * **Authentication**: JWT-based auth with register/login
    * **User Management**: Profile management and preferences
    * **Courses**: Course catalog and lessons
    * **Progress Tracking**: User learning progress and streaks
    * **Vocabulary**: Personal vocabulary library
    
    ### Architecture:
    * **Database**: PostgreSQL with SQLAlchemy ORM
    * **Auth**: JWT tokens with bcrypt password hashing
    * **API**: RESTful endpoints with OpenAPI docs
    
    ### Related Services:
    * **AI Service**: Handles AI chat, pronunciation analysis (separate service)
    
    ### Documentation:
    * **Swagger UI**: `/docs` (you are here)
    * **ReDoc**: `/redoc`
    """,
    version="1.0.1",
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
    lifespan=lifespan,
    swagger_ui_parameters={
        "defaultModelsExpandDepth": -1,
        "docExpansion": "none",
        "filter": True,
        "syntaxHighlight.theme": "monokai"
    },
    contact={
        "name": "LexiLingo Team",
        "url": "https://github.com/InfinityZero3000/LexiLingo",
    },
    license_info={
        "name": "MIT License",
        "url": "https://opensource.org/licenses/MIT"
    }
)


# ===== MIDDLEWARE CONFIGURATION =====
# Order matters! Last added = outermost (executes first for requests).
# 
# Execution order (request): PNA → CORS → RateLimit → RequestID → Logging → App
# Execution order (response): App → Logging → RequestID → RateLimit → CORS → PNA
#
# KEY: CORS must be OUTSIDE RateLimit and Logging so error responses get CORS headers.
# PNA must be OUTSIDE CORS so it can add PNA headers to CORS preflight responses.

# 1. Trusted Host - Security (innermost, closest to app)
if settings.is_production:
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=settings.ALLOWED_HOSTS
    )

# 2. Request Logging - Log all requests
app.add_middleware(RequestLoggingMiddleware)

# 3. Request ID - Add unique ID to each request
app.add_middleware(RequestIDMiddleware)

# 4. Rate Limiting - Prevent abuse (Phase 1: Security)
# Higher limits in development to avoid blocking local testing
_rate_rpm = 300 if settings.is_development else 120
_rate_rph = 5000 if settings.is_development else 1000
app.add_middleware(
    RateLimitMiddleware,
    requests_per_minute=_rate_rpm,
    requests_per_hour=_rate_rph,
)

# 5. CORS - Must be OUTSIDE RateLimit so error responses get CORS headers
if settings.enable_app_cors:
    _cors_origin_regex = settings.CORS_ALLOW_ORIGIN_REGEX or ""
    _lexilingo_origin_regex = r"https?://(www\.)?lexilingo\.me(:\d+)?"
    if _cors_origin_regex:
        _cors_origin_regex = f"{_cors_origin_regex}|{_lexilingo_origin_regex}"
    else:
        _cors_origin_regex = _lexilingo_origin_regex

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=_cors_origin_regex,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "X-Api-Key",
            "X-Admin-Key",
            "X-Request-Id",
            "X-Idempotency-Key",
            "X-AI-Service-Secret",
        ],
        allow_private_network=True,
    )
    logger.info("App-level CORS middleware enabled")
else:
    logger.info("App-level CORS middleware disabled (edge handles CORS)")

# 6. Private Network Access - Chrome CORS-RFC1918 (outermost)
app.add_middleware(PrivateNetworkAccessMiddleware)

# 7. Security Headers Middleware (outermost for security fallback)
app.add_middleware(SecurityHeadersMiddleware)

# ===== EXCEPTION HANDLERS =====
app.add_exception_handler(HTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)


@app.middleware("http")
async def forward_proto_middleware(request: Request, call_next):
    """Respect x-forwarded-proto header to set request scheme for reverse proxies."""
    x_forwarded_proto = request.headers.get("x-forwarded-proto")
    if x_forwarded_proto:
        request.scope["scheme"] = x_forwarded_proto
    return await call_next(request)


# ===== Request Body Size Limit (Phase 4) =====
@app.middleware("http")
async def limit_request_body(request: Request, call_next):
    """Reject requests with bodies larger than MAX_REQUEST_BODY_BYTES."""
    limit = settings.MAX_REQUEST_BODY_BYTES
    if request.url.path.startswith(f"{settings.API_V1_PREFIX}/internal/learner-state"):
        limit = settings.LEARNER_STATE_MAX_BODY_BYTES
    content_length = request.headers.get("content-length")
    try:
        declared_length = int(content_length) if content_length else None
    except ValueError:
        return JSONResponse(status_code=400, content={"detail": "Invalid Content-Length"})
    if declared_length is not None and declared_length > limit:
        return JSONResponse(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            content={"detail": "Request body too large"},
        )
    if request.method not in {"POST", "PUT", "PATCH"}:
        return await call_next(request)

    class _RequestBodyTooLarge(Exception):
        pass

    original_receive = request._receive
    received = 0

    async def limited_receive():
        nonlocal received
        message = await original_receive()
        if message.get("type") == "http.request":
            received += len(message.get("body", b""))
            if received > limit:
                raise _RequestBodyTooLarge
        return message

    request._receive = limited_receive
    try:
        return await call_next(request)
    except _RequestBodyTooLarge:
        return JSONResponse(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            content={"detail": "Request body too large"},
        )

# Include routers
app.include_router(well_known_router)
app.include_router(health_router, tags=["Health"])
app.include_router(auth_router, prefix=f"{settings.API_V1_PREFIX}/auth", tags=["Authentication"])
app.include_router(users_router, prefix=f"{settings.API_V1_PREFIX}/users", tags=["Users"])
app.include_router(courses_router, prefix=f"{settings.API_V1_PREFIX}/courses", tags=["Courses"])
app.include_router(
    integrations_router,
    prefix=f"{settings.API_V1_PREFIX}/integrations",
    tags=["Partner Integrations"],
)
app.include_router(course_categories_router, prefix=f"{settings.API_V1_PREFIX}/categories", tags=["Course Categories"])
app.include_router(progress_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Progress"])
app.include_router(learning_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Learning Sessions"])
app.include_router(vocabulary_router, prefix=f"{settings.API_V1_PREFIX}/vocabulary", tags=["Vocabulary"])
app.include_router(concepts_router, prefix=f"{settings.API_V1_PREFIX}/concepts", tags=["Concepts"])
app.include_router(gamification_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Gamification"])
app.include_router(challenges_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Challenges"])
app.include_router(admin_courses_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Admin"])
app.include_router(admin_gamification_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Admin"])
app.include_router(admin_system_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Admin"])
app.include_router(content_agent_router, prefix=f"{settings.API_V1_PREFIX}")
app.include_router(notification_campaign_router, prefix=f"{settings.API_V1_PREFIX}")
app.include_router(ranking_agent_router, prefix=f"{settings.API_V1_PREFIX}")
app.include_router(devices_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Devices"])
app.include_router(proficiency_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Proficiency Assessment"])
app.include_router(rbac_router, prefix=f"{settings.API_V1_PREFIX}", tags=["RBAC Management"])
app.include_router(analytics_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Analytics"])
app.include_router(user_management_router, prefix=f"{settings.API_V1_PREFIX}", tags=["User Management"])
app.include_router(reminders_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Reminder Preferences"])
app.include_router(notifications_router, prefix=f"{settings.API_V1_PREFIX}/notifications", tags=["Notifications"])
app.include_router(mistakes_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Mistakes"])

# Content Features
app.include_router(youtube_router, prefix=f"{settings.API_V1_PREFIX}", tags=["YouTube"])
app.include_router(news_router, prefix=f"{settings.API_V1_PREFIX}", tags=["News"])
app.include_router(podcasts_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Podcasts"])

# Phase 3: English Games + XP System
app.include_router(games_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Games"])
app.include_router(xp_router, prefix=f"{settings.API_V1_PREFIX}", tags=["XP System"])

# Phase 5: Book Reading
app.include_router(books_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Books"])
app.include_router(ai_audit_router, prefix=f"{settings.API_V1_PREFIX}", tags=["AI Audit"])
app.include_router(monitoring_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Admin Monitoring"])
app.include_router(referral_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Referral"])
app.include_router(learner_state_router, prefix=f"{settings.API_V1_PREFIX}")

# Prometheus metrics — exposed at /metrics, scraped by Prometheus server
try:
    from prometheus_fastapi_instrumentator import Instrumentator
    import prometheus_fastapi_instrumentator.routing as _pfi_routing
    from starlette.routing import Match, Mount

    # Starlette 1.x adds _IncludedRouter objects to app.routes. These have
    # a matches() method but no .path attribute, crashing the default route
    # name resolver. Patch _get_route_name to guard against that.
    def _safe_get_route_name(scope, routes, route_name=None):
        for route in routes:
            match, child_scope = route.matches(scope)
            if match == Match.FULL:
                if not hasattr(route, "path"):
                    if hasattr(route, "routes"):
                        child_scope = {**scope, **child_scope}
                        return _safe_get_route_name(child_scope, route.routes, route_name)
                    return route_name
                route_name = route.path
                child_scope = {**scope, **child_scope}
                if isinstance(route, Mount) and route.routes:
                    child_name = _safe_get_route_name(child_scope, route.routes, route_name)
                    route_name = None if child_name is None else route_name + child_name
                return route_name
            elif match == Match.PARTIAL and route_name is None:
                if hasattr(route, "path"):
                    route_name = route.path
        return None

    _pfi_routing._get_route_name = _safe_get_route_name

    Instrumentator(
        should_group_status_codes=True,
        excluded_handlers=["/health", "/metrics"],
    ).instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)
    logger.info("Prometheus metrics enabled at /metrics")
except ImportError:
    logger.warning("prometheus-fastapi-instrumentator not installed; /metrics disabled")

# Serve uploaded/imported media files
import os
_media_dir = "/app/data/media"
if os.path.isdir(_media_dir):
    app.mount("/media", StaticFiles(directory=_media_dir), name="media")


@app.api_route("/", methods=["GET", "HEAD"])
async def root():
    """Root endpoint. Supports HEAD for Render/load-balancer health probes."""
    return {
        "message": f"Welcome to {settings.APP_NAME}",
        "version": "1.0.1",
        "docs": "/docs",
        "health": "/health"
    }


if __name__ == "__main__":
    import multiprocessing
    import uvicorn

    workers = 1 if settings.DEBUG else (multiprocessing.cpu_count() * 2 + 1)
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=settings.PORT,
        reload=settings.DEBUG,
        workers=1 if settings.DEBUG else workers,
        timeout_keep_alive=5,
    )
