"""
Configuration management for LexiLingo Backend

Environment-aware settings following Clean Architecture principles
Similar to Flutter's environment configuration
"""

import os
import json
import re
from datetime import date
from pathlib import Path
from typing import List, Optional, Union
from dotenv import dotenv_values
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import AliasChoices, Field, field_validator, model_validator
from functools import lru_cache
from urllib.parse import urlparse

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent

# The six internal routes read their admin key with os.getenv, but pydantic's
# env_file only ever populates Settings — os.environ stays empty. Under Docker
# compose passes the real variables so that works; running uvicorn directly it
# did not, and those routes answered 503 with a .env sitting right there.
#
# Only this one key is exported, not the whole file. A blanket load_dotenv()
# leaks every setting into os.environ, which silently defeats the config tests
# that pass _env_file=None to prove a setting is unset — one of them exists to
# guarantee production refuses to enable the ETL with no dataset pinned.
#
# A real container variable always wins: we only fill a gap, never overwrite.
if "AI_ADMIN_API_KEY" not in os.environ:
    _env_path = PROJECT_ROOT / ".env"
    if _env_path.is_file():
        _admin_key = (dotenv_values(_env_path).get("AI_ADMIN_API_KEY") or "").strip()
        if _admin_key:
            os.environ["AI_ADMIN_API_KEY"] = _admin_key


