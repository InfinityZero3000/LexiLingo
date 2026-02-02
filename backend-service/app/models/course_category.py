"""
Course Category Model

Categories for organizing courses (e.g., Grammar, Vocabulary, Business English, etc.)
"""

import uuid
from datetime import datetime
from sqlalchemy import String, Integer, Boolean, DateTime, Text, Index
from sqlalchemy.orm import Mapped, mapped_column
from typing import Optional

from app.core.database import Base
from app.core.db_types import GUID


class CourseCategory(Base):
    """
    Course Category model for organizing courses.
    Examples: Grammar, Vocabulary, Business English, Travel English, etc.
    """
    
    __tablename__ = "course_categories"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    slug: Mapped[str] = mapped_column(String(100), nullable=False, unique=True, index=True)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # Display properties
    icon: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)  # Icon name or emoji
    color: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)  # Hex color code
    
    # Ordering and visibility
    order_index: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    
    # Metadata
    course_count: Mapped[int] = mapped_column(Integer, default=0)  # Denormalized count
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    # Add index for common queries
    __table_args__ = (
        Index('idx_category_active_order', 'is_active', 'order_index'),
    )
    
    def __repr__(self) -> str:
        return f"<CourseCategory {self.name}>"
