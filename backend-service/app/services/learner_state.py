"""Learner concept-state evolution and persistence primitives."""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from math import exp, log
from collections.abc import Awaitable, Callable
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import delete, func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.learner_state import (
    LearnerConceptState,
    LearnerObservationEvent,
    LearnerStateProfile,
)
from app.models.user import User

ALGORITHM_VERSION = "bkt-fsrs-v1"
LEARNING_RATE = 0.45
MIN_MASTERY = 0.01
MAX_MASTERY = 0.99
MIN_STABILITY_DAYS = 0.25
MAX_STABILITY_DAYS = 3650.0
TARGET_RETENTION = 0.9
MAX_BATCH_CONCEPTS = 100
MAX_OBSERVATION_BATCH = 100


class TooManyConceptsError(ValueError):
    """Raised before issuing SQL when a batch exceeds its configured bound."""


@dataclass(frozen=True, slots=True)
class ObservationCleanupResult:
    payloads_eligible: int
    audit_rows_eligible: int
    payloads_cleared: int = 0
    audit_rows_deleted: int = 0
    cleanup_lag_seconds: float = 0.0


@dataclass(frozen=True, slots=True)
class ObservationInput:
    event_id: str
    user_id: UUID
    concept_id: str
    outcome: str
    confidence: float
    observed_at: datetime
    session_id: str | None = None
    payload: dict[str, Any] | None = None


@dataclass(frozen=True, slots=True)
class BatchStateResult:
    state_epoch: int
    states: tuple[LearnerConceptState, ...]
    goal: str | None = None
    interest: str | None = None


def _clamp(lower: float, upper: float, value: float) -> float:
    return max(lower, min(upper, value))


@dataclass(frozen=True, slots=True)
class LearnerStateSnapshot:
    """Database-independent state used by the deterministic update function."""

    mastery_probability: float = 0.5
    stability_days: float = 1.0
    difficulty: float = 0.5
    attempt_count: int = 0
    correct_count: int = 0
    error_count: int = 0
    last_interacted_at: datetime | None = None
    next_review_at: datetime | None = None
    state_version: int = 1
    algorithm_version: str = ALGORITHM_VERSION


def evolve_state(
    state: LearnerStateSnapshot,
    outcome: str,
    confidence: float,
    now: datetime,
) -> LearnerStateSnapshot:
    """Apply one confidence-weighted observation with exponential forgetting.

    This v1 model deliberately keeps a small sufficient state. It combines a
    BKT-style posterior step with an FSRS-style stability interval without
    retaining an unbounded review history.
    """
    if outcome not in {"correct", "incorrect"}:
        raise ValueError("outcome must be 'correct' or 'incorrect'")
    if not 0.0 <= confidence <= 1.0:
        raise ValueError("confidence must be between 0 and 1")
    if now.tzinfo is None:
        raise ValueError("now must be timezone-aware")

    elapsed_days = 0.0
    if state.last_interacted_at is not None:
        elapsed_days = max(
            0.0,
            (now - state.last_interacted_at).total_seconds() / 86_400.0,
        )

    stability = _clamp(
        MIN_STABILITY_DAYS,
        MAX_STABILITY_DAYS,
        state.stability_days,
    )
    retention = exp(-elapsed_days / stability)
    decayed_mastery = _clamp(
        MIN_MASTERY,
        MAX_MASTERY,
        state.mastery_probability * retention,
    )
    difficulty = _clamp(0.0, 1.0, state.difficulty)
    evidence = confidence * (1.0 - 0.35 * difficulty)
    target = 1.0 if outcome == "correct" else 0.0
    posterior = _clamp(
        MIN_MASTERY,
        MAX_MASTERY,
        decayed_mastery + evidence * LEARNING_RATE * (target - decayed_mastery),
    )

    if outcome == "correct":
        next_stability = stability * (1.0 + 0.45 * evidence * (1.0 - difficulty))
        next_difficulty = difficulty - 0.04 * evidence
    else:
        next_stability = stability * (1.0 - 0.55 * evidence)
        next_difficulty = difficulty + 0.08 * evidence

    next_stability = _clamp(MIN_STABILITY_DAYS, MAX_STABILITY_DAYS, next_stability)
    next_difficulty = _clamp(0.0, 1.0, next_difficulty)
    interval_days = max(
        MIN_STABILITY_DAYS,
        -next_stability * log(TARGET_RETENTION),
    )

    return replace(
        state,
        mastery_probability=posterior,
        stability_days=next_stability,
        difficulty=next_difficulty,
        attempt_count=state.attempt_count + 1,
        correct_count=state.correct_count + (outcome == "correct"),
        error_count=state.error_count + (outcome == "incorrect"),
        last_interacted_at=now,
        next_review_at=now + timedelta(days=interval_days),
        state_version=state.state_version + 1,
        algorithm_version=ALGORITHM_VERSION,
    )


