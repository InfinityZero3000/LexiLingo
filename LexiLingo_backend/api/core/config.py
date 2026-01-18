"""
Configuration management for LexiLingo Backend

Environment-aware settings following Clean Architecture principles
Similar to Flutter's environment configuration
"""

import os
import json
from typing import List, Optional, Union
from pydantic_settings import BaseSettings
from pydantic import field_validator
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
    REDIS_HOST: str = os.getenv("REDIS_HOST", "localhost")
    REDIS_PORT: int = int(os.getenv("REDIS_PORT", "6379"))
    REDIS_PASSWORD: Optional[str] = os.getenv("REDIS_PASSWORD", "lexilingo2026")
    REDIS_DB: int = int(os.getenv("REDIS_DB", "0"))
    REDIS_MAX_CONNECTIONS: int = 50
    
    # ============================================================
    # CORS Settings
    # ============================================================
    ALLOWED_ORIGINS: Union[str, List[str]] = [
        "http://localhost:3000",  # Flutter web dev
        "http://localhost:8080",  # Flutter web dev (alternate)
        "http://127.0.0.1:3000",
        "https://lexilingo.vercel.app",  # Production Flutter web
        # Add your custom domains here
    ]
    
    @field_validator('ALLOWED_ORIGINS', mode='before')
    @classmethod
    def parse_allowed_origins(cls, v):
        """Parse ALLOWED_ORIGINS from string or list."""
        if isinstance(v, str):
            try:
                # Try to parse as JSON array
                return json.loads(v)
            except json.JSONDecodeError:
                # If not JSON, split by comma
                return [origin.strip() for origin in v.split(',')]
        return v
    
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
    AI_MODEL_API_KEY: Optional[str] = os.getenv("AI_MODEL_API_KEY")
    AI_MODEL_TIMEOUT: int = 30  # seconds
    
    # DL Model Service (alias for backward compatibility)
    DL_MODEL_API_URL: str = AI_MODEL_API_URL
    DL_MODEL_API_KEY: Optional[str] = AI_MODEL_API_KEY
    
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
        extra = "ignore"  # Ignore extra fields from .env file


@lru_cache()
def get_settings() -> Settings:
    """
    Get cached settings instance.
    
    Similar to Flutter's GetIt singleton pattern.
    """
    return Settings()


# Global settings instance
settings = get_settings()
