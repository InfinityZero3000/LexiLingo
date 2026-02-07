"""
Content models for admin-managed grammar, questions, and test exams.
"""

import uuid
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, Text, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.db_types import GUID


class GrammarItem(Base):
    __tablename__ = "grammar_items"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    level: Mapped[str] = mapped_column(String(20), nullable=False, default="A1")
    topic: Mapped[str | None] = mapped_column(String(100), nullable=True)
    summary: Mapped[str | None] = mapped_column(String(500), nullable=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    examples: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # list of examples
    tags: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # list of tags
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    questions = relationship("QuestionItem", back_populates="grammar", lazy="noload")

    __table_args__ = (
        Index("ix_grammar_items_level", "level"),
        Index("ix_grammar_items_topic", "topic"),
    )


class QuestionItem(Base):
    __tablename__ = "question_bank"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    question_type: Mapped[str] = mapped_column(String(50), nullable=False, default="mcq")
    options: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # list of options
    answer: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    explanation: Mapped[str | None] = mapped_column(Text, nullable=True)
    difficulty_level: Mapped[str] = mapped_column(String(20), nullable=False, default="A1")
    tags: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    grammar_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("grammar_items.id", ondelete="SET NULL"), nullable=True, index=True
    )

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    grammar = relationship("GrammarItem", back_populates="questions", lazy="selectin")

    __table_args__ = (
        Index("ix_question_bank_level", "difficulty_level"),
        Index("ix_question_bank_type", "question_type"),
    )


class TestExam(Base):
    __tablename__ = "test_exams"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    level: Mapped[str] = mapped_column(String(20), nullable=False, default="A1")
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
    passing_score: Mapped[int] = mapped_column(Integer, nullable=False, default=70)
    question_ids: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # list of question UUIDs
    is_published: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        Index("ix_test_exams_level", "level"),
        Index("ix_test_exams_published", "is_published"),
    )
