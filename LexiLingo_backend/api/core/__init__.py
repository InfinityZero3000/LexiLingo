"""
Core module initialization
"""

from api.core.config import settings, get_settings
from api.core.database import mongodb_manager, get_database

__all__ = [
    "settings",
    "get_settings",
    "mongodb_manager",
    "get_database",
]
