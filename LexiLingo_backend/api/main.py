"""
LexiLingo FastAPI Backend
Main application entry point

Architecture: Clean Architecture (matching Flutter app structure)
- Domain: Business entities and logic
- Services: Business use cases  
- Routes: API endpoints (like Presentation layer)
- Models: Data models and repositories
"""

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import time
import logging
from contextlib import asynccontextmanager

# Import routes
from api.routes import ai_router, chat_router, user_router, health_router

# Import core
from api.core.config import settings
from api.core.database import mongodb_manager

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# Lifespan context manager for startup/shutdown events
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan events for FastAPI application.
    Replaces deprecated @app.on_event("startup") and @app.on_event("shutdown")
    """
    # Startup
    logger.info("🚀 Starting LexiLingo Backend API...")
    logger.info(f"Environment: {settings.ENVIRONMENT}")
    logger.info(f"API Version: {settings.API_VERSION}")
    
    # Connect to MongoDB
    try:
        await mongodb_manager.connect()
        logger.info("✅ MongoDB connected successfully")
    except Exception as e:
        logger.error(f"❌ Failed to connect to MongoDB: {e}")
        # Continue without MongoDB (graceful degradation)
    
    yield
    
    # Shutdown
    logger.info("🛑 Shutting down LexiLingo Backend API...")
    await mongodb_manager.disconnect()
    logger.info("✅ MongoDB disconnected")


# Create FastAPI app
app = FastAPI(
    title="LexiLingo API",
    description="Backend API for LexiLingo - AI-powered English learning platform",
    version=settings.API_VERSION,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
    lifespan=lifespan
)


# CORS middleware (allow Flutter web/mobile to connect)
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
    
    # Process request
    response = await call_next(request)
    
    # Calculate duration
    duration = time.time() - start_time
    
    # Log request
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
app.include_router(health_router, prefix="/api", tags=["Health"])
app.include_router(ai_router, prefix="/api/ai", tags=["AI"])
app.include_router(chat_router, prefix="/api/chat", tags=["Chat"])
app.include_router(user_router, prefix="/api/user", tags=["User"])


# Root endpoint
@app.get("/")
async def root():
    """API root endpoint."""
    return {
        "name": "LexiLingo API",
        "version": settings.API_VERSION,
        "status": "running",
        "docs": "/api/docs",
        "environment": settings.ENVIRONMENT
    }


# Health check endpoint (simple, no dependencies)
@app.get("/health")
async def health_simple():
    """Simple health check."""
    return {"status": "ok"}


# For local development
if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        "api.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,  # Auto-reload on code changes
        log_level="info"
    )
