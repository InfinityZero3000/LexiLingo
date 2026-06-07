"""
Configuration management for LexiLingo Backend

Environment-aware settings following Clean Architecture principles
Similar to Flutter's environment configuration
"""

import os
import json
from typing import List, Optional, Union
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import AliasChoices, Field, field_validator, model_validator
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )
    
    # ============================================================
    # Environment
    # ============================================================
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    DEBUG: bool = os.getenv("DEBUG", "false").lower() == "true"
    API_VERSION: str = "1.0.0"
    APP_NAME: str = "LexiLingo AI Service"
    
    # ============================================================
    # MongoDB Configuration
    # ============================================================
    MONGODB_ATLAS_URI: str = os.getenv("MONGODB_ATLAS_URI", "").strip()
    MONGODB_URI: str = os.getenv(
        "MONGODB_URI",
        ""
    ).strip() or MONGODB_ATLAS_URI or "mongodb://localhost:27017"
    MONGODB_DATABASE: str = os.getenv("MONGODB_DATABASE", "lexilingo_dev")
    MONGODB_TLS_ALLOW_INVALID_CERTIFICATES: bool = (
        os.getenv("MONGODB_TLS_ALLOW_INVALID_CERTIFICATES", "false").lower() == "true"
    )
    MONGODB_SERVER_SELECTION_TIMEOUT_MS: int = int(
        os.getenv("MONGODB_SERVER_SELECTION_TIMEOUT_MS", "10000")
    )
    MONGODB_MIN_POOL_SIZE: int = 2
    MONGODB_MAX_POOL_SIZE: int = 50 if ENVIRONMENT == "production" else 10
    
    # ============================================================
    # Redis Configuration
    # ============================================================
    REDIS_URL: str = os.getenv(
        "REDIS_URL",
        "redis://localhost:6379/1"
    )
    REDIS_HOST: str = os.getenv("REDIS_HOST", "localhost")
    REDIS_PORT: int = int(os.getenv("REDIS_PORT", "6379"))
    REDIS_PASSWORD: Optional[str] = os.getenv("REDIS_PASSWORD", "")
    REDIS_DB: int = int(os.getenv("REDIS_DB", "1"))
    REDIS_MAX_CONNECTIONS: int = 50
    
    # ============================================================
    # CORS Settings
    # ============================================================
    ALLOWED_ORIGINS: Union[str, List[str]] = Field(
        default=[
            "https://lexilingo.me",
            "https://www.lexilingo.me",
            "https://admin.lexilingo.me",
        ],
        validation_alias=AliasChoices("ALLOWED_ORIGINS", "CORS_ORIGINS"),
    )
    CORS_ALLOW_ORIGIN_REGEX: str = (
        r"https?://([a-zA-Z0-9-]+\.)*lexilingo\.me(:\d+)?"
    )

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
                return [origin.strip() for origin in v.split(',') if origin.strip()]
        return v

    @field_validator("DEBUG", mode="before")
    @classmethod
    def parse_debug(cls, v):
        """Accept common host DEBUG values without breaking app startup."""
        if isinstance(v, bool):
            return v
        raw = str(v or "").strip().lower()
        if raw in {"1", "true", "yes", "on", "debug"}:
            return True
        if raw in {"0", "false", "no", "off", "release", "prod", "production", ""}:
            return False
        return False

    @model_validator(mode="after")
    def validate_production_security(self):
        """Reject common insecure deployment settings."""
        if self.ENVIRONMENT != "production":
            return self

        if self.DEBUG:
            raise ValueError("DEBUG must be false when ENVIRONMENT=production")

        if self.MONGODB_TLS_ALLOW_INVALID_CERTIFICATES:
            raise ValueError("MongoDB invalid TLS certificates are not allowed in production")

        origins = self.ALLOWED_ORIGINS
        if isinstance(origins, str):
            origins = [origin.strip() for origin in origins.split(",") if origin.strip()]

        if "*" in origins:
            raise ValueError("Wildcard CORS origins are not allowed with credentials in production")

        if any("localhost" in origin or "127.0.0.1" in origin for origin in origins):
            raise ValueError("Localhost CORS origins are not allowed when ENVIRONMENT=production")

        if "devtunnels.ms" in self.CORS_ALLOW_ORIGIN_REGEX or "github.dev" in self.CORS_ALLOW_ORIGIN_REGEX:
            raise ValueError("Broad development tunnel CORS regex is not allowed in production")

        return self
    
    # ============================================================
    # API Keys (for external services)
    # ============================================================
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    HUGGINGFACE_API_KEY: str = os.getenv("HUGGINGFACE_API_KEY", "")
    
    # ============================================================
    # Ollama (Local LLM) Configuration
    # ============================================================
    OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
    OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "lexilingo-qwen3-1.7b")
    OLLAMA_TIMEOUT: int = int(os.getenv("OLLAMA_TIMEOUT", "60"))
    
    # ============================================================
    # Topic Chat LLM Configuration
    # ============================================================
    TOPIC_LLM_TEMPERATURE: float = float(os.getenv("TOPIC_LLM_TEMPERATURE", "0.7"))
    TOPIC_LLM_MAX_TOKENS: int = int(os.getenv("TOPIC_LLM_MAX_TOKENS", "512"))
    
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
    # Model Names (default = use base model on server)
    # ============================================================
    # Qwen3-1.7B - English NLP (grammar, fluency, vocabulary, tutor response)
    QWEN_MODEL_NAME: str = os.getenv("QWEN_MODEL_NAME", "")
    
    # LLaMA3-8B-VI - Vietnamese explanations (lazy load)
    LLAMA_MODEL_NAME: str = os.getenv("LLAMA_MODEL_NAME", "vilm/vinallama-7b-chat")
    
    # HuBERT - Pronunciation analysis
    HUBERT_MODEL_NAME: str = os.getenv("HUBERT_MODEL_NAME", "facebook/hubert-large-ls960-ft")
    HUBERT_DEVICE: str = os.getenv("HUBERT_DEVICE", "cpu")

    # ============================================================
    # STT / TTS Configuration
    # ============================================================
    # Faster-Whisper v3 - Speech-to-Text
    STT_MODEL_NAME: str = os.getenv("STT_MODEL_NAME", "large-v3")
    STT_DEVICE: str = os.getenv("STT_DEVICE", "cpu")
    STT_COMPUTE_TYPE: str = os.getenv("STT_COMPUTE_TYPE", "int8")
    STT_BEAM_SIZE: int = int(os.getenv("STT_BEAM_SIZE", "5"))
    STT_VAD: bool = os.getenv("STT_VAD", "true").lower() == "true"
    STT_LANGUAGE: str = os.getenv("STT_LANGUAGE", "en")
    
    # Piper VITS - Text-to-Speech
    TTS_MODEL_PATH: str = os.getenv("TTS_MODEL_PATH", "en_US-lessac-medium")
    TTS_CONFIG_PATH: str = os.getenv("TTS_CONFIG_PATH", "")
    TTS_SPEAKER_ID: int = int(os.getenv("TTS_SPEAKER_ID", "0"))
    TTS_VOICE: str = os.getenv("TTS_VOICE", "en_US-lessac-medium")

    # ============================================================
    # Knowledge Graph (KuzuDB) & Embeddings
    # ============================================================
    KUZU_DB_PATH: str = os.getenv(
        "KUZU_DB_PATH",
        os.path.join(os.path.dirname(__file__), "..", "..", "data", "kuzu")
    )
    EMBEDDING_MODEL: str = os.getenv(
        "EMBEDDING_MODEL",
        "sentence-transformers/all-MiniLM-L6-v2"
    )
    EMBEDDING_DEVICE: str = os.getenv("EMBEDDING_DEVICE", "cpu")
    
    # ============================================================
    # Rate Limiting
    # ============================================================
    RATE_LIMIT_ENABLED: bool = ENVIRONMENT == "production"
    RATE_LIMIT_PER_MINUTE: int = 60
    
    # ============================================================
    # Vercel Deployment Detection
    # ============================================================
    IS_VERCEL: bool = os.getenv("VERCEL", "").lower() == "1"
    

@lru_cache()
def get_settings() -> Settings:
    """
    Get cached settings instance.
    
    Similar to Flutter's GetIt singleton pattern.
    """
    return Settings()


# Global settings instance
settings = get_settings()