def _snapshot_from_model(row: LearnerConceptState) -> LearnerStateSnapshot:
    return LearnerStateSnapshot(
        mastery_probability=row.mastery_probability,
        stability_days=row.stability_days,
        difficulty=row.difficulty,
        attempt_count=row.attempt_count,
        correct_count=row.correct_count,
        error_count=row.error_count,
        last_interacted_at=row.last_interacted_at,
        next_review_at=row.next_review_at,
        state_version=row.state_version,
        algorithm_version=row.algorithm_version,
    )


def _apply_snapshot(
    row: LearnerConceptState,
    snapshot: LearnerStateSnapshot,
    now: datetime,
) -> None:
    row.mastery_probability = snapshot.mastery_probability
    row.stability_days = snapshot.stability_days
    row.difficulty = snapshot.difficulty
    row.attempt_count = snapshot.attempt_count
    row.correct_count = snapshot.correct_count
    row.error_count = snapshot.error_count
    row.last_interacted_at = snapshot.last_interacted_at
    row.next_review_at = snapshot.next_review_at
    row.state_version = snapshot.state_version
    row.algorithm_version = snapshot.algorithm_version
    # Required explicitly because Core UPDATE/UPSERT paths do not trigger the
    # ORM-only ``onupdate`` callback.
    row.updated_at = now


def _validate_observation(observation: ObservationInput) -> None:
    if len(observation.event_id) != 64:
        raise ValueError("event_id must be a 64-character SHA-256 hex digest")
    try:
        int(observation.event_id, 16)
    except ValueError as exc:
        raise ValueError("event_id must be hexadecimal") from exc
    if not observation.concept_id or len(observation.concept_id) > 255:
        raise ValueError("concept_id must contain 1..255 characters")
    if observation.outcome not in {"correct", "incorrect"}:
        raise ValueError("outcome must be 'correct' or 'incorrect'")
    if not 0.0 <= observation.confidence <= 1.0:
        raise ValueError("confidence must be between 0 and 1")
    if observation.observed_at.tzinfo is None:
        raise ValueError("observed_at must be timezone-aware")


async def get_states_for_concepts(
    session: AsyncSession,
    user_id: UUID,
    concept_ids: list[str],
    *,
    limit: int = MAX_BATCH_CONCEPTS,
) -> BatchStateResult:
    """Read one sparse learner overlay with exactly two bounded SELECTs.

    The first SELECT joins ``users`` so callers needing onboarding
    preferences (goal/interest) alongside the epoch get them for free —
    this is a hot, deadline-bounded RPC (ai-service polls it every chat
    turn), so a separate third round-trip for those two columns would
    silently break that latency budget.
    """
    ids = list(dict.fromkeys(concept_ids))
    if len(ids) > limit:
        raise TooManyConceptsError(f"at most {limit} concept IDs are allowed")
    if any(not concept_id or len(concept_id) > 255 for concept_id in ids):
        raise ValueError("concept IDs must contain 1..255 characters")

    profile_row = (
        await session.execute(
            select(LearnerStateProfile.state_epoch, User.goal, User.interest)
            .select_from(User)
            .outerjoin(LearnerStateProfile, LearnerStateProfile.user_id == User.id)
            .where(User.id == user_id)
        )
    ).first()
    epoch = profile_row.state_epoch if profile_row else None
    goal = profile_row.goal if profile_row else None
    interest = profile_row.interest if profile_row else None

    if not ids:
        return BatchStateResult(
            state_epoch=int(epoch or 0), states=(), goal=goal, interest=interest
        )

    rows = (
        await session.scalars(
            select(LearnerConceptState).where(
                LearnerConceptState.user_id == user_id,
                LearnerConceptState.concept_id.in_(ids),
            )
        )
    ).all()
    by_id = {row.concept_id: row for row in rows}
    return BatchStateResult(
        state_epoch=int(epoch or 0),
        states=tuple(by_id[concept_id] for concept_id in ids if concept_id in by_id),
        goal=goal,
        interest=interest,
    )


