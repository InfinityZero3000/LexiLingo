"""Keep fabricated data out of any database real people use.

Every script that invents users or activity calls ``require_sandbox`` first.
A host name alone proves nothing (production's database is also reached as
``postgres``, and a tunnel makes it ``localhost``), so three things must agree.
"""
from __future__ import annotations

import os

from sqlalchemy import func, select
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.user import User

_LOOPBACK = {"localhost", "127.0.0.1", "::1"}
# Domains nobody can own, plus the ones this repo's seeds use.
_SANDBOX_SUFFIXES = ("@example.com", ".example.com", "@lexilingo.test", "@lexilingo.dev", ".invalid")
# A developer's own sign-ins. More than this and the database is not a sandbox.
MAX_REAL_ACCOUNTS = 3


class NotASandbox(SystemExit):
    pass


def check_environment(database_url: object) -> None:
    if settings.is_production:
        raise NotASandbox("Refusing to write mock data: APP_ENV=production.")
    host = make_url(database_url).host
    allowed = os.getenv("ALLOW_MOCK_SEED_HOST")
    if host is not None and host not in _LOOPBACK and host != allowed:
        raise NotASandbox(
            f"Refusing to write mock data to database host '{host}'. For a staging "
            f"database, set ALLOW_MOCK_SEED_HOST={host}."
        )


def check_redis() -> None:
    """The Redis URL gets the same host rule as the database."""
    host = make_url(settings.REDIS_URL).host if settings.REDIS_URL else None
    if host is not None and host not in _LOOPBACK and host != os.getenv("ALLOW_MOCK_SEED_HOST"):
        raise NotASandbox(f"Refusing to write mock data to Redis host '{host}'.")


async def require_sandbox(db: AsyncSession) -> None:
    check_environment(db.get_bind().url)
    sandbox = [User.email.ilike(f"%{suffix}") for suffix in _SANDBOX_SUFFIXES]
    real = await db.scalar(select(func.count()).select_from(User).where(*[~clause for clause in sandbox]))
    if (real or 0) > MAX_REAL_ACCOUNTS:
        raise NotASandbox(
            f"Refusing to write mock data: this database holds {real} real-looking accounts."
        )
