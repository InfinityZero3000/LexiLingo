"""Lightweight visibility for aging content_etl snapshots.

Ingestion (checksum-verified download + normalize) is a deliberate,
manual CLI step (see cli.py) — nothing here re-triggers it. This only
makes it observable when an active snapshot has silently gone stale
because an operator forgot to refresh it.

Note: SourceManifest.retrieved_at is a deterministic value derived from
the source/version/checksum (see pipeline.py::_deterministic_retrieved_at),
not a real wall-clock timestamp — it must not be used for staleness. The
active pointer file's mtime (set when the snapshot was actually activated)
is the real signal.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from pathlib import Path

from api.core.config import settings

logger = logging.getLogger(__name__)

DEFAULT_MAX_AGE_DAYS = 30
CHECK_INTERVAL_SECONDS = 3600


def stale_active_sources(max_age_days: int = DEFAULT_MAX_AGE_DAYS) -> list[str]:
    """Return source names whose active snapshot pointer is older than max_age_days."""
    active_dir = Path(settings.CONTENT_ETL_STORAGE_ROOT) / "active"
    if not active_dir.is_dir():
        return []

    now = datetime.now(timezone.utc)
    stale: list[str] = []
    for pointer in sorted(active_dir.glob("*.json")):
        age_days = (now.timestamp() - pointer.stat().st_mtime) / 86400
        if age_days > max_age_days:
            stale.append(pointer.stem)
    return stale


async def run_staleness_loop(max_age_days: int = DEFAULT_MAX_AGE_DAYS) -> None:
    from api.services.telemetry import get_telemetry

    while True:
        try:
            stale = stale_active_sources(max_age_days)
            if stale:
                logger.warning(
                    "[content_etl] %d active snapshot(s) older than %d days: %s",
                    len(stale), max_age_days, ", ".join(stale),
                )
                get_telemetry().increment_counter(
                    "content_etl_snapshot_stale_total", len(stale)
                )
        except Exception as exc:
            logger.debug("[content_etl] staleness check skipped: %s", exc)
        await asyncio.sleep(CHECK_INTERVAL_SECONDS)
