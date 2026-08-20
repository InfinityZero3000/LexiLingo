"""Celery maintenance tasks for authentication tokens."""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db
from app.models.user import RefreshToken

logger = logging.getLogger(__name__)

# A spent token is kept this long so a reuse attempt still lands on a row we
# could inspect; after that it is only rows.
SPENT_TOKEN_GRACE = timedelta(days=1)


async def prune_refresh_tokens(
    db: AsyncSession, *, now: datetime | None = None
) -> int:
    """Delete refresh tokens that can never authenticate again.

    Rotation writes one row per refresh, so without this the table only grows.
    """
    now = now or datetime.now(UTC)
    result = await db.execute(
        delete(RefreshToken).where(
            or_(
                RefreshToken.expires_at < now,
                (RefreshToken.is_used.is_(True) | RefreshToken.is_revoked.is_(True))
                & (RefreshToken.created_at < now - SPENT_TOKEN_GRACE),
            )
        )
    )
    await db.commit()
    return result.rowcount or 0


@celery_app.task(name="app.tasks.auth_tokens.prune_refresh_tokens")
def prune_refresh_tokens_task() -> dict:
    return asyncio.run(_prune_refresh_tokens())


async def _prune_refresh_tokens() -> dict:
    try:
        async with AsyncSessionLocal() as db:
            deleted = await prune_refresh_tokens(db)
        logger.info("Pruned %s refresh tokens", deleted)
        return {"deleted": deleted}
    finally:
        # Celery creates a fresh event loop for each asyncio.run() invocation.
        await close_db()
