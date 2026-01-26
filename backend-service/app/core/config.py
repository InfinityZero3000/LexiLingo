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

    # Firebase (optional, for ID token verification)
    FIREBASE_PROJECT_ID: str | None = None
    FIREBASE_CREDENTIALS_JSON: str | None = None
    
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
