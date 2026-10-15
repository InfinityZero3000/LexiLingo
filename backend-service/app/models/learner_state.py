"""Sparse per-user concept state and durable learner-observation outbox."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import CheckConstraint, Float, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, PortableJSON, TZDateTime


def utc_now() -> datetime:
    return datetime.now(UTC)


class LearnerConceptState(Base):
    """Materialized learner overlay; rows exist only for observed concepts."""

    __tablename__ = "learner_concept_states"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    concept_id: Mapped[str] = mapped_column(String(255), nullable=False)
    mastery_probability: Mapped[float] = mapped_column(Float, nullable=False, default=0.5)
    stability_days: Mapped[float] = mapped_column(Float, nullable=False, default=1.0)
    difficulty: Mapped[float] = mapped_column(Float, nullable=False, default=0.5)
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    correct_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    error_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_interacted_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    next_review_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    state_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    # Placeholder only: evolve_state stamps its own ALGORITHM_VERSION on every
    # write. Kept as a literal because importing the service here would close
    # an import cycle (the service imports this module).
    algorithm_version: Mapped[str] = mapped_column(
        String(32), nullable=False, default="bkt-fsrs-v2"
    )
    created_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )

    __table_args__ = (
        UniqueConstraint("user_id", "concept_id", name="uq_learner_state_user_concept"),
        CheckConstraint(
            "mastery_probability >= 0.0 AND mastery_probability <= 1.0",
            name="ck_learner_state_mastery_probability",
        ),
        CheckConstraint(
            "difficulty >= 0.0 AND difficulty <= 1.0",
            name="ck_learner_state_difficulty",
        ),
        CheckConstraint("stability_days >= 0.0", name="ck_learner_state_stability"),
        CheckConstraint(
            "attempt_count >= 0 AND correct_count >= 0 AND error_count >= 0",
            name="ck_learner_state_counters_nonnegative",
        ),
        CheckConstraint(
            "correct_count + error_count <= attempt_count",
            name="ck_learner_state_counter_consistency",
        ),
        CheckConstraint("state_version >= 1", name="ck_learner_state_version"),
        Index("ix_learner_state_user_due", "user_id", "next_review_at"),
        Index("ix_learner_state_user_mastery", "user_id", "mastery_probability"),
        Index("ix_learner_state_user_updated", "user_id", "updated_at"),
    )


class LearnerStateProfile(Base):
    """One scalar epoch per learner for safe personalized cache invalidation."""

    __tablename__ = "learner_state_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    state_epoch: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )

    __table_args__ = (
        CheckConstraint("state_epoch >= 0", name="ck_learner_state_profile_epoch"),
    )


class LearnerObservationEvent(Base):
    """Idempotent observation and PostgreSQL transactional outbox record."""

    __tablename__ = "learner_observation_events"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    event_id: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    session_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    concept_id: Mapped[str] = mapped_column(String(255), nullable=False)
    outcome: Mapped[str] = mapped_column(String(32), nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False)
    observed_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=False)
    payload: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    available_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=False, default=utc_now)
    claimed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    applied_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    last_error_code: Mapped[str | None] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=False, default=utc_now)

    __table_args__ = (
        CheckConstraint(
            "confidence >= 0.0 AND confidence <= 1.0",
            name="ck_learner_observation_confidence",
        ),
        CheckConstraint(
            "outcome IN ('correct', 'incorrect')",
            name="ck_learner_observation_outcome",
        ),
        CheckConstraint(
            "status IN ('pending', 'processing', 'applied', 'retry', 'dead')",
            name="ck_learner_observation_status",
        ),
        CheckConstraint(
            "attempt_count >= 0 AND attempt_count <= 100",
            name="ck_learner_observation_attempt_count",
        ),
        Index(
            "ix_learner_observation_claim",
            "status",
            "available_at",
            "created_at",
        ),
        Index("ix_learner_observation_cleanup", "status", "applied_at"),
        Index("ix_learner_observation_user_created", "user_id", "created_at"),
        Index(
            "ix_learner_observation_concept_order",
            "user_id", "concept_id", "observed_at", "event_id",
        ),
    )
