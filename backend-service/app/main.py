"""
LexiLingo Backend App
FastAPI application for user management, courses, and progress tracking

Architecture: Clean Architecture
- Models: SQLAlchemy (PostgreSQL)
- Schemas: Pydantic validation
- Routes: API endpoints
- Services: Business logic
"""

import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import time

from app.core.config import settings
from app.core.database import init_db, close_db
from app.routes import (
    health_router,
    auth_router,
    users_router,
    courses_router,
)

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


# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all incoming requests with timing."""
    start_time = time.time()
    
    response = await call_next(request)
    
    duration = time.time() - start_time
    
    logger.info(
        f"{request.method} {request.url.path} - "
        f"Status: {response.status_code} - "
        f"Duration: {duration:.3f}s"
    )
    
    return response


# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Handle uncaught exceptions."""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "message": str(exc) if settings.DEBUG else "An error occurred",
            "path": str(request.url.path)
        }
    )


# Include routers
app.include_router(health_router, tags=["Health"])
app.include_router(auth_router, prefix=f"{settings.API_V1_PREFIX}/auth", tags=["Authentication"])
app.include_router(users_router, prefix=f"{settings.API_V1_PREFIX}/users", tags=["Users"])
app.include_router(courses_router, prefix=f"{settings.API_V1_PREFIX}/courses", tags=["Courses"])


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
