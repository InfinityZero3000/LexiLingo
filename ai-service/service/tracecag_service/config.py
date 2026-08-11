"""Configuration for the portable TRACE-CAG service wrapper."""

from __future__ import annotations

from dataclasses import dataclass
import os


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


@dataclass(frozen=True)
class TraceCAGServiceConfig:
    """Runtime knobs that are safe to carry across projects."""

    service_name: str = "tracecag-service"
    version: str = "0.1.0"
    timeout_seconds: float = 30.0
    max_concurrency: int = 4
    default_session_id: str = "tracecag-session"
    include_raw_state_by_default: bool = False
    strict_validation: bool = True

    @classmethod
    def from_env(cls, prefix: str = "TRACECAG_SERVICE_") -> "TraceCAGServiceConfig":
        """Build config from environment variables without requiring settings.py."""

        return cls(
            service_name=os.getenv(f"{prefix}NAME", cls.service_name),
            version=os.getenv(f"{prefix}VERSION", cls.version),
            timeout_seconds=_env_float(f"{prefix}TIMEOUT_SECONDS", cls.timeout_seconds),
            max_concurrency=max(1, _env_int(f"{prefix}MAX_CONCURRENCY", cls.max_concurrency)),
            default_session_id=os.getenv(
                f"{prefix}DEFAULT_SESSION_ID",
                cls.default_session_id,
            ),
            include_raw_state_by_default=_env_bool(
                f"{prefix}INCLUDE_RAW_STATE",
                cls.include_raw_state_by_default,
            ),
            strict_validation=_env_bool(
                f"{prefix}STRICT_VALIDATION",
                cls.strict_validation,
            ),
        )
