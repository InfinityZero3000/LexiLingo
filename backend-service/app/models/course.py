"""
Course, Unit, and Lesson Models
Extended for Phase 2: Advanced Content Management System
"""

import uuid
from datetime import datetime
from sqlalchemy import String, Integer, Boolean, DateTime, Text, ForeignKey, JSON, Index, ARRAY
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from typing import List

from app.core.database import Base


class Course(Base):
    """
    Course model with hierarchical content structure.
    Phase 2: Added tags, total_xp, estimated_duration, content_version.
    """
    
    __tablename__ = "courses"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    language: Mapped[str] = mapped_column(String(10), nullable=False)  # en, vi
    level: Mapped[str] = mapped_column(String(20), nullable=False, index=True)  # A1, A2, B1, B2, C1, C2
    
    # Phase 2: Enhanced metadata
    tags: Mapped[dict] = mapped_column(JSON, nullable=True)  # ["grammar", "vocabulary", "business"]
    total_xp: Mapped[int] = mapped_column(Integer, default=0)
    estimated_duration: Mapped[int] = mapped_column(Integer, default=0)  # minutes
    content_version: Mapped[int] = mapped_column(Integer, default=1)  # For cache invalidation
    
    total_lessons: Mapped[int] = mapped_column(Integer, default=0)
    thumbnail_url: Mapped[str] = mapped_column(String(500), nullable=True)
    
    is_published: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    # Relationships
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
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    
    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
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
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    # Relationships
    course: Mapped["Course"] = relationship("Course", back_populates="units")
    lessons: Mapped[List["Lesson"]] = relationship("Lesson", back_populates="unit", cascade="all, delete-orphan")
    
    def __repr__(self) -> str:
        return f"<Unit {self.title}>"

threshold, prerequisites, total_exercises.
    """
    
    __tablename__ = "lessons"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    
    course_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("courses.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    unit_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("units.id", ondelete="CASCADE"),
        nullable=True,
        index=True
    )
    
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    
    # Phase 2: Prerequisites and pass requirements
    prerequisites: Mapped[list] = mapped_column(ARRAY(UUID(as_uuid=True)), nullable=True, default=[])
    pass_threshold: Mapped[int] = mapped_column(Integer, default=80)  # Minimum score to pass (%)
    
    # Lesson content stored as JSON
    content: Mapped[dict] = mapped_column(JSON, nullable=True)
    content_version: Mapped[int] = mapped_column(Integer, default=1)  # For cache/offline invalidation
    
    estimated_minutes: Mapped[int] = mapped_column(Integer, default=10)
    xp_reward: Mapped[int] = mapped_column(Integer, default=10)
    total_exercises: Mapped[int] = mapped_column(Integer, default=0)
    
    lesson_type: Mapped[str] = mapped_column(String(50), default="lesson")  # lesson, practice, review, test
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    # Relationships
    unit: Mapped["Unit"] = relationship("Unit", back_populates="lessons"updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    def __repr__(self) -> str:
        return f"<Lesson {self.title}>"


class MediaResource(Base):
    """
    Centralized media resource management.
    Phase 2: Avoid duplicate URLs across tables.
    """
    
    __tablename__ = "media_resources"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
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
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<MediaResource {self.filename}>"


# Create composite indexes for efficient queries
Index('idx_course_level_published', Course.level, Course.is_published)
Index('idx_unit_course_order', Unit.course_id, Unit.order_index)
Index('idx_lesson_unit_order', Lesson.unit_id, Lesson.order_index)
