"""
Application configuration

Using Pydantic settings for type-safe configuration
"""

from typing import List
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict
from dotenv import load_dotenv

# Get project root directory and load .env explicitly
PROJECT_ROOT = Path(__file__).parent.parent.parent
load_dotenv(PROJECT_ROOT / ".env")


class Settings(BaseSettings):
    """Application settings."""
    
    # Application
    APP_NAME: str = "LexiLingo Backend Service"
    APP_ENV: str = "development"
    API_V1_PREFIX: str = "/api/v1"
    DEBUG: bool = True
    PORT: int = 8000
    
    # Database
    DATABASE_URL: str
    DB_ECHO: bool = False
    DB_POOL_SIZE: int = 20
    DB_MAX_OVERFLOW: int = 10
    
    # Request limits
    MAX_REQUEST_BODY_BYTES: int = 10 * 1024 * 1024  # 10 MB

    @property
    def effective_pool_size(self) -> int:
        """Return larger pool in production."""
        return 50 if self.is_production else self.DB_POOL_SIZE

    @property
    def effective_max_overflow(self) -> int:
        """Return larger overflow in production."""
        return 20 if self.is_production else self.DB_MAX_OVERFLOW
    
    # Security
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    # CORS
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://localhost:8080,http://localhost:5173"
    ALLOWED_HOSTS: List[str] = ["localhost", "127.0.0.1", "*.lexilingo.com"]
    
    @property
    def cors_origins(self) -> List[str]:
        """Parse ALLOWED_ORIGINS string to list"""
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",")]
    
    # Logging
    LOG_LEVEL: str = "INFO"
    
    # AI Service (optional)
    AI_SERVICE_URL: str = "http://localhost:8001/api/v1"

    # Google OAuth
    GOOGLE_CLIENT_ID: str | None = None
    GOOGLE_ADMIN_CLIENT_ID: str | None = None

    # Firebase (optional, for ID token verification from Flutter app)
    FIREBASE_PROJECT_ID: str | None = None
    # Option 1: Paste JSON directly (escape quotes/newlines)
    FIREBASE_CREDENTIALS_JSON: str | None = None
    # Option 2: Path to service account JSON file (recommended)
    FIREBASE_CREDENTIALS_FILE: str | None = None

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_PASSWORD: str | None = None

    # ── External API Keys (Phase 0+ Content Features) ──
    YOUTUBE_API_KEY: str | None = None           # YouTube Data API v3
    NEWSAPI_KEY: str | None = None               # NewsAPI.org
    NEWSDATA_KEY: str | None = None              # NewsData.io (fallback)
    PODCASTINDEX_KEY: str | None = None          # PodcastIndex.org
    PODCASTINDEX_SECRET: str | None = None       # PodcastIndex.org secret
    WORDSAPI_KEY: str | None = None              # WordsAPI (RapidAPI)
    
    model_config = SettingsConfigDict(
        env_file=str(PROJECT_ROOT / ".env"),
        case_sensitive=True,
        extra="ignore"
    )
    
    @property
    def is_development(self) -> bool:
        """Check if running in development mode."""
        return self.APP_ENV == "development"
    
    @property
    def is_production(self) -> bool:
        """Check if running in production mode."""
        return self.APP_ENV == "production"


# Global settings instance
settings = Settings()
