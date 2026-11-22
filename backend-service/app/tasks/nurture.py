"""Celery tasks: activation nudges, streak-at-risk email and the weekly summary."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db
from app.services import nurture_service

logger = logging.getLogger(__name__)


async def _run(work: Callable[[AsyncSession], Awaitable[dict]]) -> dict:
    try:
        async with AsyncSessionLocal() as db:
            result = await work(db)
        logger.info("nurture result: %s", result)
        return result
    finally:
        await close_db()


async def _activation(db: AsyncSession) -> dict:
    return {
        kind: await nurture_service.run_activation(db, kind)
        for kind in (nurture_service.D1, nurture_service.D3)
    }


@celery_app.task(name="app.tasks.nurture.send_activation_nudges")
def send_activation_nudges() -> dict:
    return asyncio.run(_run(_activation))


@celery_app.task(name="app.tasks.nurture.send_streak_risk_emails")
def send_streak_risk_emails() -> dict:
    return asyncio.run(_run(nurture_service.run_streak_risk))


@celery_app.task(name="app.tasks.nurture.send_weekly_summaries")
def send_weekly_summaries() -> dict:
    return asyncio.run(_run(nurture_service.run_weekly))
