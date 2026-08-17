"""
Course, Unit, and Lesson Models
Extended for Phase 2: Advanced Content Management System
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Integer, Boolean, Text, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship, validates
from typing import List

from app.core.database import Base
from app.core.db_types import GUID, GUIDArray, TZDateTime, PortableJSON


def count_exercises(content) -> int:
    exercises = content.get("exercises") if isinstance(content, dict) else None
    return len(exercises) if isinstance(exercises, list) else 0


class Course(Base):
    """
    Course model with hierarchical content structure.
    Phase 2: Added tags, total_xp, estimated_duration, content_version.
    """
    
    __tablename__ = "courses"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    language: Mapped[str] = mapped_column(String(10), nullable=False)  # en, vi
    level: Mapped[str] = mapped_column(String(20), nullable=False, index=True)  # A1, A2, B1, B2, C1, C2
    
    # Category relationship
    category_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("course_categories.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )
    
    # Which of the six CEFR skills this course mainly exercises, used to
    # credit the right UserSkillScore on completion. NULL means "not
    # labelled yet" and falls back to guessing from tags — see
    # ProficiencyService.resolve_lesson_skill.
    skill: Mapped[str] = mapped_column(String(20), nullable=True)

    # Phase 2: Enhanced metadata
    tags: Mapped[dict] = mapped_column(PortableJSON, nullable=True)  # ["grammar", "vocabulary", "business"]
    total_xp: Mapped[int] = mapped_column(Integer, default=0)
    estimated_duration: Mapped[int] = mapped_column(Integer, default=0)  # minutes
    content_version: Mapped[int] = mapped_column(Integer, default=1)  # For cache invalidation
    
    total_lessons: Mapped[int] = mapped_column(Integer, default=0)
    thumbnail_url: Mapped[str] = mapped_column(String(500), nullable=True)
    
    is_published: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc)
    )
    
    # Relationships
    category: Mapped["CourseCategory"] = relationship("CourseCategory", foreign_keys=[category_id])
    units: Mapped[List["Unit"]] = relationship("Unit", back_populates="course", cascade="all, delete-orphan")
    
    def __repr__(self) -> str:
        return f"<Course {self.title}>"


class Unit(Base):
    """
    Unit model - Groups of lessons within a course.
    Phase 2: New hierarchical layer between Course and Lesson.
    """
    
    __tablename__ = "units"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    course_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("courses.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    
    # UI customization
    background_color: Mapped[str] = mapped_column(String(20), nullable=True)  # Hex color
    icon_url: Mapped[str] = mapped_column(String(500), nullable=True)
    
    total_lessons: Mapped[int] = mapped_column(Integer, default=0)
    
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc)
    )
    
    # Relationships
    course: Mapped["Course"] = relationship("Course", back_populates="units")
    lessons: Mapped[List["Lesson"]] = relationship("Lesson", back_populates="unit", cascade="all, delete-orphan")
    
    def __repr__(self) -> str:
        return f"<Unit {self.title}>"


class Lesson(Base):
    """
    Lesson model - smallest learning unit.
    Phase 2: Added content_data (JSONB), unlock_threshold, prerequisites, total_exercises.
    """
    
    __tablename__ = "lessons"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    course_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("courses.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    unit_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("units.id", ondelete="CASCADE"),
        nullable=True,
        index=True
    )
    
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)

    # Can-do statement (CEFR action-oriented / TBLT mission outcome), e.g.
    # "You can order food at a restaurant over the phone."
    outcome: Mapped[str] = mapped_column(Text, nullable=True)

    # Phase 2: Prerequisites and pass requirements
    prerequisites: Mapped[list] = mapped_column(GUIDArray(), nullable=True, default=[])
    pass_threshold: Mapped[int] = mapped_column(Integer, default=80)  # Minimum score to pass (%)
    
    # Lesson content stored as JSON
    content: Mapped[dict] = mapped_column(PortableJSON, nullable=True)
    content_version: Mapped[int] = mapped_column(Integer, default=1)  # For cache/offline invalidation
    
    estimated_minutes: Mapped[int] = mapped_column(Integer, default=10)
    xp_reward: Mapped[int] = mapped_column(Integer, default=10)
    total_exercises: Mapped[int] = mapped_column(Integer, default=0)
    
    lesson_type: Mapped[str] = mapped_column(String(50), default="lesson")  # lesson, practice, review, test

    # Overrides Course.skill for a single lesson (a listening lesson inside a
    # grammar course). NULL = inherit from the course.
    skill: Mapped[str] = mapped_column(String(20), nullable=True)


    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc)
    )
    
    # Relationships
    unit: Mapped["Unit"] = relationship("Unit", back_populates="lessons")

    @property
    def exercise_count(self) -> int:
        """Playable exercises in content — the single source of truth for
        "is this lesson learnable?"."""
        return count_exercises(self.content)

    @validates("content")
    def _sync_total_exercises(self, _key: str, content):
        """Keep the denormalized counter true no matter who writes content
        (admin routes, CRUD, content agent, seeds, scripts) — it used to be
        set by hand in some paths and left at 0 in others."""
        self.total_exercises = count_exercises(content)
        return content

    def __repr__(self) -> str:
        return f"<Lesson {self.title}>"


class MediaResource(Base):
    """
    Centralized media resource management.
    Phase 2: Avoid duplicate URLs across tables.
    """
    
    __tablename__ = "media_resources"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    resource_type: Mapped[str] = mapped_column(String(20), nullable=False)  # image, audio, video
    url: Mapped[str] = mapped_column(String(500), nullable=False, unique=True, index=True)
    filename: Mapped[str] = mapped_column(String(255), nullable=False)
    
    # Optional metadata
    duration: Mapped[int] = mapped_column(Integer, nullable=True)  # seconds (for audio/video)
    size: Mapped[int] = mapped_column(Integer, nullable=True)  # bytes
    mime_type: Mapped[str] = mapped_column(String(100), nullable=True)
    
    # Usage tracking
    reference_count: Mapped[int] = mapped_column(Integer, default=0)
    
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc))
    
    def __repr__(self) -> str:
        return f"<MediaResource {self.filename}>"


# Create composite indexes for efficient queries
Index('idx_course_level_published', Course.level, Course.is_published)
Index('idx_course_published_lang_level', Course.is_published, Course.language, Course.level)
Index('idx_course_published_created_at', Course.is_published, Course.created_at)
Index('idx_unit_course_order', Unit.course_id, Unit.order_index)
Index('idx_lesson_unit_order', Lesson.unit_id, Lesson.order_index)
Index('idx_lesson_course_order', Lesson.course_id, Lesson.order_index)
