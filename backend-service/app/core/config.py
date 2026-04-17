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
    DEBUG: bool = False
    PORT: int = 8000
    
    # Database
    DATABASE_URL: str
    DB_ECHO: bool = False
    DB_POOL_SIZE: int = 20
    DB_MAX_OVERFLOW: int = 10

    @property
    def async_database_url(self) -> str:
        """
        Return an async-compatible DATABASE_URL.

        Render/Supabase/Heroku often provide ``postgres://`` or
        ``postgresql://`` URLs.  SQLAlchemy async requires the
        ``postgresql+asyncpg://`` scheme.  This property normalises that so
        env-vars from hosting providers work without manual editing.
        """
        url = self.DATABASE_URL
        if url.startswith("postgres://"):
            url = url.replace("postgres://", "postgresql+asyncpg://", 1)
        elif url.startswith("postgresql://") and "+asyncpg" not in url:
            url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
        return url
    
    # Request limits
    MAX_REQUEST_BODY_BYTES: int = 10 * 1024 * 1024  # 10 MB

    @property
    def effective_pool_size(self) -> int:
        """Return larger pool in production (sized for 10k concurrent users)."""
        return 100 if self.is_production else self.DB_POOL_SIZE

    @property
    def effective_max_overflow(self) -> int:
        """Return larger overflow in production."""
        return 50 if self.is_production else self.DB_MAX_OVERFLOW
    
    # Security
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    # CORS
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://localhost:8080,http://localhost:5176"
    CORS_ALLOW_ORIGIN_REGEX: str = (
        r"https?://([a-zA-Z0-9-]+\.)*vercel\.app(:\d+)?"
        r"|https?://([a-zA-Z0-9-]+\.)*netlify\.app(:\d+)?"
        r"|https?://.*\.devtunnels\.ms(:\d+)?"
        r"|https?://.*\.github\.dev(:\d+)?"
    )
    ALLOWED_HOSTS: List[str] = [
        "localhost",
        "127.0.0.1",
        "*.lexilingo.com",
        "*.onrender.com",
        "*.vercel.app",
    ]
    
    @property
    def cors_origins(self) -> List[str]:
        """Parse ALLOWED_ORIGINS string to list"""
        return [
            origin.strip()
            for origin in self.ALLOWED_ORIGINS.split(",")
            if origin.strip()
        ]
    
    # Logging
    LOG_LEVEL: str = "INFO"

    # Email (SMTP)
    SMTP_HOST: str | None = None
    SMTP_PORT: int = 587
    SMTP_USERNAME: str | None = None
    SMTP_PASSWORD: str | None = None
    SMTP_USE_TLS: bool = True
    SMTP_USE_SSL: bool = False
    EMAIL_FROM: str = "noreply@lexilingo.app"
    PASSWORD_RESET_URL_BASE: str = "http://localhost:8080/#/reset-password"
    
    # AI Service (optional)
    AI_SERVICE_URL: str = "http://localhost:8001/api/v1"
    AI_AUDIT_INGEST_SECRET: str = ""

    # Google OAuth
    GOOGLE_CLIENT_ID: str | None = None
    GOOGLE_ADMIN_CLIENT_ID: str | None = None
    ADMIN_EMAIL_WHITELIST: str = ""
    SUPER_ADMIN_EMAIL_WHITELIST: str = ""

    @staticmethod
    def _parse_email_list(raw_value: str) -> List[str]:
        """Normalize a comma-separated email allowlist."""
        return [
            email.strip().lower()
            for email in raw_value.split(",")
            if email.strip()
        ]

    @property
    def admin_email_whitelist(self) -> List[str]:
        """Emails allowed to access the admin application."""
        return self._parse_email_list(self.ADMIN_EMAIL_WHITELIST)

    @property
    def super_admin_email_whitelist(self) -> List[str]:
        """Emails that should receive super_admin on first Google login."""
        return self._parse_email_list(self.SUPER_ADMIN_EMAIL_WHITELIST)

    def get_admin_role_for_email(self, email: str | None) -> str | None:
        """Return the allowlisted admin role for an email, if any."""
        if not email:
            return None

        normalized_email = email.strip().lower()
        if normalized_email in self.super_admin_email_whitelist:
            return "super_admin"
        if normalized_email in self.admin_email_whitelist:
            return "admin"
        return None

    # Firebase (optional, for ID token verification from Flutter app)
    FIREBASE_PROJECT_ID: str | None = None
    # Option 1: Paste JSON directly (escape quotes/newlines)
    FIREBASE_CREDENTIALS_JSON: str | None = None
    # Option 2: Path to service account JSON file (recommended)
    FIREBASE_CREDENTIALS_FILE: str | None = None

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_PASSWORD: str | None = None
    # Trusted reverse-proxy IPs (comma-separated) allowed to set X-Forwarded-For.
    # Set to your load balancer IP(s) in production; leave empty for dev/direct deployments.
    TRUSTED_PROXIES: str = ""

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
settings = Settings()  # pyright: ignore[reportCallIssue]
