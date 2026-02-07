"""
Notification Model
Maps to existing 'notifications' table in the database.
"""

import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, Boolean, ForeignKey, Text, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID


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
    data: Mapped[dict] = mapped_column(JSON, nullable=True)  # Extra payload (achievement_id, etc.)

    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    read_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        Index("idx_notification_user_read", "user_id", "is_read"),
    )

    def __repr__(self) -> str:
        return f"<Notification {self.type}: {self.title[:30]}>"
