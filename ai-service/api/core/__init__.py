"""
Core module initialization.
"""
from .config import settings
from .logging_config import logger

__all__ = [
    "settings",
    "logger",
]

