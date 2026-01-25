"""
API Routes

Import all routers here
"""

from app.routes.health import router as health_router
from app.routes.auth import router as auth_router
from app.routes.users import router as users_router
from app.routes.courses import router as courses_router
from app.routes.progress import router as progress_router

__all__ = [
    "health_router",
    "auth_router",
    "users_router",
    "courses_router",
    "progress_router",
]
