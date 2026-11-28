"""Celery tasks behind error monitoring: flush the Redis buffer, mail digests, prune old counts."""

from __future__ import annotations

import asyncio
import logging

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db
from app.core.redis import RedisClient
from app.services import ops_errors

logger = logging.getLogger(__name__)


@celery_app.task(name="app.tasks.ops_errors.flush_error_buffer")
def flush_error_buffer_task() -> dict:
    return asyncio.run(_locked(ops_errors.FLUSH_LOCK_KEY, 55, _flush))


@celery_app.task(name="app.tasks.ops_errors.send_error_digest")
def send_error_digest_task() -> dict:
    return asyncio.run(_locked(ops_errors.DIGEST_LOCK_KEY, 240, _digest))


@celery_app.task(name="app.tasks.ops_errors.prune_error_counts")
def prune_error_counts_task() -> dict:
    return asyncio.run(_prune())


async def _locked(lock_key: str, ttl: int, work) -> dict:
    """Run `work(redis)` under a Redis NX lock so two beats never overlap."""
    if not RedisClient.is_connected():
        await RedisClient.connect()
    try:
        redis = await RedisClient.get_instance()
        if redis is None:
            return {"skipped": "redis unavailable"}
        if not await redis.set(lock_key, "1", nx=True, ex=ttl):
            return {"skipped": "locked"}
        try:
            return await work(redis)
        finally:
            await redis.delete(lock_key)
    finally:
        # asyncio.run() closes its loop on return; a client left in the singleton
        # stays bound to it and the next tick dies with "Event loop is closed".
        await RedisClient.close()
        await close_db()


async def _flush(redis) -> dict:
    async with AsyncSessionLocal() as db:
        result = await ops_errors.run_flush(db, redis)
    logger.info("Error buffer flushed: %s", result)
    return result


async def _digest(_redis) -> dict:
    async with AsyncSessionLocal() as db:
        return await ops_errors.run_digest(db)


async def _prune() -> dict:
    try:
        async with AsyncSessionLocal() as db:
            return {"deleted": await ops_errors.prune_counts(db)}
    finally:
        await close_db()
