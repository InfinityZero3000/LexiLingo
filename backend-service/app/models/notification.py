"""
Notification Model
Maps to existing 'notifications' table in the database.
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Boolean, ForeignKey, Text, Index, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, TZDateTime, PortableJSON


class Notification(Base):
    """
    User notifications for achievements, social events, system messages.
    Table already exists in DB — this model maps to it.
    """

    __tablename__ = "notifications"

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

    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    type: Mapped[str] = mapped_column(
        String(50), nullable=False
    )  # achievement, social, system, challenge, streak, level_up
    data: Mapped[dict] = mapped_column(PortableJSON, nullable=True)  # Extra payload (achievement_id, etc.)

    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    read_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=True)

    # "<period>" for system-sent nudges (a day, an ISO week); the unique index
    # below is what stops an overlapping or retried run from sending twice.
    dedupe_key: Mapped[str | None] = mapped_column(String(80), nullable=True)

    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        Index("idx_notification_user_read", "user_id", "is_read"),
        Index(
            "uq_notification_user_type_dedupe",
            "user_id",
            "type",
            "dedupe_key",
            unique=True,
            postgresql_where=text("dedupe_key IS NOT NULL"),
            sqlite_where=text("dedupe_key IS NOT NULL"),
        ),
    )

    def __repr__(self) -> str:
        return f"<Notification {self.type}: {self.title[:30]}>"