class Settings(BaseSettings):
    """Application settings."""

    model_config = SettingsConfigDict(
        env_file=str(PROJECT_ROOT / ".env"),
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
    # Sparse Learner State (safe rollout; disabled by default)
    # ============================================================
    LEARNER_STATE_MODE: str = Field(default="off", pattern=r"^(off|shadow|read|primary)$")
    LEARNER_STATE_API_URL: str = "http://backend-service:8000/api/v1/internal"
    LEARNER_STATE_INTERNAL_TOKEN: str = ""
    LEARNER_STATE_INTERNAL_AUDIENCE: str = "lexilingo-backend"
    LEARNER_STATE_DEADLINE_MS: int = Field(default=40, ge=5, le=500)
    LEARNER_STATE_CONNECT_TIMEOUT_MS: int = Field(default=10, ge=1, le=100)
    LEARNER_STATE_POOL_TIMEOUT_MS: int = Field(default=5, ge=1, le=100)
    LEARNER_STATE_MAX_INFLIGHT: int = Field(default=100, ge=1, le=1000)
    LEARNER_STATE_CIRCUIT_FAILURES: int = Field(default=5, ge=1, le=100)
    LEARNER_STATE_CIRCUIT_RESET_SECONDS: float = Field(default=30.0, ge=0.1, le=600.0)
    KUZU_USER_MASTERY_WRITES_ENABLED: bool = True

    # ============================================================
    # Internal CEFR Content Agent
    # ============================================================
    CONTENT_AGENT_SERVICE_TOKEN: str = os.getenv(
        "CONTENT_AGENT_SERVICE_TOKEN",
        "",
    )
    CONTENT_AGENT_TTL_SECONDS: int = int(
        os.getenv("CONTENT_AGENT_TTL_SECONDS", "3600")
    )
    CONTENT_AGENT_MAX_RECORDS: int = int(
        os.getenv("CONTENT_AGENT_MAX_RECORDS", "20000")
    )
    CONTENT_AGENT_MAX_BATCH_RECORDS: int = int(
        os.getenv("CONTENT_AGENT_MAX_BATCH_RECORDS", "2000")
    )
    CONTENT_AGENT_ALLOW_LOCAL_STORE: bool = os.getenv(
        "CONTENT_AGENT_ALLOW_LOCAL_STORE",
        "false" if ENVIRONMENT == "production" else "true",
    ).lower() == "true"

    # Ollama is not deployed anywhere yet: with it on, every chat warm-up
    # dials a host that is not listening and logs a connection error.
    OLLAMA_ENABLED: bool = Field(default=False)

    TRACE_CAG_EXTERNAL_ENABLED: bool = False
    TRACE_CAG_SERVICE_TOKEN_HASH: str = ""
    TRACE_CAG_PREVIOUS_TOKEN_HASH: str = ""
    TRACE_CAG_PREVIOUS_TOKEN_VALID_UNTIL: str = ""

    # ============================================================
    # Licensed Content ETL
    # ============================================================
    CONTENT_ETL_ENABLED: bool = Field(default=False)
    CONTENT_ETL_STORAGE_ROOT: str = Field(default="/data/content-etl")
    CONTENT_ETL_HTTP_TIMEOUT_SECONDS: int = Field(default=60, gt=0)
    CONTENT_ETL_MAX_DOWNLOAD_BYTES: int = Field(default=1073741824, gt=0)
    CONTENT_ETL_MAX_QUARANTINE_RATIO: float = Field(default=0.02, ge=0.0, le=1.0)
    CONTENT_ETL_USER_AGENT: str = Field(default="LexiLingo-ETL/1.0", min_length=1)
    # Empty means "dataset not configured" — pin it together with its checksum.
    CONTENT_ETL_OEWN_VERSION: str = Field(default="")
    CONTENT_ETL_OEWN_SHA256: str = Field(default="")
    CONTENT_ETL_CMU_REF: str = Field(default="")
    CONTENT_ETL_CMU_SHA256: str = Field(default="")
    CONTENT_ETL_CEFR_J_REF: str = Field(default="")
    CONTENT_ETL_CEFR_J_PATH: str = Field(
        default="cefrj-vocabulary-profile-1.5.csv"
    )
    CONTENT_ETL_CEFR_J_SHA256: str = Field(default="")
    CONTENT_ETL_WIKIDATA_SNAPSHOT: str = Field(default="")
    CONTENT_ETL_TATOEBA_RELEASE: str = Field(default="")
    CONTENT_ETL_LIBRISPEECH_RELEASE: str = Field(default="")
    CONTENT_ETL_COMMON_VOICE_RELEASE: str = Field(default="")
    
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
    CORS_ALLOW_PRIVATE_NETWORK: bool = True

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
        if self.LEARNER_STATE_MODE != "off":
            if len(self.LEARNER_STATE_INTERNAL_TOKEN) < 32:
                raise ValueError(
                    "LEARNER_STATE_INTERNAL_TOKEN must be at least 32 characters when enabled"
                )
            if not self.LEARNER_STATE_INTERNAL_AUDIENCE.strip():
                raise ValueError("LEARNER_STATE_INTERNAL_AUDIENCE must not be empty")
            if self.ENVIRONMENT == "production":
                parsed = urlparse(self.LEARNER_STATE_API_URL)
                private_service = parsed.hostname == "backend-service" or bool(
                    parsed.hostname and parsed.hostname.endswith(".internal")
                )
                if parsed.scheme != "https" and not private_service:
                    raise ValueError(
                        "LEARNER_STATE_API_URL must use HTTPS or private service DNS in production"
                    )
        if self.ENVIRONMENT != "production":
            return self

        if self.DEBUG:
            raise ValueError("DEBUG must be false when ENVIRONMENT=production")

        if (
            not self.SECRET_KEY
            or self.SECRET_KEY.lower().startswith("your_")
            or len(self.SECRET_KEY) < 32
        ):
            raise ValueError(
                "SECRET_KEY must be a random string of at least 32 characters in production"
            )

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

        if self.CONTENT_ETL_ENABLED:
            self._validate_production_etl_pins()

        return self

    def _validate_production_etl_pins(self) -> None:
        moving_refs = {"head", "latest", "main", "master", "stable", "trunk"}

        def require_non_moving(name: str, value: str) -> None:
            if not value.strip() or value.strip().lower() in moving_refs:
                raise ValueError(f"{name} must use a pinned immutable version")

        def validate_dataset(
            ref_name: str,
            ref_value: str,
            sha_name: str,
            sha_value: str,
            *,
            commit_sha: bool,
        ) -> bool:
            """A dataset is either fully pinned or not configured at all.

            Requiring every dataset would make ETL unusable for an operator who
            has not licensed one of them (CEFR-J is commercial): a half-pinned
            dataset still fails, and an unpinned one is refused at sync time by
            `sources.build_source_sync_spec`, so nothing unverified is ingested.
            """
            if not ref_value.strip() and not sha_value.strip():
                return False
            require_non_moving(ref_name, ref_value)
            if commit_sha and re.fullmatch(r"[a-fA-F0-9]{40}", ref_value) is None:
                raise ValueError(
                    f"{ref_name} must use a pinned 40-character commit SHA"
                )
            if re.fullmatch(r"[a-f0-9]{64}", sha_value) is None:
                raise ValueError(f"{sha_name} must use a lowercase SHA-256 checksum")
            return True

        configured = [
            validate_dataset(
                "CONTENT_ETL_OEWN_VERSION",
                self.CONTENT_ETL_OEWN_VERSION,
                "CONTENT_ETL_OEWN_SHA256",
                self.CONTENT_ETL_OEWN_SHA256,
                commit_sha=False,
            ),
            validate_dataset(
                "CONTENT_ETL_CMU_REF",
                self.CONTENT_ETL_CMU_REF,
                "CONTENT_ETL_CMU_SHA256",
                self.CONTENT_ETL_CMU_SHA256,
                commit_sha=True,
            ),
            validate_dataset(
                "CONTENT_ETL_CEFR_J_REF",
                self.CONTENT_ETL_CEFR_J_REF,
                "CONTENT_ETL_CEFR_J_SHA256",
                self.CONTENT_ETL_CEFR_J_SHA256,
                commit_sha=True,
            ),
        ]
        if not any(configured) and not self.CONTENT_ETL_WIKIDATA_SNAPSHOT:
            raise ValueError(
                "CONTENT_ETL_ENABLED requires at least one pinned dataset "
                "(OEWN, CMUdict, CEFR-J or a Wikidata snapshot)"
            )

        if self.CONTENT_ETL_WIKIDATA_SNAPSHOT:
            require_non_moving(
                "CONTENT_ETL_WIKIDATA_SNAPSHOT",
                self.CONTENT_ETL_WIKIDATA_SNAPSHOT,
            )
            try:
                date.fromisoformat(self.CONTENT_ETL_WIKIDATA_SNAPSHOT)
            except ValueError as exc:
                raise ValueError(
                    "CONTENT_ETL_WIKIDATA_SNAPSHOT must use a pinned YYYY-MM-DD date"
                ) from exc

        for name, value in (
            ("CONTENT_ETL_TATOEBA_RELEASE", self.CONTENT_ETL_TATOEBA_RELEASE),
            (
                "CONTENT_ETL_LIBRISPEECH_RELEASE",
                self.CONTENT_ETL_LIBRISPEECH_RELEASE,
            ),
            (
                "CONTENT_ETL_COMMON_VOICE_RELEASE",
                self.CONTENT_ETL_COMMON_VOICE_RELEASE,
            ),
        ):
            if value:
                require_non_moving(name, value)
    
    # ============================================================
    # JWT shared secret (must match backend-service SECRET_KEY)
    # ============================================================
    SECRET_KEY: str = os.getenv("SECRET_KEY", "")

    # ============================================================
    # API Keys (for external services)
    # ============================================================
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    HUGGINGFACE_API_KEY: str = os.getenv("HUGGINGFACE_API_KEY", "")
    
    # ============================================================
    # Ollama (Local LLM) Configuration
    # ============================================================
    USE_OLLAMA: bool = os.getenv("USE_OLLAMA", "false").lower() == "true"
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
    SENTRY_DSN: str = os.getenv("SENTRY_DSN", "")
    LOG_AI_INTERACTIONS: bool = True
    LOG_PERFORMANCE_METRICS: bool = True
    
    # ============================================================
    # AI Model Configuration (for DL-Model-Support integration)
    # ============================================================
    AI_MODEL_API_URL: str = os.getenv("AI_MODEL_API_URL", "")
    AI_MODEL_API_KEY: Optional[str] = os.getenv("AI_MODEL_API_KEY")
    AI_MODEL_TIMEOUT: int = 30

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
    # Legacy short-clip STT compatibility. Realtime settings live in
    # api.services.stt.config.STTConfig.
    STT_MODEL_NAME: str = os.getenv("STT_VERIFY_MODEL", "base.en")
    STT_DEVICE: str = os.getenv("STT_DEVICE", "cpu")
    STT_COMPUTE_TYPE: str = os.getenv("STT_COMPUTE_TYPE", "int8")
    STT_BEAM_SIZE: int = int(os.getenv("STT_BEAM_SIZE", "1"))
    STT_VAD: bool = os.getenv("STT_VAD", "true").lower() == "true"
    STT_LANGUAGE: str = os.getenv("STT_LANGUAGE", "en")
    
    # Piper VITS - Text-to-Speech
    # Accept PIPER_MODEL_PATH as alias for TTS_MODEL_PATH
    TTS_MODEL_PATH: str = (
        os.getenv("TTS_MODEL_PATH")
        or os.getenv("PIPER_MODEL_PATH", "en_US-lessac-medium")
    )
    TTS_CONFIG_PATH: str = os.getenv("TTS_CONFIG_PATH", "")
    TTS_SPEAKER_ID: int = int(os.getenv("TTS_SPEAKER_ID", "0"))
    TTS_VOICE: str = os.getenv("TTS_VOICE", "en_US-lessac-medium")
    TTS_INTRA_OP_THREADS: int = Field(default=4, ge=0, le=16)
    VOICE_DUPLEX_ENABLED: bool = False

    # ============================================================
    # Knowledge Graph (KuzuDB) & Embeddings
    # ============================================================
    KUZU_DB_PATH: str = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "..",
            "..",
            os.getenv("KUZU_DB_PATH", "data/kuzu_runtime.db"),
        )
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
