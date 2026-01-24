"""
User Progress and Streak Models
"""

import uuid
from datetime import datetime, date
from sqlalchemy import String, Integer, DateTime, Date, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class UserProgress(Base):
    """User progress for lessons/courses."""
    
    __tablename__ = "user_progress"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    lesson_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("lessons.id", ondelete="CASCADE"),
        nullable=False
    )
    
    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("courses.id", ondelete="CASCADE"),
        nullable=False
    )
    
    status: Mapped[str] = mapped_column(
        String(20),
        default="not_started"
    )  # not_started, in_progress, completed
    
    score: Mapped[int] = mapped_column(Integer, default=0)  # 0-100
    completed_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    
    time_spent_seconds: Mapped[int] = mapped_column(Integer, default=0)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    def __repr__(self) -> str:
        return f"<UserProgress user={self.user_id} lesson={self.lesson_id}>"


class Streak(Base):
    """User learning streak tracker."""
    
    __tablename__ = "streaks"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True
    )
    
    current_streak: Mapped[int] = mapped_column(Integer, default=0)
    longest_streak: Mapped[int] = mapped_column(Integer, default=0)
    last_activity_date: Mapped[date] = mapped_column(Date, nullable=True)
    total_days_active: Mapped[int] = mapped_column(Integer, default=0)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    def __repr__(self) -> str:
        return f"<Streak user={self.user_id} current={self.current_streak}>"
