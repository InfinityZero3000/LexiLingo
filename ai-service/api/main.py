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
from api.routes import (
    ai_router,
    chat_router,
    user_router,
    health_router,
    training_router,
    cag_router,
    stt_router,
    tts_router,
    topic_chat_router,
)

# Import core
from api.core.config import settings
from api.core.database import mongodb_manager
from api.core.redis_client import RedisClient

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
    logger.info("Starting LexiLingo Backend API...")
    logger.info(f"Environment: {settings.ENVIRONMENT}")
    logger.info(f"API Version: {settings.API_VERSION}")
    
    # Connect to MongoDB
    try:
        await mongodb_manager.connect()
        logger.info("MongoDB connected successfully")
    except Exception as e:
        logger.error(f"Failed to connect to MongoDB: {e}")
        # Continue without MongoDB (graceful degradation)
    
    # Connect to Redis (with graceful degradation)
    try:
        await RedisClient.get_instance()
        logger.info("Redis connected successfully")
    except Exception as e:
        logger.warning(f"Redis connection failed: {e}. Continuing without cache...")
    
    yield
    
    # Shutdown
    logger.info("Shutting down LexiLingo Backend API...")
    await mongodb_manager.disconnect()
    await RedisClient.close()
    logger.info("Shutdown complete")


# Create FastAPI app with comprehensive Swagger configuration
app = FastAPI(
    title="LexiLingo AI Service",
    description="""
    ## LexiLingo AI Service - AI-Powered Learning Platform
    
    AI Service xử lý chat, pronunciation analysis, STT/TTS, và ML models.
    
    ### Tính năng chính:
    * **AI Chat với Gemini**: Trò chuyện thông minh với AI tutor
    * **Phân tích ngữ pháp**: Phát hiện và sửa lỗi tự động
    * **Theo dõi tiến độ**: Phân tích pattern học tập
    * **Quản lý session**: Lưu trữ lịch sử hội thoại
    
    ### Môi trường:
    * **Development**: `http://localhost:8000`
    * **Production**: `https://api.lexilingo.com`
    
    ### Tài liệu:
    * **Swagger UI**: `/docs` (bạn đang ở đây)
    * **ReDoc**: `/redoc`
    * **API Contract**: Xem file `docs/API_CONTRACT.md`
    """,
    version=settings.API_VERSION,
    docs_url="/docs",  # Swagger UI tại /docs
    redoc_url="/redoc",  # ReDoc tại /redoc
    openapi_url="/openapi.json",  # OpenAPI schema
    lifespan=lifespan,
    # Swagger UI configuration
    swagger_ui_parameters={
        "defaultModelsExpandDepth": -1,  # Ẩn schemas mặc định
        "docExpansion": "none",  # Thu gọn tất cả endpoints
        "filter": True,  # Bật tìm kiếm
        "showCommonExtensions": True,
        "syntaxHighlight.theme": "monokai"  # Dark theme
    },
    # Contact và license info
    contact={
        "name": "LexiLingo Backend Team",
        "url": "https://github.com/InfinityZero3000/LexiLingo",
        "email": "support@lexilingo.com"
    },
    license_info={
        "name": "MIT License",
        "url": "https://opensource.org/licenses/MIT"
    },
    # Servers cho Swagger UI
    servers=[
        {
            "url": "http://localhost:8000",
            "description": "Development server"
        },
        {
            "url": "https://api.lexilingo.com",
            "description": "Production server"
        }
    ]
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


# Include routers with detailed tags
app.include_router(
    health_router, 
    tags=["Health & Status"],
    prefix=""
)
app.include_router(
    ai_router, 
    prefix="/api/v1/ai",
    tags=["AI Interactions & Analytics"]
)
app.include_router(
    chat_router, 
    prefix="/api/v1/chat",
    tags=["Chat with Gemini AI"]
)
app.include_router(
    user_router, 
    prefix="/api/v1/users",
    tags=["User Data & Learning Pattern"]
)
app.include_router(
    training_router,
    prefix="/api/v1/training",
    tags=["Training & Learning (ML Pipeline)"]
)
app.include_router(
    cag_router,
    prefix="/api/v1/cag",
    tags=["Content Auto-Generation (CAG)"]
)
app.include_router(
    stt_router,
    prefix="/api/v1/stt",
    tags=["Speech-to-Text (STT)"]
)
app.include_router(
    tts_router,
    prefix="/api/v1/tts",
    tags=["Text-to-Speech (TTS)"]
)
app.include_router(
    topic_chat_router,
    prefix="/api/v1/topics",
    tags=["Topic-Based Conversation"]
)


# Root endpoint
@app.get(
    "/",
    summary="API Root",
    description="Thông tin cơ bản về API",
    tags=["General"]
)
async def root():
    """API root endpoint với thông tin cơ bản."""
    return {
        "name": "LexiLingo API",
        "version": settings.API_VERSION,
        "status": "running",
        "docs": "/docs",
        "redoc": "/redoc",
        "openapi": "/openapi.json",
        "environment": settings.ENVIRONMENT,
        "message": "Welcome to LexiLingo API!"
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
