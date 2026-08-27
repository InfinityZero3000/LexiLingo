"""Event Worker — drains the content_interaction Redis Stream and
recomputes each affected user's recommender insights off the request path.

    content_interaction event
            │  XADD          (app.routes.product_events)
            ▼
    Redis Stream: rec:events:content_interaction
            │  XREADGROUP, drained on a schedule rather than a standing
            │  process — reuses the existing Celery worker/beat, no new
            │  deployment unit.
            ▼
    Event Worker (this module)
            │  compute_insights() — the exact function build_profile()
            │  already falls back to synchronously, no separate math.
            ▼
    Redis: rec:insights:{user_id} — read by build_profile() first; a miss
                                     (new user, worker lag, cache expiry)
                                     just recomputes synchronously.

A drain that hits a Redis outage or an empty stream is a no-op, not an
error — the request-path fallback in recommendation_service.py is what
keeps recommendations correct if this task stops running entirely.
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid

from app.core.celery_app import celery_app
from app.core.config import settings
from app.core.database import AsyncSessionLocal, close_db
from app.core.redis import RedisClient, get_redis
from app.services.feature_processor import (
    INSIGHTS_CACHE_PREFIX,
    INSIGHTS_CACHE_TTL_SECONDS,
    STREAM_KEY,
    compute_insights,
    prune_product_events,
)
from app.services.recommendation_service import get_assessed_level

logger = logging.getLogger(__name__)

CONSUMER_GROUP = "rec-worker"
CONSUMER_NAME = "drain"

# A message delivered to a consumer that died before acking sits in the
# pending list forever — XREADGROUP ">" only ever returns never-delivered
# messages. Reclaim anything idle longer than this on the next tick.
STALE_PENDING_MS = 60_000


@celery_app.task(name="app.tasks.event_worker.drain_content_interaction_stream")
def drain_content_interaction_stream_task() -> dict:
    return asyncio.run(_run())


@celery_app.task(name="app.tasks.event_worker.prune_product_events")
def prune_product_events_task() -> dict:
    return asyncio.run(_prune_product_events())


async def _prune_product_events() -> dict:
    try:
        async with AsyncSessionLocal() as db:
            result = await prune_product_events(db)
        payload = {"deleted": result.deleted, "cutoff": result.cutoff.isoformat()}
        logger.info("Product event prune result: %s", payload)
        return payload
    finally:
        await close_db()


async def _run() -> dict:
    """Task entrypoint: bootstrap this process's Redis connection (a Celery
    worker never runs the FastAPI lifespan that normally does this), then
    drain. Kept separate from _drain() so tests can exercise the drain logic
    against a fake client without touching RedisClient's real connect path."""
    if not RedisClient.is_connected():
        await RedisClient.connect()
    return await _drain()


async def _drain() -> dict:
    try:
        client = await get_redis()
        if client is None:
            return {"drained": 0, "skipped": "redis unavailable"}

        await _ensure_group(client)

        batch_size = settings.EVENT_WORKER_DRAIN_BATCH_SIZE
        reclaimed = await _reclaim_stale(client, batch_size)

        entries = await client.xreadgroup(
            CONSUMER_GROUP,
            CONSUMER_NAME,
            {STREAM_KEY: ">"},
            count=batch_size,
        )

        message_ids: list[str] = []
        user_ids: set[str] = set()
        for message_id, fields in reclaimed:
            message_ids.append(message_id)
            user_id = (fields or {}).get("user_id")
            if user_id:
                user_ids.add(user_id)
        for _stream_key, messages in entries or []:
            for message_id, fields in messages:
                message_ids.append(message_id)
                user_id = fields.get("user_id")
                if user_id:
                    user_ids.add(user_id)

        if not message_ids:
            return {"drained": 0}

        recomputed = 0
        async with AsyncSessionLocal() as db:
            for user_id in user_ids:
                try:
                    await _recompute_one(db, client, user_id)
                    recomputed += 1
                except Exception as exc:
                    # One user's bad data (unparseable id, DB error) must not
                    # block the rest of the batch or jam the stream forever.
                    logger.warning(
                        "event worker: recompute failed for %s: %s", user_id, exc
                    )

        await client.xack(STREAM_KEY, CONSUMER_GROUP, *message_ids)

        return {
            "drained": len(message_ids),
            "reclaimed": len(reclaimed),
            "users_recomputed": recomputed,
        }
    finally:
        # Celery creates a fresh event loop for each asyncio.run() invocation.
        await close_db()


async def _reclaim_stale(client, count: int) -> list[tuple]:
    """Take back messages a previous run delivered but never acked.

    Without this a worker killed mid-drain (deploy, OOM, crash) leaves those
    messages pending forever: XREADGROUP ">" only returns messages never
    delivered to anyone. A stuck message is not fatal — the request path
    recomputes synchronously on a cache miss — but it means that user's
    insights silently stop refreshing until something else touches them.
    """
    try:
        _cursor, messages, *_ = await client.xautoclaim(
            STREAM_KEY,
            CONSUMER_GROUP,
            CONSUMER_NAME,
            min_idle_time=STALE_PENDING_MS,
            start_id="0-0",
            count=count,
        )
        if messages:
            logger.info("event worker: reclaimed %d stale message(s)", len(messages))
        return list(messages or [])
    except Exception as exc:
        # A reclaim failure must not stop the normal drain.
        logger.warning("event worker: xautoclaim failed: %s", exc)
        return []


async def _recompute_one(db, client, user_id_str: str) -> None:
    user_id = uuid.UUID(user_id_str)
    level = await get_assessed_level(db, user_id)
    insights = await compute_insights(db, user_id, level=level)
    await client.setex(
        f"{INSIGHTS_CACHE_PREFIX}{user_id}",
        INSIGHTS_CACHE_TTL_SECONDS,
        json.dumps(insights),
    )


async def _ensure_group(client) -> None:
    try:
        # id="0", not "$" — if events land before this group's first-ever
        # creation (worker never ran yet, or its group was deleted), start
        # from the beginning of the stream so nothing already queued is
        # silently skipped.
        await client.xgroup_create(STREAM_KEY, CONSUMER_GROUP, id="0", mkstream=True)
    except Exception as exc:
        if "BUSYGROUP" not in str(exc):
            raise
