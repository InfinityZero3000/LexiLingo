"""
Application configuration

Using Pydantic settings for type-safe configuration
"""

from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict


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
    ALLOWED_ORIGINS: List[str] = [
        "http://localhost:3000",
        "http://localhost:8080",
    ]
    
    # Logging
    LOG_LEVEL: str = "INFO"
    
    # AI Service (optional)
    AI_SERVICE_URL: str = "http://localhost:8001/api/v1"
    
    model_config = SettingsConfigDict(
        env_file=".env",
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
