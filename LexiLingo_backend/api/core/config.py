"""
Configuration management for LexiLingo Backend

Environment-aware settings following Clean Architecture principles
Similar to Flutter's environment configuration
"""

import os
from typing import List
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings."""
    
    # ============================================================
    # Environment
    # ============================================================
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    DEBUG: bool = os.getenv("DEBUG", "true").lower() == "true"
    API_VERSION: str = "1.0.0"
    
    # ============================================================
    # MongoDB Configuration
    # ============================================================
    MONGODB_URI: str = os.getenv(
        "MONGODB_URI",
        "mongodb://admin:lexilingo2026@localhost:27017/"
    )
    MONGODB_DATABASE: str = os.getenv("MONGODB_DATABASE", "lexilingo_dev")
    MONGODB_MIN_POOL_SIZE: int = 2
    MONGODB_MAX_POOL_SIZE: int = 50 if ENVIRONMENT == "production" else 10
    
    # ============================================================
    # Redis Configuration
    # ============================================================
    REDIS_URL: str = os.getenv(
        "REDIS_URL",
        "redis://:lexilingo2026@localhost:6379/0"
    )
    REDIS_MAX_CONNECTIONS: int = 50
    
    # ============================================================
    # CORS Settings
    # ============================================================
    ALLOWED_ORIGINS: List[str] = [
        "http://localhost:3000",  # Flutter web dev
        "http://localhost:8080",  # Flutter web dev (alternate)
        "http://127.0.0.1:3000",
        "https://lexilingo.vercel.app",  # Production Flutter web
        # Add your custom domains here
    ]
    
    # ============================================================
    # API Keys (for external services)
    # ============================================================
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    HUGGINGFACE_API_KEY: str = os.getenv("HUGGINGFACE_API_KEY", "")
    
    # ============================================================
    # Logging Configuration
    # ============================================================
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    LOG_AI_INTERACTIONS: bool = True
    LOG_PERFORMANCE_METRICS: bool = True
    
    # ============================================================
    # AI Model Configuration (for DL-Model-Support integration)
    # ============================================================
    AI_MODEL_API_URL: str = os.getenv(
        "AI_MODEL_API_URL",
        "http://localhost:8001"  # DL-Model-Support API
    )
    AI_MODEL_TIMEOUT: int = 30  # seconds
    
    # ============================================================
    # Rate Limiting
    # ============================================================
    RATE_LIMIT_ENABLED: bool = ENVIRONMENT == "production"
    RATE_LIMIT_PER_MINUTE: int = 60
    
    # ============================================================
    # Vercel Deployment Detection
    # ============================================================
    IS_VERCEL: bool = os.getenv("VERCEL", "").lower() == "1"
    
    class Config:
        """Pydantic configuration."""
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    """
    Get cached settings instance.
    
    Similar to Flutter's GetIt singleton pattern.
    """
    return Settings()


# Global settings instance
settings = get_settings()