async def get_due_concepts_for_user(
    session: AsyncSession,
    user_id: UUID,
    *,
    now: datetime | None = None,
    limit: int = MAX_BATCH_CONCEPTS,
) -> list[LearnerConceptState]:
    """List concepts due for review for a user, across all concept types
    (vocabulary, grammar, mission) — unlike get_states_for_concepts, the
    caller does not need to know concept_ids in advance. Uses the existing
    ix_learner_state_user_due index (user_id, next_review_at)."""
    now = now or datetime.now(UTC)
    rows = (
        await session.scalars(
            select(LearnerConceptState)
            .where(
                LearnerConceptState.user_id == user_id,
                LearnerConceptState.next_review_at.is_not(None),
                LearnerConceptState.next_review_at <= now,
            )
            .order_by(LearnerConceptState.next_review_at.asc())
            .limit(min(limit, MAX_BATCH_CONCEPTS))
        )
    ).all()
    return list(rows)


async def ingest_observations(
    session: AsyncSession,
    observations: list[ObservationInput],
    *,
    limit: int = MAX_OBSERVATION_BATCH,
) -> set[str]:
    """Durably enqueue observations, returning IDs inserted by this call.

    PostgreSQL conflict handling makes retries safe. The caller owns the
    transaction and must acknowledge only after commit.
    """
    if len(observations) > limit:
        raise ValueError(f"at most {limit} observations are allowed")
    for observation in observations:
        _validate_observation(observation)
    if not observations:
        return set()

    rows = [
        {
            "id": uuid4(),
            "event_id": item.event_id,
            "user_id": item.user_id,
            "session_id": item.session_id,
            "concept_id": item.concept_id,
            "outcome": item.outcome,
            "confidence": item.confidence,
            "observed_at": item.observed_at,
            "payload": item.payload,
            "status": "pending",
            # Queue availability is server time, independent of client clock
            # skew in the pedagogical observation timestamp.
            "available_at": datetime.now(UTC),
        }
        for item in observations
    ]
    dialect = session.bind.dialect.name if session.bind else "postgresql"  # type: ignore[union-attr]
    if dialect != "postgresql":
        raise RuntimeError("learner observation ingestion requires PostgreSQL")

    statement = (
        pg_insert(LearnerObservationEvent)
        .values(rows)
        .on_conflict_do_nothing(index_elements=["event_id"])
        .returning(LearnerObservationEvent.event_id)
    )
    return set((await session.scalars(statement)).all())


async def bump_learner_state_epoch(
    session: AsyncSession,
    user_id: UUID,
    now: datetime,
) -> None:
    """Advance a learner's cache-invalidation epoch by one.

    Any personalized artifact (TraceCAG cache entries, KG-derived responses)
    that depends on ``learner:{user_id}:profile`` is versioned off this epoch,
    so bumping it here is what makes those artifacts refresh instead of
    silently going stale after learner state changes.
    """
    await session.execute(
        pg_insert(LearnerStateProfile)
        .values(user_id=user_id, state_epoch=0, updated_at=now)
        .on_conflict_do_nothing(index_elements=["user_id"])
    )
    profile = await session.scalar(
        select(LearnerStateProfile)
        .where(LearnerStateProfile.user_id == user_id)
        .with_for_update()
    )
    if profile is None:  # pragma: no cover - defensive database invariant
        raise RuntimeError("learner state profile row was not created")
    profile.state_epoch += 1
    profile.updated_at = now


