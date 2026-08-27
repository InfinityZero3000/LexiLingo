"""Feature Processor — turns raw ProductEvent rows into named recommender
insights. One event type fans out into several independent features, each a
pure function over rows that have already been loaded once:

    content_interaction
            │
            ▼
      Feature Processor
            │
            ├── topic_affinity        (what the learner picks)
            ├── vocabulary_weakness   (what they get wrong)
            └── difficulty_preference (harder or easier than their level)

compute_insights() is called two ways: synchronously from
recommendation_service.build_profile() on a cache miss, and asynchronously
from app.tasks.event_worker, which drains the content_interaction Redis
Stream and writes the result under INSIGHTS_CACHE_PREFIX so the request path
usually just reads a cache hit instead of recomputing.
"""

from __future__ import annotations

import logging
import math
import uuid
from collections import defaultdict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Course
from app.models.product_event import ProductEvent
from app.models.vocabulary import VocabularyItem

logger = logging.getLogger(__name__)

# Weight of each interaction. A completion says far more about interest (or,
# for a review outcome, about mastery) than an impression does.
ACTION_WEIGHTS = {
    "complete": 1.0,
    "start": 0.7,
    "review": 0.7,
    "review_correct": 0.7,
    "review_incorrect": 0.7,
    "open": 0.4,
    "impression": 0.05,
    "skip": -0.5,
}
DECAY_HALF_LIFE_DAYS = 14.0
EVENT_WINDOW_DAYS = 60
# ponytail: events are aggregated in Python from a bounded window rather than
# in SQL, so this works identically on SQLite (tests) and JSONB. Materialize
# into per-user summary tables when this scan shows up in slow queries.
EVENT_ROW_LIMIT = 2000

# Where the async worker publishes and the sync request path reads insights
# from, keyed per user. TTL is the staleness ceiling if the worker stalls —
# a expired entry just falls back to a synchronous recompute.
STREAM_KEY = "rec:events:content_interaction"

INSIGHTS_CACHE_PREFIX = "rec:insights:"
INSIGHTS_CACHE_TTL_SECONDS = 3600

# Nothing reads an event older than EVENT_WINDOW_DAYS — every processor above
# loads a 60-day window — so anything past this retention is dead weight that
# only costs disk, index depth and backup size. Kept wider than the read
# window so a widened window (or an ad-hoc analytics query) still has slack.
EVENT_RETENTION_DAYS = 90
# Deleted per statement so one night's cleanup cannot hold a long lock on the
# 2-vCPU production box. Mirrors prune_exercise_attempts' batching.
PRUNE_BATCH_SIZE = 5000

_CEFR_ORDER = {"A1": 0, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5}

Processor = Callable[
    [AsyncSession, list[ProductEvent], dict[str, Any], datetime], Awaitable[dict[str, Any]]
]


async def compute_insights(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    level: str | None = None,
    now: datetime | None = None,
) -> dict[str, Any]:
    """Run every registered processor for every event type it cares about,
    loading each event type's rows once and sharing them across processors."""
    now = now or datetime.now(UTC)
    context = {"level": level}
    insights: dict[str, Any] = {}
    for event_name, processors in _PROCESSORS.items():
        rows = await _load_events(db, user_id, event_name, now)
        for processor in processors:
            insights.update(await processor(db, rows, context, now))
    return insights


async def build_topic_affinity(
    db: AsyncSession, user_id: uuid.UUID, *, now: datetime | None = None
) -> dict[str, float]:
    """Time-decayed topic preference, normalized to [0,1].

    This is the "topic the learner picks most often" signal: every surface
    reports `content_interaction` with a `topic`, and recent picks outweigh
    old ones on a 14-day half-life. Standalone entry point (used directly by
    tests and any other one-off caller); compute_insights() computes the same
    thing from rows it has already loaded, via _topic_affinity_from_rows.
    """
    now = now or datetime.now(UTC)
    rows = await _load_events(db, user_id, "content_interaction", now)
    return _topic_affinity_from_rows(rows, now)


async def _process_topic_affinity(
    db: AsyncSession, rows: list[ProductEvent], context: dict[str, Any], now: datetime
) -> dict[str, Any]:
    return {"topic_affinity": _topic_affinity_from_rows(rows, now)}


def _topic_affinity_from_rows(rows: list[ProductEvent], now: datetime) -> dict[str, float]:
    totals: dict[str, float] = defaultdict(float)
    for row in rows:
        properties = row.properties or {}
        topic = str(properties.get("topic") or "").strip().lower()
        if not topic:
            continue
        weight = ACTION_WEIGHTS.get(str(properties.get("action") or "open"), 0.4)
        totals[topic] += weight * _decay(row.created_at, now)
    return _normalize_positive(totals)


async def _process_vocabulary_weakness(
    db: AsyncSession, rows: list[ProductEvent], context: dict[str, Any], now: datetime
) -> dict[str, Any]:
    """Per-topic fail signal from vocab reviews: a wrong answer pulls a
    topic's weakness up, a right one pulls it back down. Only vocab review
    outcomes count — every other action on every other item type is silently
    irrelevant here, unlike topic_affinity which reads all of them."""
    totals: dict[str, float] = defaultdict(float)
    for row in rows:
        properties = row.properties or {}
        if properties.get("item_type") != "vocab":
            continue
        action = properties.get("action")
        if action not in ("review_correct", "review_incorrect"):
            continue
        topic = str(properties.get("topic") or "").strip().lower()
        if not topic:
            continue
        sign = 1.0 if action == "review_incorrect" else -0.4
        totals[topic] += sign * _decay(row.created_at, now)
    return {"vocabulary_weakness": _normalize_positive(totals)}


