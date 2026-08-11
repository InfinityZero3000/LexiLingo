"""Synced mistake notebook models."""

import uuid
from datetime import UTC, datetime

from sqlalchemy import ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, PortableJSON, TZDateTime


class MistakeNotebookEntry(Base):
    """A user-owned mistake captured from quizzes, games, reading, or voice practice."""

    __tablename__ = "mistake_notebook_entries"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    client_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    source_type: Mapped[str] = mapped_column(String(80), nullable=False)
    source_id: Mapped[str] = mapped_column(String(255), nullable=False)
    source_title: Mapped[str] = mapped_column(String(500), default="", nullable=False)
    question: Mapped[str] = mapped_column(Text, nullable=False)
    question_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    selected_answer: Mapped[str] = mapped_column(Text, default="", nullable=False)
    correct_answer: Mapped[str] = mapped_column(Text, default="", nullable=False)
    explanation: Mapped[str] = mapped_column(Text, default="", nullable=False)
    skill: Mapped[str] = mapped_column(String(80), default="general", nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="open", nullable=False)
    review_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    attempt_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    extra_data: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(UTC),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(UTC),
        onupdate=lambda: datetime.now(UTC),
        nullable=False,
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    last_seen_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(UTC),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "client_id",
            name="uq_mistake_notebook_entries_user_client_id",
        ),
        Index(
            "ix_mistake_notebook_entries_user_status_created",
            "user_id",
            "status",
            "created_at",
        ),
        Index(
            "ix_mistake_notebook_entries_user_source_question_hash",
            "user_id",
            "source_type",
            "source_id",
            "question_hash",
        ),
    )
