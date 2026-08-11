"""Celery tasks: scheduled content prefetch (news / YouTube / podcasts)."""

from __future__ import annotations

import asyncio

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db


@celery_app.task(name="app.tasks.content_prefetch_schedule.prefetch_news")
def prefetch_news_task() -> dict:
    return asyncio.run(_with_db_cleanup(_run_news()))


@celery_app.task(name="app.tasks.content_prefetch_schedule.prefetch_youtube")
def prefetch_youtube_task() -> dict:
    return asyncio.run(_with_db_cleanup(_run_youtube()))


@celery_app.task(name="app.tasks.content_prefetch_schedule.prefetch_podcasts")
def prefetch_podcasts_task() -> dict:
    return asyncio.run(_with_db_cleanup(_run_podcasts()))


async def _with_db_cleanup(coro):
    try:
        return await coro
    finally:
        await close_db()


async def _run_news() -> dict:
    from app.tasks.content_prefetch import prefetch_news

    async with AsyncSessionLocal() as db:
        return await prefetch_news(db)


async def _run_youtube() -> dict:
    from app.tasks.content_prefetch import prefetch_youtube

    async with AsyncSessionLocal() as db:
        return await prefetch_youtube(db)


async def _run_podcasts() -> dict:
    from app.tasks.content_prefetch import prefetch_podcasts

    async with AsyncSessionLocal() as db:
        return await prefetch_podcasts(db)
