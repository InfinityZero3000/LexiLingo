"""
Thin helpers for reading typed values from environment variables.
No dependencies on other trace_cag modules.
"""

import os


def _env_flag(name: str, default: bool = False) -> bool:
    raw = str(os.getenv(name, "1" if default else "0")).strip().lower()
    return raw in {"1", "true", "yes", "on"}


def kg_context_v2() -> bool:
    """KG_CONTEXT_V2 (default on): the 2026-11-11 fixes to what a KG concept becomes in the prompt and to how a named concept ranks.

    Off restores the earlier behaviour exactly. Research harnesses that must reproduce a registered result pin it off
    (docs/TRACE_CAG.md 5.7.13); the product leaves it on.
    """
    return _env_flag("KG_CONTEXT_V2", True)


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


def _clip01(value: float) -> float:
    return max(0.0, min(1.0, value))
