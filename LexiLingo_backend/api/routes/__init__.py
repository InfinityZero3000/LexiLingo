"""
Routes module initialization

Export all route routers for main.py
"""

from api.routes.health import router as health_router
from api.routes.ai import router as ai_router
from api.routes.chat import router as chat_router
from api.routes.user import router as user_router

__all__ = [
    "health_router",
    "ai_router",
    "chat_router",
    "user_router",
]
