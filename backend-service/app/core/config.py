"""
Application configuration

Using Pydantic settings for type-safe configuration
"""

from typing import List
from pathlib import Path
import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator, model_validator
from dotenv import load_dotenv

# Get project root directory and load environment files explicitly.
# Always load .env first, then override with .env.production in production mode.
PROJECT_ROOT = Path(__file__).parent.parent.parent
load_dotenv(PROJECT_ROOT / ".env")
if os.getenv("APP_ENV", "").lower() == "production":
    # Do not use override=True here because it overwrites real container environment variables!
    load_dotenv(PROJECT_ROOT / ".env.production", override=False)


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
    JWT_ISSUER: str = "lexilingo-backend"
    JWT_AUDIENCE: str = "lexilingo-services"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    # CORS
    # ENABLE_APP_CORS: explicit override (takes priority over GATEWAY_HANDLES_CORS).
    # GATEWAY_HANDLES_CORS: set true only when an Nginx/Kong gateway sits in front
    #   and emits CORS headers via proxy_hide_header + add_header. The gateway's
    #   proxy_hide_header strips backend CORS headers, preventing duplicates.
    #   Default false (safe for direct Render/PaaS deployments without a gateway).
    ENABLE_APP_CORS: bool | None = None
    GATEWAY_HANDLES_CORS: bool = False
    ALLOWED_ORIGINS: str = "https://lexilingo.me,https://www.lexilingo.me,https://admin.lexilingo.me"
    CORS_ALLOW_ORIGIN_REGEX: str = (
        r"https?://([a-zA-Z0-9-]+\.)*lexilingo\.me(:\d+)?"
    )
    ALLOWED_HOSTS: List[str] = [
        "api.lexilingo.me",
        "*.lexilingo.me",
        "lexilingo-backend.onrender.com",
    ]

    @field_validator("ALLOWED_HOSTS", mode="before")
    @classmethod
    def parse_allowed_hosts(cls, value):
        """Accept either JSON/list values or a comma-separated env var."""
        if isinstance(value, str):
            return [host.strip() for host in value.split(",") if host.strip()]
        return value
    
    @property
    def cors_origins(self) -> List[str]:
        """Parse ALLOWED_ORIGINS string to list"""
        return [
            origin.strip()
            for origin in self.ALLOWED_ORIGINS.split(",")
            if origin.strip()
        ]

    @model_validator(mode="after")
    def validate_production_security(self):
        """Fail fast on unsafe production security settings."""
        if not self.is_production:
            return self

        if self.DEBUG:
            raise ValueError("DEBUG must be false when APP_ENV=production")

        if self.SECRET_KEY.strip().lower().startswith(("your-secret", "change_me", "replace_")):
            raise ValueError("SECRET_KEY must be a real secret when APP_ENV=production")

        if self.enable_app_cors:
            origins = self.cors_origins
            local_origins = [
                origin for origin in origins
                if "localhost" in origin or "127.0.0.1" in origin
            ]
            if "*" in origins:
                raise ValueError("Wildcard CORS origins are not allowed with credentials in production")
            if local_origins:
                raise ValueError("Localhost CORS origins are not allowed when APP_ENV=production")
            if "devtunnels.ms" in self.CORS_ALLOW_ORIGIN_REGEX or "github.dev" in self.CORS_ALLOW_ORIGIN_REGEX:
                raise ValueError("Broad development tunnel CORS regex is not allowed in production")

        return self
    
    # Logging
    LOG_LEVEL: str = "INFO"

    # Error Tracking
    SENTRY_DSN: str | None = None

    # Email (SMTP)
    SMTP_HOST: str | None = None
    SMTP_PORT: int = 587
    SMTP_USERNAME: str | None = None
    SMTP_PASSWORD: str | None = None
    SMTP_USE_TLS: bool = True
    SMTP_USE_SSL: bool = False
    SMTP_TIMEOUT: int = 10
    EMAIL_FROM: str = "noreply@lexilingo.app"
    PASSWORD_RESET_URL_BASE: str = "https://lexilingo.me/reset-password"
    PASSWORD_RESET_URL_BASE_PRODUCTION: str | None = None
    EMAIL_VERIFICATION_URL_BASE: str = "https://lexilingo.me/verify-email"
    EMAIL_VERIFICATION_URL_BASE_PRODUCTION: str | None = None
    
    # AI Service (optional)
    AI_SERVICE_URL: str = "https://api.lexilingo.me/api/v1"
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

    # Reminder scheduler (disabled by default for safe rollout)
    REMINDERS_ENABLED: bool = False
    REMINDER_DRY_RUN: bool = True
    REMINDER_SCAN_BATCH_SIZE: int = 250
    REMINDER_SCAN_INTERVAL_SECONDS: int = 300
    REMINDER_DEFAULT_TIMEZONE: str = "Asia/Ho_Chi_Minh"
    REMINDER_REVIEW_ROUTE: str = "/vocabulary/review"
    APP_PUBLIC_URL: str = "https://lexilingo.me"

    # Celery. Falls back to REDIS_URL when unset.
    CELERY_BROKER_URL: str | None = None
    CELERY_RESULT_BACKEND: str | None = None

    @property
    def effective_celery_broker_url(self) -> str:
        return self.CELERY_BROKER_URL or self.REDIS_URL

    @property
    def effective_celery_result_backend(self) -> str:
        return self.CELERY_RESULT_BACKEND or self.REDIS_URL

    # ── External API Keys (Phase 0+ Content Features) ──
    YOUTUBE_API_KEY: str | None = None           # YouTube Data API v3
    NEWSAPI_KEY: str | None = None               # NewsAPI.org
    NEWSDATA_KEY: str | None = None              # NewsData.io (fallback)
    PODCASTINDEX_KEY: str | None = None          # PodcastIndex.org
    PODCASTINDEX_SECRET: str | None = None       # PodcastIndex.org secret
    DICTIONARY_API_BASE_URL: str = "https://api.dictionaryapi.dev/api/v2/entries/en"
    
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

    @property
    def enable_app_cors(self) -> bool:
        """Whether backend should emit CORS headers directly.

        Default: on (safe for direct PaaS deployments).
        Set GATEWAY_HANDLES_CORS=true to disable when an Nginx/Kong gateway
        handles CORS via proxy_hide_header, preventing duplicate headers.
        """
        if self.ENABLE_APP_CORS is not None:
            return self.ENABLE_APP_CORS
        return not self.GATEWAY_HANDLES_CORS

    @property
    def effective_password_reset_url_base(self) -> str:
        """Return reset URL base according to current environment."""
        if self.is_production and self.PASSWORD_RESET_URL_BASE_PRODUCTION:
            return self.PASSWORD_RESET_URL_BASE_PRODUCTION
        return self.PASSWORD_RESET_URL_BASE

    @property
    def effective_email_verification_url_base(self) -> str:
        """Return email verification URL base according to current environment."""
        if self.is_production and self.EMAIL_VERIFICATION_URL_BASE_PRODUCTION:
            return self.EMAIL_VERIFICATION_URL_BASE_PRODUCTION
        return self.EMAIL_VERIFICATION_URL_BASE


# Global settings instance
settings = Settings()  # pyright: ignore[reportCallIssue]