async def apply_observation_event(
    session: AsyncSession,
    event_db_id: UUID,
    *,
    now: datetime,
) -> bool:
    """Apply one claimed outbox event atomically with its learner epoch.

    Callers must use one event per transaction. Task 6's worker claims events
    in ``(user_id, concept_id, observed_at, event_id)`` order and retries
    serialization/deadlock errors. A late event is still useful evidence but
    must never move the learner clock backwards.
    """
    if now.tzinfo is None:
        raise ValueError("now must be timezone-aware")
    event = await session.scalar(
        select(LearnerObservationEvent)
        .where(LearnerObservationEvent.id == event_db_id)
        .with_for_update()
    )
    if event is None or event.status == "applied":
        return False
    if event.status not in {"pending", "processing", "retry"}:
        raise ValueError(f"event status {event.status!r} is not applicable")

    await session.execute(
        pg_insert(LearnerConceptState)
        .values(
            id=uuid4(),
            user_id=event.user_id,
            concept_id=event.concept_id,
        )
        .on_conflict_do_nothing(index_elements=["user_id", "concept_id"])
    )
    state = await session.scalar(
        select(LearnerConceptState)
        .where(
            LearnerConceptState.user_id == event.user_id,
            LearnerConceptState.concept_id == event.concept_id,
        )
        .with_for_update()
    )
    if state is None:  # pragma: no cover - defensive database invariant
        raise RuntimeError("learner state row was not created")

    effective_observed_at = event.observed_at
    if state.last_interacted_at is not None:
        effective_observed_at = max(effective_observed_at, state.last_interacted_at)
    next_state = evolve_state(
        _snapshot_from_model(state),
        outcome=event.outcome,
        confidence=event.confidence,
        now=effective_observed_at,
    )
    _apply_snapshot(state, next_state, now)

    await bump_learner_state_epoch(session, event.user_id, now)

    event.status = "applied"
    event.applied_at = now
    event.claimed_at = None
    event.last_error_code = None
    await session.flush()
    return True


async def cleanup_observation_events(
    session: AsyncSession,
    *,
    now: datetime,
    dry_run: bool = True,
    batch_size: int = 5000,
    archive_hook: Callable[[str, list[dict[str, Any]]], Awaitable[None]] | None = None,
) -> ObservationCleanupResult:
    """Bounded retention cleanup; pending/retry/dead rows are never deleted."""
    if now.tzinfo is None:
        raise ValueError("now must be timezone-aware")
    limit = max(1, min(batch_size, 5000))
    payload_cutoff = now - timedelta(days=90)
    audit_cutoff = now - timedelta(days=365)
    payload_filter = (
        LearnerObservationEvent.status == "applied",
        LearnerObservationEvent.applied_at < payload_cutoff,
        LearnerObservationEvent.payload.is_not(None),
    )
    delete_filter = (
        LearnerObservationEvent.status == "applied",
        LearnerObservationEvent.applied_at < audit_cutoff,
    )
    payload_count = int(
        await session.scalar(select(func.count()).where(*payload_filter)) or 0
    )
    delete_count = int(
        await session.scalar(select(func.count()).where(*delete_filter)) or 0
    )
    oldest_applied = await session.scalar(
        select(func.min(LearnerObservationEvent.applied_at)).where(
            LearnerObservationEvent.status == "applied"
        )
    )
    cleanup_lag = (
        max(0.0, (now - oldest_applied).total_seconds()) if oldest_applied else 0.0
    )
    if dry_run:
        return ObservationCleanupResult(
            payload_count, delete_count, cleanup_lag_seconds=cleanup_lag
        )

    payload_ids = (
        select(LearnerObservationEvent.id)
        .where(*payload_filter)
        .order_by(LearnerObservationEvent.applied_at)
        .limit(limit)
        .scalar_subquery()
    )
    delete_id_query = (
        select(LearnerObservationEvent.id)
        .where(*delete_filter)
        .order_by(LearnerObservationEvent.applied_at)
        .limit(limit)
    )
    selected_delete_ids = list((await session.scalars(delete_id_query)).all())
    if archive_hook and selected_delete_ids:
        archive_rows = (
            await session.scalars(
                select(LearnerObservationEvent).where(
                    LearnerObservationEvent.id.in_(selected_delete_ids)
                )
            )
        ).all()
        await archive_hook(
            "learner-observation-audit-v1",
            [
                {
                    "event_id": row.event_id,
                    "user_id": str(row.user_id),
                    "concept_id": row.concept_id,
                    "applied_at": row.applied_at.isoformat() if row.applied_at else None,
                }
                for row in archive_rows
            ],
        )
    cleared = await session.execute(
        update(LearnerObservationEvent)
        .where(LearnerObservationEvent.id.in_(payload_ids))
        .values(payload=None)
        .execution_options(synchronize_session=False)
    )
    deleted = await session.execute(
        delete(LearnerObservationEvent)
        .where(LearnerObservationEvent.id.in_(selected_delete_ids))
        .execution_options(synchronize_session=False)
    )
    return ObservationCleanupResult(
        payload_count,
        delete_count,
        payloads_cleared=max(0, int(cleared.rowcount or 0)),
        audit_rows_deleted=max(0, int(deleted.rowcount or 0)),
        cleanup_lag_seconds=cleanup_lag,
    )
