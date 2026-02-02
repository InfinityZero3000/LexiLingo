"""
Proficiency Assessment Models

Database models for tracking user proficiency across multiple language skills.
This system provides a more accurate CEFR level assessment than simple XP accumulation.
"""

from sqlalchemy import Column, String, Integer, Float, DateTime, ForeignKey, Text, Boolean, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid
import enum

from app.models.user import Base


class SkillType(str, enum.Enum):
    """Core language skill types aligned with CEFR."""
    VOCABULARY = "vocabulary"
    GRAMMAR = "grammar"
    READING = "reading"
    LISTENING = "listening"
    SPEAKING = "speaking"
    WRITING = "writing"


class UserProficiencyProfile(Base):
    """
    User's overall proficiency profile.
    
    Tracks the multi-dimensional assessment of user's language abilities.
    The `assessed_level` is the official CEFR level based on proficiency tests,
    separate from the gamification XP system.
    """
    __tablename__ = "user_proficiency_profiles"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    
    # Official CEFR level based on proficiency assessment
    assessed_level = Column(String(5), default="A1", nullable=False)
    overall_score = Column(Float, default=0.0)
    
    # XP is separate from proficiency (for gamification)
    total_xp = Column(Integer, default=0)
    
    # Assessment statistics
    total_exercises_completed = Column(Integer, default=0)
    total_correct_exercises = Column(Integer, default=0)
    total_lessons_completed = Column(Integer, default=0)
    
    # Timestamps
    last_assessment_at = Column(DateTime, nullable=True)
    last_level_change_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    skill_scores = relationship("UserSkillScore", back_populates="profile", cascade="all, delete-orphan")
    level_history = relationship("UserLevelHistory", back_populates="profile", cascade="all, delete-orphan")
    
    @property
    def accuracy(self) -> float:
        """Calculate overall accuracy rate."""
        if self.total_exercises_completed == 0:
            return 0.0
        return self.total_correct_exercises / self.total_exercises_completed


class UserSkillScore(Base):
    """
    Individual skill scores for a user.
    
    Each skill (vocabulary, grammar, etc.) has its own score that
    contributes to the overall level assessment.
    """
    __tablename__ = "user_skill_scores"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    profile_id = Column(UUID(as_uuid=True), ForeignKey("user_proficiency_profiles.id", ondelete="CASCADE"), nullable=False, index=True)
    
    skill = Column(SQLEnum(SkillType), nullable=False)
    score = Column(Float, default=0.0)  # 0-100 scale
    confidence = Column(Float, default=0.0)  # 0-1 scale
    estimated_level = Column(String(5), default="A1")
    
    # Statistics for this skill
    exercises_completed = Column(Integer, default=0)
    correct_exercises = Column(Integer, default=0)
    
    # Trend tracking
    score_7d_ago = Column(Float, nullable=True)  # Score snapshot from 7 days ago
    score_30d_ago = Column(Float, nullable=True)  # Score snapshot from 30 days ago
    
    last_updated = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    profile = relationship("UserProficiencyProfile", back_populates="skill_scores")
    
    @property
    def accuracy(self) -> float:
        """Calculate accuracy for this skill."""
        if self.exercises_completed == 0:
            return 0.0
        return self.correct_exercises / self.exercises_completed
    
    @property
    def trend(self) -> str:
        """Get trend direction based on score changes."""
        if self.score_7d_ago is None:
            return "stable"
        diff = self.score - self.score_7d_ago
        if diff > 5:
            return "improving"
        elif diff < -5:
            return "declining"
        return "stable"


class UserLevelHistory(Base):
    """
    History of level changes for a user.
    
    Tracks when and why the user's level changed, enabling
    analysis of progression patterns.
    """
    __tablename__ = "user_level_history"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    profile_id = Column(UUID(as_uuid=True), ForeignKey("user_proficiency_profiles.id", ondelete="CASCADE"), nullable=False, index=True)
    
    previous_level = Column(String(5), nullable=False)
    new_level = Column(String(5), nullable=False)
    change_type = Column(String(20), nullable=False)  # 'promotion', 'demotion', 'initial'
    
    # Context at time of change
    overall_score = Column(Float, nullable=True)
    skill_scores_snapshot = Column(JSONB, nullable=True)  # Snapshot of all skill scores
    exercises_completed = Column(Integer, nullable=True)
    accuracy = Column(Float, nullable=True)
    
    reason = Column(Text, nullable=True)  # Description of why level changed
    triggered_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    profile = relationship("UserProficiencyProfile", back_populates="level_history")


class ExerciseAttempt(Base):
    """
    Individual exercise attempt tracking.
    
    Records each exercise the user completes for detailed analysis
    and skill score calculation.
    """
    __tablename__ = "exercise_attempts"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # Exercise details
    exercise_type = Column(String(50), nullable=False)  # vocab_fill_blank, grammar_choice, etc.
    skill = Column(SQLEnum(SkillType), nullable=False)
    difficulty_level = Column(String(5), nullable=False)  # CEFR level of the exercise
    
    # Result
    is_correct = Column(Boolean, nullable=False)
    score = Column(Float, nullable=False)  # 0-100
    time_spent_seconds = Column(Integer, default=0)
    
    # Context
    lesson_id = Column(UUID(as_uuid=True), ForeignKey("lessons.id", ondelete="SET NULL"), nullable=True)
    course_id = Column(UUID(as_uuid=True), ForeignKey("courses.id", ondelete="SET NULL"), nullable=True)
    
    # Metadata
    attempted_at = Column(DateTime, default=datetime.utcnow, index=True)
    
    # Additional data (wrong answer, hints used, etc.)
    attempt_metadata = Column(JSONB, nullable=True)


class LevelAssessmentTest(Base):
    """
    Formal level assessment test records.
    
    Tracks formal placement/assessment tests that users take
    for official level determination.
    """
    __tablename__ = "level_assessment_tests"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    
    test_type = Column(String(20), nullable=False)  # 'initial', 'quick', 'comprehensive'
    
    # Results
    assessed_level = Column(String(5), nullable=False)
    overall_score = Column(Float, nullable=False)
    skill_scores = Column(JSONB, nullable=False)  # {skill: score, ...}
    
    # Test metadata
    questions_count = Column(Integer, nullable=False)
    correct_count = Column(Integer, nullable=False)
    time_taken_seconds = Column(Integer, nullable=True)
    
    started_at = Column(DateTime, nullable=False)
    completed_at = Column(DateTime, default=datetime.utcnow)
    
    # Whether this assessment resulted in a level change
    level_changed = Column(Boolean, default=False)
    previous_level = Column(String(5), nullable=True)
