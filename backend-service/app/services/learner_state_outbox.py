"""Concurrent-safe PostgreSQL worker for learner observation application."""

from __future__ import annotations

import asyncio
import logging
import random
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import and_, exists, or_, select, update
from sqlalchemy.orm import aliased

from app.core.database import AsyncSessionLocal
from app.models.learner_state import LearnerObservationEvent
from app.services.learner_state import apply_observation_event

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class ClaimedEvent:
    id: Any
    user_id: Any
    concept_id: str
    event_id: str
    observed_at: datetime


def build_claim_statement(*, now: datetime, lease_timeout: timedelta, batch_size: int):
    lease_expired = now - lease_timeout
    earlier = aliased(LearnerObservationEvent)
    no_earlier_unapplied = ~exists(
        select(1).where(
            earlier.user_id == LearnerObservationEvent.user_id,
            earlier.concept_id == LearnerObservationEvent.concept_id,
            earlier.status.in_(("pending", "processing", "retry")),
            or_(
                earlier.observed_at < LearnerObservationEvent.observed_at,
                and_(
                    earlier.observed_at == LearnerObservationEvent.observed_at,
                    earlier.event_id < LearnerObservationEvent.event_id,
                ),
            ),
        )
    )
    claimable = (
        select(LearnerObservationEvent.id)
        .where(
            or_(
                and_(
                    LearnerObservationEvent.status.in_(("pending", "retry")),
                    LearnerObservationEvent.available_at <= now,
                ),
                and_(
                    LearnerObservationEvent.status == "processing",
                    LearnerObservationEvent.claimed_at <= lease_expired,
                ),
            ),
            no_earlier_unapplied,
        )
        .order_by(
            LearnerObservationEvent.user_id,
            LearnerObservationEvent.concept_id,
            LearnerObservationEvent.observed_at,
            LearnerObservationEvent.event_id,
        )
        .limit(max(1, batch_size))
        .with_for_update(skip_locked=True)
        .scalar_subquery()
    )
    return (
        update(LearnerObservationEvent)
        .where(LearnerObservationEvent.id.in_(claimable))
        .values(
            status="processing",
            claimed_at=now,
            attempt_count=LearnerObservationEvent.attempt_count + 1,
            last_error_code=None,
        )
        .returning(
            LearnerObservationEvent.id,
            LearnerObservationEvent.user_id,
            LearnerObservationEvent.concept_id,
            LearnerObservationEvent.event_id,
            LearnerObservationEvent.observed_at,
        )
        .execution_options(synchronize_session=False)
    )


def retry_delay_seconds(
    attempt: int,
    *,
    maximum: float = 30.0,
    jitter: float = 0.25,
) -> float:
    base = min(maximum, float(2 ** max(0, min(attempt - 1, 10))))
    return min(maximum, base + random.uniform(0.0, max(0.0, jitter)))


class LearnerStateOutboxWorker:
    def __init__(
        self,
        *,
        session_factory: Any = AsyncSessionLocal,
        batch_size: int = 100,
        poll_seconds: float = 0.1,
        lease_seconds: float = 30.0,
        max_attempts: int = 10,
    ) -> None:
        self._session_factory = session_factory
        self._batch_size = max(1, min(batch_size, 500))
        self._poll_seconds = max(0.01, poll_seconds)
        self._lease_timeout = timedelta(seconds=max(1.0, lease_seconds))
        self._max_attempts = max(1, max_attempts)
        self._stop = asyncio.Event()
        self._task: asyncio.Task[None] | None = None

    async def claim(self) -> list[ClaimedEvent]:
        now = datetime.now(UTC)
        async with self._session_factory() as session:
            result = await session.execute(
                build_claim_statement(
                    now=now,
                    lease_timeout=self._lease_timeout,
                    batch_size=self._batch_size,
                )
            )
            claimed = [ClaimedEvent(*row) for row in result.all()]
            await session.commit()
            return sorted(
                claimed,
                key=lambda item: (str(item.user_id), item.concept_id, item.observed_at, item.event_id),
            )

    async def _mark_failed(self, event_id: Any, exc: Exception) -> None:
        async with self._session_factory() as session:
            event = await session.scalar(
                select(LearnerObservationEvent)
                .where(LearnerObservationEvent.id == event_id)
                .with_for_update()
            )
            if event is None or event.status == "applied":
                return
            event.claimed_at = None
            event.last_error_code = type(exc).__name__[:100]
            if event.attempt_count >= self._max_attempts:
                event.status = "dead"
            else:
                event.status = "retry"
                event.available_at = datetime.now(UTC) + timedelta(
                    seconds=retry_delay_seconds(event.attempt_count)
                )
            await session.commit()

    async def apply_claimed(self, event_id: Any) -> bool:
        try:
            async with self._session_factory() as session:
                applied = await apply_observation_event(
                    session, event_id, now=datetime.now(UTC)
                )
                await session.commit()
                return applied
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning(
                "learner outbox apply failed error=%s", type(exc).__name__
            )
            await self._mark_failed(event_id, exc)
            return False

    async def run_once(self) -> int:
        claimed = await self.claim()
        applied = 0
        for item in claimed:
            applied += int(await self.apply_claimed(item.id))
        return applied

    async def _run(self) -> None:
        while not self._stop.is_set():
            try:
                processed = await self.run_once()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("learner outbox worker loop degraded")
                processed = 0
            if processed == 0:
                try:
                    await asyncio.wait_for(self._stop.wait(), self._poll_seconds)
                except TimeoutError:
                    pass

    def start(self) -> None:
        if self._task is None or self._task.done():
            self._stop.clear()
            self._task = asyncio.create_task(self._run(), name="learner-state-outbox")

    async def stop(self, *, timeout_seconds: float = 10.0) -> None:
        self._stop.set()
        if self._task is None:
            return
        try:
            await asyncio.wait_for(self._task, max(0.1, timeout_seconds))
        except TimeoutError:
            self._task.cancel()
            await asyncio.gather(self._task, return_exceptions=True)
        finally:
            self._task = None


_WORKER: LearnerStateOutboxWorker | None = None


def start_learner_state_outbox_worker() -> None:
    global _WORKER
    if _WORKER is None:
        from app.core.config import settings

        _WORKER = LearnerStateOutboxWorker(
            batch_size=settings.LEARNER_STATE_OUTBOX_BATCH_SIZE,
            poll_seconds=settings.LEARNER_STATE_OUTBOX_POLL_MS / 1000.0,
            lease_seconds=settings.LEARNER_STATE_OUTBOX_LEASE_SECONDS,
            max_attempts=settings.LEARNER_STATE_OUTBOX_MAX_ATTEMPTS,
        )
    _WORKER.start()


async def stop_learner_state_outbox_worker() -> None:
    global _WORKER
    if _WORKER is not None:
        await _WORKER.stop()
    _WORKER = None
