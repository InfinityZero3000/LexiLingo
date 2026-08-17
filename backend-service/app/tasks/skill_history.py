"""Celery maintenance tasks for skill measurement data."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import asdict
from datetime import UTC, datetime

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db
from app.services.skill_history_service import (
    prune_exercise_attempts,
    snapshot_skill_scores,
)

logger = logging.getLogger(__name__)


@celery_app.task(name="app.tasks.skill_history.prune_exercise_attempts")
def prune_exercise_attempts_task() -> dict:
    return asyncio.run(_prune_exercise_attempts())


async def _prune_exercise_attempts() -> dict:
    try:
        async with AsyncSessionLocal() as db:
            result = await prune_exercise_attempts(db, now=datetime.now(UTC))
        payload = asdict(result) | {"cutoff": result.cutoff.isoformat()}
        logger.info("Exercise attempt prune result: %s", payload)
        return payload
    finally:
        # Celery creates a fresh event loop for each asyncio.run() invocation.
        await close_db()


@celery_app.task(name="app.tasks.skill_history.snapshot_skill_scores")
def snapshot_skill_scores_task() -> dict:
    return asyncio.run(_snapshot_skill_scores())


async def _snapshot_skill_scores() -> dict:
    try:
        async with AsyncSessionLocal() as db:
            result = await snapshot_skill_scores(db, now=datetime.now(UTC))
        logger.info("Skill score snapshot result: %s", result)
        return result
    finally:
        await close_db()
