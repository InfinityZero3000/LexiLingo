"""
Core module initialization.
"""
from .config import settings
from .database import get_database, mongodb_manager
from .logging_config import logger

__all__ = [
    "settings",
    "get_database",
    "mongodb_manager",
    "logger",
]

