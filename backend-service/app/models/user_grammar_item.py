"""Per-user spaced-repetition state for grammar items."""

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import Float, ForeignKey, Index, Integer, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, TZDateTime


class UserGrammarItem(Base):
    __tablename__ = "user_grammar_items"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    grammar_item_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("grammar_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    ease_factor: Mapped[float] = mapped_column(Float, default=2.5)
    interval: Mapped[int] = mapped_column(Integer, default=1)
    repetitions: Mapped[int] = mapped_column(Integer, default=0)
    next_review_date: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc) + timedelta(days=1),
        index=True,
    )
    last_reviewed_at: Mapped[datetime | None] = mapped_column(
        TZDateTime,
        nullable=True,
    )

    fsrs_stability: Mapped[float | None] = mapped_column(
        Float,
        default=0.0,
        nullable=True,
    )
    fsrs_difficulty: Mapped[float | None] = mapped_column(
        Float,
        default=0.0,
        nullable=True,
    )
    fsrs_elapsed_days: Mapped[int | None] = mapped_column(
        Integer,
        default=0,
        nullable=True,
    )
    fsrs_scheduled_days: Mapped[int | None] = mapped_column(
        Integer,
        default=0,
        nullable=True,
    )
    fsrs_reps: Mapped[int | None] = mapped_column(
        Integer,
        default=0,
        nullable=True,
    )
    fsrs_lapses: Mapped[int | None] = mapped_column(
        Integer,
        default=0,
        nullable=True,
    )
    fsrs_state: Mapped[int | None] = mapped_column(
        Integer,
        default=0,
        nullable=True,
    )
    fsrs_last_review: Mapped[datetime | None] = mapped_column(
        TZDateTime,
        nullable=True,
    )

    total_reviews: Mapped[int] = mapped_column(Integer, default=0)
    correct_reviews: Mapped[int] = mapped_column(Integer, default=0)
    added_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "grammar_item_id",
            name="uq_user_grammar_items_user_item",
        ),
        Index(
            "ix_user_grammar_items_user_next_review",
            "user_id",
            "next_review_date",
        ),
    )
