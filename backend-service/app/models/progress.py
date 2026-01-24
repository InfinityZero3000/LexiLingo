"""
User Progress, Streak, and Learning Attempt Models
Extended for Phase 3: Smart Learning Engine & Spaced Repetition
"""

import uuid
from datetime import datetime, date
from sqlalchemy import String, Integer, DateTime, Date, ForeignKey, Boolean, Float, JSON, Text, Index
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
        nullable=False,
        index=True
    )
    
    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("courses.id", ondelete="CASCADE"),
        nullable=False,
        index=True
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


class LessonAttempt(Base):
    """
    Phase 3: Detailed lesson attempt tracking for AI analysis.
    Critical for understanding learning patterns and providing personalized feedback.
    """
    
    __tablename__ = "lesson_attempts"
    
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
        nullable=False,
        index=True
    )
    
    # Attempt details
    started_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    finished_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    score: Mapped[int] = mapped_column(Integer, default=0)  # 0-100
    passed: Mapped[bool] = mapped_column(Boolean, default=False)
    xp_earned: Mapped[int] = mapped_column(Integer, default=0)
    
    # Session metadata for AI
    total_questions: Mapped[int] = mapped_column(Integer, default=0)
    correct_answers: Mapped[int] = mapped_column(Integer, default=0)
    hints_used: Mapped[int] = mapped_column(Integer, default=0)
    lives_remaining: Mapped[int] = mapped_column(Integer, default=5)
    
    # Performance metrics
    time_spent_ms: Mapped[int] = mapped_column(Integer, default=0)
    avg_response_time_ms: Mapped[int] = mapped_column(Integer, default=0)
    
    # Device context
    device_type: Mapped[str] = mapped_column(String(20), nullable=True)  # ios, android, web
    
    def __repr__(self) -> str:
        return f"<LessonAttempt {self.id[:8]} score={self.score}>"


class QuestionAttempt(Base):
    """
    Phase 3: Individual question attempt tracking.
    Essential for fine-grained learning analytics and AI-powered recommendations.
    """
    
    __tablename__ = "question_attempts"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    
    lesson_attempt_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("lesson_attempts.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    question_id: Mapped[str] = mapped_column(String(255), nullable=False, index=True)  # Question identifier
    question_type: Mapped[str] = mapped_column(String(50), nullable=False)  # multiple_choice, fill_blank, etc.
    
    # Answer tracking
    user_answer: Mapped[str] = mapped_column(Text, nullable=True)  # JSON string or text
    correct_answer: Mapped[str] = mapped_column(Text, nullable=True)
    is_correct: Mapped[bool] = mapped_column(Boolean, default=False)
    
    # Performance metrics
    time_spent_ms: Mapped[int] = mapped_column(Integer, default=0)
    hint_used: Mapped[bool] = mapped_column(Boolean, default=False)
    attempt_number: Mapped[int] = mapped_column(Integer, default=1)  # For retry tracking
    
    # AI context
    confidence_score: Mapped[float] = mapped_column(Float, nullable=True)  # 0.0-1.0
    difficulty_rating: Mapped[str] = mapped_column(String(20), nullable=True)  # easy, medium, hard
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<QuestionAttempt {self.question_id} correct={self.is_correct}>"


class UserVocabKnowledge(Base):
    """
    Phase 3: Spaced Repetition System (SRS) for vocabulary.
    Implements SM-2 or FSRS algorithm for optimal review scheduling.
    """
    
    __tablename__ = "user_vocab_knowledge"
    
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
    
    vocab_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
        index=True
    )
    
    # SRS algorithm data
    strength: Mapped[float] = mapped_column(Float, default=0.0)  # 0.0-1.0 (0%=new, 100%=mastered)
    ease_factor: Mapped[float] = mapped_column(Float, default=2.5)  # SM-2 algorithm
    interval_days: Mapped[int] = mapped_column(Integer, default=0)  # Days until next review
    
    # Review tracking
    last_review_date: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    next_review_date: Mapped[datetime] = mapped_column(DateTime, nullable=True, index=True)
    review_count: Mapped[int] = mapped_column(Integer, default=0)
    consecutive_correct: Mapped[int] = mapped_column(Integer, default=0)
    
    # Performance history (JSON array of scores)
    review_history: Mapped[dict] = mapped_column(JSON, nullable=True)
    
    # Status
    mastery_level: Mapped[str] = mapped_column(String(20), default="learning")  # learning, reviewing, mastered
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    def __repr__(self) -> str:
        return f"<UserVocabKnowledge vocab={self.vocab_id} strength={self.strength:.2f}>"


class DailyReviewSession(Base):
    """
    Phase 3: Daily review session tracking.
    Manages the daily vocabulary review queue generated by SRS algorithm.
    """
    
    __tablename__ = "daily_review_sessions"
    
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
    
    review_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    
    # Session stats
    total_words: Mapped[int] = mapped_column(Integer, default=0)
    completed_words: Mapped[int] = mapped_column(Integer, default=0)
    correct_count: Mapped[int] = mapped_column(Integer, default=0)
    
    # Session metadata
    started_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    completed_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    is_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    
    # Vocabulary IDs in this session (JSON array)
    vocab_list: Mapped[dict] = mapped_column(JSON, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<DailyReviewSession {self.review_date} {self.completed_words}/{self.total_words}>"


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
    
    # Streak freeze (gamification)
    freeze_count: Mapped[int] = mapped_column(Integer, default=0)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    def __repr__(self) -> str:
        return f"<Streak user={self.user_id} current={self.current_streak}>"


# Create composite indexes for efficient queries
Index('idx_lesson_attempt_user_lesson', LessonAttempt.user_id, LessonAttempt.lesson_id)
Index('idx_question_attempt_lesson', QuestionAttempt.lesson_attempt_id, QuestionAttempt.question_id)
Index('idx_vocab_knowledge_user_next_review', UserVocabKnowledge.user_id, UserVocabKnowledge.next_review_date)
Index('idx_daily_review_user_date', DailyReviewSession.user_id, DailyReviewSession.review_date)