async def _process_difficulty_preference(
    db: AsyncSession, rows: list[ProductEvent], context: dict[str, Any], now: datetime
) -> dict[str, Any]:
    """Signed preference for content above/below the learner's own level,
    scoped to vocab and course interactions — the two item types that carry a
    CEFR level. Positive = engages with harder content, negative = easier.
    A skip counts too: skipping something harder than the learner's level is
    real evidence against wanting harder content, via ACTION_WEIGHTS' -0.5."""
    user_idx = _CEFR_ORDER.get(str(context.get("level") or "A1").upper(), 0)
    levels = await _item_levels(db, rows)

    weighted_sum = 0.0
    weight_total = 0.0
    for row in rows:
        properties = row.properties or {}
        item_level = levels.get(str(properties.get("item_id") or ""))
        if not item_level:
            continue
        item_idx = _CEFR_ORDER.get(str(item_level).upper())
        if item_idx is None:
            continue
        delta = max(-2, min(2, item_idx - user_idx))
        weight = ACTION_WEIGHTS.get(str(properties.get("action") or "open"), 0.4)
        decay = _decay(row.created_at, now)
        weighted_sum += weight * decay * delta
        weight_total += abs(weight) * decay

    if weight_total == 0:
        return {"difficulty_preference": 0.0}
    preference = (weighted_sum / weight_total) / 2.0
    return {"difficulty_preference": round(max(-1.0, min(1.0, preference)), 4)}


async def _item_levels(db: AsyncSession, rows: list[ProductEvent]) -> dict[str, str]:
    vocab_ids: set[str] = set()
    course_ids: set[str] = set()
    for row in rows:
        properties = row.properties or {}
        item_id = properties.get("item_id")
        if not item_id:
            continue
        if properties.get("item_type") == "vocab":
            vocab_ids.add(item_id)
        elif properties.get("item_type") == "course":
            course_ids.add(item_id)

    levels: dict[str, str] = {}
    if vocab_ids:
        rows_ = await db.execute(
            select(VocabularyItem.id, VocabularyItem.difficulty_level).where(
                VocabularyItem.id.in_(_as_uuids(vocab_ids))
            )
        )
        levels.update({str(vid): _level_value(level) for vid, level in rows_})
    if course_ids:
        rows_ = await db.execute(
            select(Course.id, Course.level).where(Course.id.in_(_as_uuids(course_ids)))
        )
        levels.update({str(cid): level for cid, level in rows_})
    return levels


def _as_uuids(raw_ids: set[str]) -> list[uuid.UUID]:
    parsed = []
    for raw in raw_ids:
        try:
            parsed.append(uuid.UUID(raw))
        except (ValueError, AttributeError, TypeError):
            continue
    return parsed


def _level_value(level: Any) -> str | None:
    return getattr(level, "value", level)


@dataclass(frozen=True, slots=True)
class EventPruneResult:
    deleted: int
    cutoff: datetime


async def prune_product_events(
    db: AsyncSession,
    *,
    now: datetime | None = None,
    retention_days: int = EVENT_RETENTION_DAYS,
    batch_size: int = PRUNE_BATCH_SIZE,
) -> EventPruneResult:
    """Delete product events past the retention window.

    product_events is append-only and the highest-volume table in the system:
    every browse, start, review outcome and impression writes a row. Without
    this it was the one high-volume table with no retention at all, growing
    ~40GB/year at 10k daily-active learners while the processors above only
    ever read the newest 60 days of it.
    """
    now = now or datetime.now(UTC)
    cutoff = now - timedelta(days=retention_days)

    deleted = 0
    while True:
        ids = (
            await db.scalars(
                select(ProductEvent.id)
                .where(ProductEvent.created_at < cutoff)
                .limit(batch_size)
            )
        ).all()
        if not ids:
            break
        result = await db.execute(
            delete(ProductEvent)
            .where(ProductEvent.id.in_(ids))
            .execution_options(synchronize_session=False)
        )
        await db.commit()
        deleted += int(result.rowcount or 0)
        if len(ids) < batch_size:
            break

    return EventPruneResult(deleted=deleted, cutoff=cutoff)


def _normalize_positive(totals: dict[str, float]) -> dict[str, float]:
    positives = [value for value in totals.values() if value > 0]
    if not positives:
        return {}
    peak = max(positives)
    return {key: round(value / peak, 4) for key, value in totals.items() if value > 0}


def _decay(created_at: datetime, now: datetime) -> float:
    age_days = max((now - _as_utc(created_at)).total_seconds() / 86400.0, 0.0)
    return math.exp(-age_days * math.log(2) / DECAY_HALF_LIFE_DAYS)


def _as_utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


async def _load_events(
    db: AsyncSession, user_id: uuid.UUID, event_name: str, now: datetime
) -> list[ProductEvent]:
    since = now - timedelta(days=EVENT_WINDOW_DAYS)
    return list(
        await db.scalars(
            select(ProductEvent)
            .where(
                ProductEvent.user_id == user_id,
                ProductEvent.event_name == event_name,
                ProductEvent.created_at >= since,
            )
            .order_by(ProductEvent.created_at.desc())
            .limit(EVENT_ROW_LIMIT)
        )
    )


_PROCESSORS: dict[str, list[Processor]] = {
    "content_interaction": [
        _process_topic_affinity,
        _process_vocabulary_weakness,
        _process_difficulty_preference,
    ],
}
