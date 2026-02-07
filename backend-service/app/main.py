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
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.core.database import init_db, close_db
from app.core.middleware import (
    RateLimitMiddleware,
    ErrorHandlerMiddleware,
    RequestLoggingMiddleware,
    RequestIDMiddleware,
)
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
    
    yield
    
    # Shutdown
    logger.info("Shutting down...")
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
# Order matters! Middleware is executed in reverse order of addition.

# 1. CORS - Allow cross-origin requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,  # Use property to parse string
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 2. Trusted Host - Security: Prevent Host header attacks
if not settings.is_development:
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=settings.ALLOWED_HOSTS
    )

# 3. Error Handler - Catch unhandled exceptions
app.add_middleware(ErrorHandlerMiddleware)

# 4. Request Logging - Log all requests (Phase 5: Observability)
app.add_middleware(RequestLoggingMiddleware)

# 5. Request ID - Add unique ID to each request
app.add_middleware(RequestIDMiddleware)

# 6. Rate Limiting - Prevent abuse (Phase 1: Security)
app.add_middleware(
    RateLimitMiddleware,
    requests_per_minute=60,
    requests_per_hour=1000
)


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


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "message": f"Welcome to {settings.APP_NAME}",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=settings.PORT,
        reload=settings.DEBUG
    )
