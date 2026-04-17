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
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.core.database import init_db, close_db
from app.core.redis import RedisClient
from app.core.middleware import (
    RateLimitMiddleware,
    RequestLoggingMiddleware,
    RequestIDMiddleware,
    PrivateNetworkAccessMiddleware,
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
    progress_router,
    vocabulary_router,
    gamification_router,
)
from app.routes.learning import router as learning_router
from app.routes.admin import router as admin_router
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
from app.schemas.common import ErrorResponse, ErrorDetail, ErrorCodes

# Setup logging
logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


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
        # Production migration check
        try:
            from alembic import command
            from alembic.config import Config
            import os
            
            # Find alembic.ini relative to this file
            ini_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "alembic.ini")
            if os.path.exists(ini_path):
                alembic_cfg = Config(ini_path)
                command.upgrade(alembic_cfg, "head")
                logger.info("Alembic migrations applied (upgrade head)")
        except Exception as e:
            logger.warning(f"Alembic check failed: {e}")
    
    # Initialize Redis (rate limiting, token blacklist, caching)
    try:
        await RedisClient.connect()
    except Exception as e:
        logger.warning(f"Redis unavailable — rate limiting will use in-memory fallback: {e}")
    
    yield
    
    # Shutdown
    logger.info("Shutting down...")
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
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
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
_rate_rph = 5000 if settings.is_development else 5000
app.add_middleware(
    RateLimitMiddleware,
    requests_per_minute=_rate_rpm,
    requests_per_hour=_rate_rph,
)

# 5. CORS - Must be OUTSIDE RateLimit so error responses get CORS headers
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_origin_regex=settings.CORS_ALLOW_ORIGIN_REGEX or None,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_private_network=True,
)

# 6. Private Network Access - Chrome CORS-RFC1918 (outermost)
app.add_middleware(PrivateNetworkAccessMiddleware)

# ===== EXCEPTION HANDLERS =====
app.add_exception_handler(HTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)


# ===== Request Body Size Limit (Phase 4) =====
@app.middleware("http")
async def limit_request_body(request: Request, call_next):
    """Reject requests with bodies larger than MAX_REQUEST_BODY_BYTES."""
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > settings.MAX_REQUEST_BODY_BYTES:
        return JSONResponse(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            content={"detail": "Request body too large"},
        )
    return await call_next(request)

# Include routers
app.include_router(health_router, tags=["Health"])
app.include_router(auth_router, prefix=f"{settings.API_V1_PREFIX}/auth", tags=["Authentication"])
app.include_router(users_router, prefix=f"{settings.API_V1_PREFIX}/users", tags=["Users"])
app.include_router(courses_router, prefix=f"{settings.API_V1_PREFIX}/courses", tags=["Courses"])
app.include_router(course_categories_router, prefix=f"{settings.API_V1_PREFIX}/categories", tags=["Course Categories"])
app.include_router(progress_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Progress"])
app.include_router(learning_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Learning Sessions"])
app.include_router(vocabulary_router, prefix=f"{settings.API_V1_PREFIX}/vocabulary", tags=["Vocabulary"])
app.include_router(gamification_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Gamification"])
app.include_router(challenges_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Challenges"])
app.include_router(admin_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Admin"])
app.include_router(devices_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Devices"])
app.include_router(proficiency_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Proficiency Assessment"])
app.include_router(rbac_router, prefix=f"{settings.API_V1_PREFIX}", tags=["RBAC Management"])
app.include_router(analytics_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Analytics"])
app.include_router(user_management_router, prefix=f"{settings.API_V1_PREFIX}", tags=["User Management"])

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


@app.api_route("/", methods=["GET", "HEAD"])
async def root():
    """Root endpoint. Supports HEAD for Render/load-balancer health probes."""
    return {
        "message": f"Welcome to {settings.APP_NAME}",
        "version": "1.0.0",
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
