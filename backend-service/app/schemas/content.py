"""
Schemas for Grammar, Question Bank, and Test Exams.
"""

from typing import Optional, List
from datetime import datetime
from pydantic import BaseModel, Field, UUID4


# ------------------- Grammar -------------------

class GrammarBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    level: str = Field(default="A1")
    topic: Optional[str] = None
    summary: Optional[str] = None
    content: str
    examples: Optional[List[dict]] = None
    tags: Optional[List[str]] = None
    is_active: bool = True


class GrammarCreate(GrammarBase):
    pass


class GrammarUpdate(BaseModel):
    title: Optional[str] = None
    level: Optional[str] = None
    topic: Optional[str] = None
    summary: Optional[str] = None
    content: Optional[str] = None
    examples: Optional[List[dict]] = None
    tags: Optional[List[str]] = None
    is_active: Optional[bool] = None


class GrammarResponse(GrammarBase):
    id: UUID4
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ------------------- Question Bank -------------------

class QuestionBase(BaseModel):
    prompt: str
    question_type: str = "mcq"
    options: Optional[List[dict]] = None
    answer: Optional[dict] = None
    explanation: Optional[str] = None
    difficulty_level: str = "A1"
    tags: Optional[List[str]] = None
    grammar_id: Optional[UUID4] = None
    is_active: bool = True


class QuestionCreate(QuestionBase):
    pass


class QuestionUpdate(BaseModel):
    prompt: Optional[str] = None
    question_type: Optional[str] = None
    options: Optional[List[dict]] = None
    answer: Optional[dict] = None
    explanation: Optional[str] = None
    difficulty_level: Optional[str] = None
    tags: Optional[List[str]] = None
    grammar_id: Optional[UUID4] = None
    is_active: Optional[bool] = None


class QuestionResponse(QuestionBase):
    id: UUID4
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ------------------- Test Exams -------------------

class TestExamBase(BaseModel):
    title: str
    description: Optional[str] = None
    level: str = "A1"
    duration_minutes: int = 20
    passing_score: int = 70
    question_ids: Optional[List[UUID4]] = None
    is_published: bool = False


class TestExamCreate(TestExamBase):
    pass


class TestExamUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    level: Optional[str] = None
    duration_minutes: Optional[int] = None
    passing_score: Optional[int] = None
    question_ids: Optional[List[UUID4]] = None
    is_published: Optional[bool] = None


class TestExamResponse(TestExamBase):
    id: UUID4
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
