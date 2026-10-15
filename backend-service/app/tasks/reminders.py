"""Celery tasks for FSRS reminders."""

import asyncio
import logging
from datetime import datetime, timezone

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db
from app.services.reminder_service import ReminderService

logger = logging.getLogger(__name__)


@celery_app.task(name="app.tasks.reminders.scan_fsrs_reminders")
def scan_fsrs_reminders() -> dict:
    """Scan due reminder preferences and dispatch configured channels."""
    return asyncio.run(_with_db_cleanup(_scan_fsrs_reminders()))


async def _with_db_cleanup(coro):
    try:
        return await coro
    finally:
        await close_db()


async def _scan_fsrs_reminders() -> dict:
    async with AsyncSessionLocal() as db:
        result = await ReminderService().scan_due_preferences(
            db,
            now_utc=datetime.now(timezone.utc),
        )
        await db.commit()
        logger.info("FSRS reminder scan result: %s", result)
        return result
