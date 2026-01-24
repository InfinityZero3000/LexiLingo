"""
Vocabulary Models
"""

import uuid
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Text, ForeignKey, Float
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class Vocabulary(Base):
    """Vocabulary word model."""
    
    __tablename__ = "vocabulary"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    
    word: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    translation: Mapped[str] = mapped_column(String(255), nullable=True)
    pronunciation: Mapped[str] = mapped_column(String(255), nullable=True)  # IPA or phonetic
    
    example_sentence: Mapped[str] = mapped_column(Text, nullable=True)
    
    language: Mapped[str] = mapped_column(String(10), nullable=False)  # en, vi
    difficulty: Mapped[str] = mapped_column(String(20), nullable=True)  # easy, medium, hard
    
    audio_url: Mapped[str] = mapped_column(String(500), nullable=True)
    image_url: Mapped[str] = mapped_column(String(500), nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<Vocabulary {self.word}>"


class UserVocabulary(Base):
    """User's personal vocabulary (flashcards)."""
    
    __tablename__ = "user_vocabulary"
    
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
    
    vocabulary_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("vocabulary.id", ondelete="CASCADE"),
        nullable=False
    )
    
    # Spaced repetition algorithm data
    status: Mapped[str] = mapped_column(String(20), default="learning")  # learning, reviewing, mastered
    review_count: Mapped[int] = mapped_column(Integer, default=0)
    next_review_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    ease_factor: Mapped[float] = mapped_column(Float, default=2.5)  # SM-2 algorithm
    interval_days: Mapped[int] = mapped_column(Integer, default=0)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<UserVocabulary user={self.user_id} vocab={self.vocabulary_id}>"
