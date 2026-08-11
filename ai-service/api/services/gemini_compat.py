"""Compatibility helpers for the legacy Gemini SDK."""

from __future__ import annotations

import importlib
import warnings
from types import ModuleType


def import_generativeai() -> ModuleType:
    """Import google.generativeai without surfacing its package deprecation warning."""
    with warnings.catch_warnings():
        warnings.filterwarnings(
            "ignore",
            message=r"\s*All support for the `google\.generativeai` package has ended.*",
            category=FutureWarning,
        )
        return importlib.import_module("google.generativeai")
