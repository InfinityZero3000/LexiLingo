"""IELTS mock-test models: the test itself, a learner's attempt, and AI grading
of the two productive skills.

The test's structure lives in `IeltsTest.content` as JSON rather than in
section/part/question tables, matching how `Lesson.content` already stores
exercises. A test paper is authored and revised as one whole; nothing in the
product edits a single question in isolation, so the extra tables would buy
querying nobody does at the cost of a five-way join on every page load.

Grading is split the way IELTS itself splits it: Listening and Reading are
answer keys and are graded on submit, so they live in `IeltsAttempt.answers`.
Writing and Speaking are judged against four band descriptors by an AI grader
that can fail, be retried, or be re-run with a newer prompt — that needs its
own row with a status, which is `IeltsGrading`.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.db_types import GUID, TZDateTime, PortableJSON

TEST_TYPES = ("academic", "general_training")
SKILL_SCOPES = ("full", "listening", "reading", "writing", "speaking")
PRODUCTIVE_SKILLS = ("writing", "speaking")
ATTEMPT_STATUSES = ("in_progress", "submitted", "graded", "abandoned")
GRADING_STATUSES = ("pending", "graded", "failed")


def _enum_check(column: str, allowed: tuple[str, ...], name: str) -> CheckConstraint:
    values = ", ".join(f"'{value}'" for value in allowed)
    return CheckConstraint(f"{column} IN ({values})", name=name)


class IeltsTest(Base):
    """One mock paper. `skill_scope` distinguishes a full four-skill sitting
    from a single-skill practice paper — learners want both, and a Writing-only
    paper has no overall band to report."""

    __test__ = False
    __tablename__ = "ielts_tests"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    slug: Mapped[str | None] = mapped_column(String(255), nullable=True, unique=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    test_type: Mapped[str] = mapped_column(String(20), nullable=False, default="academic")
    skill_scope: Mapped[str] = mapped_column(String(20), nullable=False, default="full")

    # Band the paper is pitched at, e.g. "5.0-6.5". Free text: IELTS has no CEFR
    # column and a range is what learners actually search by.
    target_band: Mapped[str | None] = mapped_column(String(20), nullable=True)

    content: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    is_published: Mapped[bool] = mapped_column(default=False, nullable=False)

    created_by: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime, default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    attempts = relationship(
        "IeltsAttempt", back_populates="test", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("ix_ielts_tests_published", "is_published"),
        Index("ix_ielts_tests_type_scope", "test_type", "skill_scope"),
        _enum_check("test_type", TEST_TYPES, "ck_ielts_tests_test_type"),
        _enum_check("skill_scope", SKILL_SCOPES, "ck_ielts_tests_skill_scope"),
    )


class IeltsAttempt(Base):
    """One sitting. Bands are Numeric(2,1) because IELTS reports in half bands
    and a float would render 6.5 as 6.4999."""

    __tablename__ = "ielts_attempts"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    test_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("ielts_tests.id", ondelete="CASCADE"), nullable=False
    )

    status: Mapped[str] = mapped_column(String(20), nullable=False, default="in_progress")
    # Which skills this sitting covers; a learner may take only Reading from a
    # full paper, and the overall band must then stay null rather than average
    # one skill against three zeros.
    skill_scope: Mapped[str] = mapped_column(String(20), nullable=False, default="full")

    answers: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    raw_scores: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)

    listening_band: Mapped[float | None] = mapped_column(Numeric(2, 1), nullable=True)
    reading_band: Mapped[float | None] = mapped_column(Numeric(2, 1), nullable=True)
    writing_band: Mapped[float | None] = mapped_column(Numeric(2, 1), nullable=True)
    speaking_band: Mapped[float | None] = mapped_column(Numeric(2, 1), nullable=True)
    overall_band: Mapped[float | None] = mapped_column(Numeric(2, 1), nullable=True)

    time_spent_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    started_at: Mapped[datetime] = mapped_column(
        TZDateTime, default=lambda: datetime.now(timezone.utc)
    )
    submitted_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    graded_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)

    test = relationship("IeltsTest", back_populates="attempts", lazy="selectin")
    gradings = relationship(
        "IeltsGrading",
        back_populates="attempt",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    __table_args__ = (
        Index("ix_ielts_attempts_user_started", "user_id", "started_at"),
        Index("ix_ielts_attempts_test", "test_id"),
        _enum_check("status", ATTEMPT_STATUSES, "ck_ielts_attempts_status"),
        _enum_check("skill_scope", SKILL_SCOPES, "ck_ielts_attempts_skill_scope"),
    )


class IeltsGrading(Base):
    """One AI-graded Writing task or Speaking part.

    `criteria_scores` holds the four band descriptors for the skill — Writing
    scores Task Response / Coherence & Cohesion / Lexical Resource /
    Grammatical Range & Accuracy; Speaking swaps Task Response for Fluency &
    Coherence and adds Pronunciation. Storing them as JSON keeps one table for
    both skills without four nullable columns that mean different things
    depending on the row.
    """

    __tablename__ = "ielts_gradings"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    attempt_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("ielts_attempts.id", ondelete="CASCADE"), nullable=False
    )

    skill: Mapped[str] = mapped_column(String(20), nullable=False)
    # Which task/part inside the skill, e.g. "writing_task_1", "speaking_part_2".
    part_key: Mapped[str] = mapped_column(String(50), nullable=False)

    submission_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    audio_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    word_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    criteria_scores: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    band: Mapped[float | None] = mapped_column(Numeric(2, 1), nullable=True)
    feedback: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)

    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    error_detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    grader_version: Mapped[str | None] = mapped_column(String(50), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        TZDateTime, default=lambda: datetime.now(timezone.utc)
    )
    graded_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)

    attempt = relationship("IeltsAttempt", back_populates="gradings")

    __table_args__ = (
        Index("ix_ielts_gradings_attempt", "attempt_id"),
        Index("ix_ielts_gradings_status", "status"),
        _enum_check("skill", PRODUCTIVE_SKILLS, "ck_ielts_gradings_skill"),
        _enum_check("status", GRADING_STATUSES, "ck_ielts_gradings_status"),
    )
