"""
Vocabulary and Spaced Repetition System (SRS) Models
Phase 3: Intelligent Vocabulary Learning with SM-2 Algorithm
"""

import uuid
from datetime import datetime, timedelta
from sqlalchemy import String, Integer, DateTime, ForeignKey, Float, JSON, Text, Index, Enum as SQLEnum, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship
from typing import Optional
import enum

from app.core.database import Base
from app.core.db_types import GUID, GUIDArray


class VocabularyStatus(str, enum.Enum):
    """Status of vocabulary in user's collection"""
    LEARNING = "learning"      # Just added, < 3 reviews
    REVIEWING = "reviewing"    # 3+ reviews, not mastered
    MASTERED = "mastered"      # Ease factor >= 2.5, interval >= 21 days
    ARCHIVED = "archived"      # User archived


class PartOfSpeech(str, enum.Enum):
    """Part of speech categories"""
    NOUN = "noun"
    VERB = "verb"
    ADJECTIVE = "adjective"
    ADVERB = "adverb"
    PRONOUN = "pronoun"
    PREPOSITION = "preposition"
    CONJUNCTION = "conjunction"
    INTERJECTION = "interjection"
    PHRASE = "phrase"


class DifficultyLevel(str, enum.Enum):
    """CEFR difficulty levels"""
    A1 = "A1"
    A2 = "A2"
    B1 = "B1"
    B2 = "B2"
    C1 = "C1"
    C2 = "C2"


class VocabularyItem(Base):
    """
    Master vocabulary database - contains all available vocabulary words.
    Shared across all users, tied to specific courses/lessons.
    """
    
    __tablename__ = "vocabulary_items"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    # Core vocabulary data
    word: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    definition: Mapped[str] = mapped_column(Text, nullable=False)
    
    # Multilingual support
    translation: Mapped[dict] = mapped_column(JSON, nullable=True)
    # Example: {"vi": "xin chào", "examples": ["Hello, how are you?", "Hello world!"]}
    
    # Pronunciation
    pronunciation: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)  # IPA: /həˈloʊ/
    audio_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    
    # Classification
    part_of_speech: Mapped[str] = mapped_column(
        SQLEnum(PartOfSpeech, name="part_of_speech_enum"),
        nullable=False,
        index=True
    )
    difficulty_level: Mapped[str] = mapped_column(
        SQLEnum(DifficultyLevel, name="difficulty_level_enum"),
        nullable=False,
        index=True
    )
    
    # Related content
    course_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        GUID(),
        ForeignKey("courses.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )
    lesson_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        GUID(),
        ForeignKey("lessons.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )
    
    # Additional metadata
    usage_frequency: Mapped[int] = mapped_column(Integer, default=0)  # How often word appears
    tags: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)  # ["business", "travel", "casual"]
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    # Indexes for performance
    __table_args__ = (
        Index("ix_vocabulary_items_word_lower", "word"),
        Index("ix_vocabulary_items_course_difficulty", "course_id", "difficulty_level"),
    )


class UserVocabulary(Base):
    """
    User's personal vocabulary collection with SRS (Spaced Repetition System) data.
    Implements SuperMemo SM-2 algorithm for optimal review scheduling.
    """
    
    __tablename__ = "user_vocabulary"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    vocabulary_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("vocabulary_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    status: Mapped[str] = mapped_column(
        SQLEnum(VocabularyStatus, name="vocabulary_status_enum"),
        nullable=False,
        default=VocabularyStatus.LEARNING,
        index=True
    )
    
    # ===== SuperMemo SM-2 Algorithm Fields =====
    ease_factor: Mapped[float] = mapped_column(Float, default=2.5)
    # Range: 1.3 - 3.0 (typically)
    # Higher = easier to remember, longer intervals
    
    interval: Mapped[int] = mapped_column(Integer, default=1)
    # Days until next review (1, 6, then multiplied by ease_factor)
    
    repetitions: Mapped[int] = mapped_column(Integer, default=0)
    # Number of consecutive correct reviews
    
    next_review_date: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.utcnow() + timedelta(days=1),
        index=True
    )
    
    last_reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    
    # ===== Statistics =====
    total_reviews: Mapped[int] = mapped_column(Integer, default=0)
    correct_reviews: Mapped[int] = mapped_column(Integer, default=0)
    streak: Mapped[int] = mapped_column(Integer, default=0)  # Consecutive correct answers
    longest_streak: Mapped[int] = mapped_column(Integer, default=0)
    
    # Gamification
    total_xp_earned: Mapped[int] = mapped_column(Integer, default=0)
    
    # User notes
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    added_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    # Relationships
    vocabulary: Mapped["VocabularyItem"] = relationship("VocabularyItem")
    
    # Indexes for efficient queries
    __table_args__ = (
        Index("ix_user_vocabulary_user_status", "user_id", "status"),
        Index("ix_user_vocabulary_next_review", "user_id", "next_review_date"),
        Index("ix_user_vocabulary_unique", "user_id", "vocabulary_id", unique=True),
    )
    
    @property
    def is_due(self) -> bool:
        """Check if vocabulary is due for review"""
        return datetime.utcnow() >= self.next_review_date
    
    @property
    def accuracy(self) -> float:
        """Calculate accuracy percentage"""
        if self.total_reviews == 0:
            return 0.0
        return (self.correct_reviews / self.total_reviews) * 100


class VocabularyReview(Base):
    """
    Individual review records for analytics and progress tracking.
    Stores each review attempt with quality rating.
    """
    
    __tablename__ = "vocabulary_reviews"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_vocabulary_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("user_vocabulary.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    # SM-2 Quality rating (0-5)
    quality: Mapped[int] = mapped_column(Integer, nullable=False)
    """
    Quality scale (SuperMemo SM-2):
    5 - Perfect: Instant recall
    4 - Correct: After hesitation
    3 - Correct: With difficulty
    2 - Incorrect: But word remembered
    1 - Incorrect: Barely remembered
    0 - Complete blackout
    """
    
    # Performance metrics
    time_spent_ms: Mapped[int] = mapped_column(Integer, default=0)  # Milliseconds
    
    # SRS state after this review
    ease_factor_after: Mapped[float] = mapped_column(Float, nullable=True)
    interval_after: Mapped[int] = mapped_column(Integer, nullable=True)
    
    reviewed_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    
    # Indexes
    __table_args__ = (
        Index("ix_vocabulary_reviews_user_vocab_date", "user_vocabulary_id", "reviewed_at"),
    )


class VocabularyDeck(Base):
    """
    User-created custom vocabulary decks/collections.
    Phase 3: Allow users to organize vocabulary into themed groups.
    """
    
    __tablename__ = "vocabulary_decks"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # Deck settings
    is_public: Mapped[bool] = mapped_column(Boolean, default=False)  # Future: Share decks
    color: Mapped[str] = mapped_column(String(7), default="#2196F3")  # Hex color
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    __table_args__ = (
        Index("ix_vocabulary_decks_user", "user_id"),
    )


class VocabularyDeckItem(Base):
    """
    Junction table: Links vocabulary items to custom decks.
    Many-to-many relationship between UserVocabulary and VocabularyDeck.
    """
    
    __tablename__ = "vocabulary_deck_items"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    deck_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("vocabulary_decks.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    user_vocabulary_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("user_vocabulary.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    order: Mapped[int] = mapped_column(Integer, default=0)  # Custom ordering in deck
    
    added_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    __table_args__ = (
        Index("ix_vocabulary_deck_items_unique", "deck_id", "user_vocabulary_id", unique=True),
    )
