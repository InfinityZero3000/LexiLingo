"""Celery task: Word of the Day push notification at 08:00 UTC."""

from __future__ import annotations

import asyncio

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db


@celery_app.task(name="app.tasks.word_of_day.send_word_of_day")
def send_word_of_day() -> dict:
    return asyncio.run(_with_db_cleanup(_run()))


async def _with_db_cleanup(coro):
    try:
        return await coro
    finally:
        await close_db()


async def _run() -> dict:
    from app.tasks.content_prefetch import send_word_of_day_notification

    async with AsyncSessionLocal() as db:
        return await send_word_of_day_notification(db)
