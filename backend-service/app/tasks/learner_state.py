"""Celery maintenance tasks for learner state."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import asdict
from datetime import UTC, datetime

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db
from app.services.learner_state import cleanup_observation_events

logger = logging.getLogger(__name__)


@celery_app.task(name="app.tasks.learner_state.cleanup_learner_observations")
def cleanup_learner_observations() -> dict:
    return asyncio.run(_cleanup_learner_observations())


async def _cleanup_learner_observations() -> dict:
    try:
        async with AsyncSessionLocal() as db:
            cleanup = await cleanup_observation_events(
                db,
                now=datetime.now(UTC),
                dry_run=False,
            )
            await db.commit()
        result = {"dry_run": False, **asdict(cleanup)}
        logger.info("Learner observation cleanup result: %s", result)
        return result
    finally:
        # Celery creates a fresh event loop for each asyncio.run() invocation.
        await close_db()
