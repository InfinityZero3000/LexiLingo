"""Celery tasks: finish translations for saved words, and export the private reference corpus."""

from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import UTC, datetime
from pathlib import Path

import httpx
from sqlalchemy import text

from app.core.celery_app import celery_app
from app.core.config import settings
from app.core.database import AsyncSessionLocal, close_db, engine
from app.services import reference_content
from app.services.vocabulary_translation import (
    GroqFatal,
    GroqRetryable,
    enrich_item,
    find_incomplete_ids,
)

logger = logging.getLogger(__name__)

MAX_RETRIES = 5
BACKOFF_BASE_S = 60
BACKOFF_CAP_S = 1800


def retry_countdown(retries: int, hint: float | None = None) -> int:
    """Exponential backoff 60s, 120s, ... capped at 30 min; Groq's own hint wins when longer."""
    backoff = min(BACKOFF_BASE_S * 2**retries, BACKOFF_CAP_S)
    return int(min(max(backoff, hint or 0), BACKOFF_CAP_S))


@celery_app.task(
    bind=True,
    name="app.tasks.vocabulary_enrichment.enrich_vocabulary_item",
    max_retries=MAX_RETRIES,
)
def enrich_vocabulary_item(self, item_id: str) -> dict:
    """Fill the missing translations of one vocabulary item; idempotent."""
    if not settings.VOCAB_AUTO_TRANSLATE_ENABLED:
        return {"status": "disabled"}
    try:
        status, hint = asyncio.run(_enrich_one(item_id))
    except Exception:  # noqa: BLE001 - a bad item must not poison the queue
        logger.exception("Vocabulary enrichment crashed for %s", item_id)
        return {"status": "failed"}
    if status not in ("retry", "partial"):
        return {"status": status}
    if self.request.retries >= self.max_retries:
        logger.warning("Vocabulary enrichment gave up on %s (%s); the sweep will retry later", item_id, status)
        return {"status": "gave_up"}
    raise self.retry(countdown=retry_countdown(self.request.retries, hint))


async def _enrich_one(item_id: str) -> tuple[str, float | None]:
    try:
        async with AsyncSessionLocal() as db:
            outcome = await enrich_item(db, uuid.UUID(item_id))
        return outcome.status, None
    except GroqRetryable as exc:
        logger.info("Groq not ready for %s: %s", item_id, exc)
        return "retry", exc.retry_after
    except GroqFatal as exc:
        logger.error("Vocabulary enrichment refused for %s: %s", item_id, exc)
        return "failed", None
    finally:
        await close_db()


@celery_app.task(name="app.tasks.vocabulary_enrichment.enrich_incomplete_vocabulary")
def enrich_incomplete_vocabulary() -> dict:
    """Enrich up to VOCAB_ENRICH_SWEEP_BATCH incomplete items, oldest first, one request at a time."""
    if not settings.VOCAB_AUTO_TRANSLATE_ENABLED:
        return {"status": "disabled"}
    return asyncio.run(
        _sweep(settings.VOCAB_ENRICH_SWEEP_BATCH, settings.VOCAB_ENRICH_DELAY_SECONDS)
    )


async def _sweep(limit: int, delay: float) -> dict:
    stats = {"candidates": 0, "enriched": 0, "partial": 0, "stopped": None}
    try:
        async with AsyncSessionLocal() as db:
            ids = await find_incomplete_ids(db, limit)
        stats["candidates"] = len(ids)
        async with httpx.AsyncClient() as client:
            for item_id in ids:
                try:
                    async with AsyncSessionLocal() as db:
                        outcome = await enrich_item(db, item_id, client)
                except (GroqRetryable, GroqFatal) as exc:
                    stats["stopped"] = str(exc)
                    break
                if outcome.status == "enriched":
                    stats["enriched"] += 1
                elif outcome.status == "partial":
                    stats["partial"] += 1
                if outcome.status in ("enriched", "partial") and delay:
                    await asyncio.sleep(delay)
        logger.info("Vocabulary enrichment sweep: %s", stats)
        return stats
    finally:
        await close_db()


@celery_app.task(name="app.tasks.vocabulary_enrichment.export_reference_corpus")
def export_reference_corpus() -> dict:
    """Write the reference corpus JSON to REFERENCE_CORPUS_DIR (private; never the repo checkout)."""
    target = (settings.REFERENCE_CORPUS_DIR or "").strip()
    if not target:
        logger.info("REFERENCE_CORPUS_DIR is not set, skipping reference corpus export")
        return {"status": "skipped"}
    return asyncio.run(_export(Path(target)))


async def _export(root: Path) -> dict:
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SET TRANSACTION READ ONLY"))
            payload = await reference_content.fetch_reference(conn)
            await conn.rollback()
        files = reference_content.build_files(payload)
        counts = {table: len(rows) for table, rows in payload.items()}
        meta = {
            "format": reference_content.FILE_FORMAT,
            "generated_at": datetime.now(UTC).isoformat(),
            "counts": counts,
        }
        written = reference_content.publish_export(files, root, meta)
        logger.info("Reference corpus exported to %s: %s", root, counts)
        return {"status": "exported", "counts": counts, "entries": written}
    finally:
        await close_db()
