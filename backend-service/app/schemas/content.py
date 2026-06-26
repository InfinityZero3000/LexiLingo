"""
Schemas for Grammar, Question Bank, and Test Exams.
"""

import json
from datetime import datetime
from typing import Any
from pydantic import BaseModel, ConfigDict, Field, UUID4, field_validator


def _coerce_json_list(value: Any) -> list[Any] | None:
    if value is None:
        return None
    if isinstance(value, list):
        return value
    if isinstance(value, tuple | set):
        return list(value)
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return [text]
        return _coerce_json_list(parsed)
    return [value]


def _coerce_tags(value: Any) -> list[str] | None:
    if value is None:
        return None
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return [tag.strip() for tag in text.split(",") if tag.strip()]
        return _coerce_tags(parsed)
    if isinstance(value, dict):
        tags: list[str] = []
        for key, item in value.items():
            if item is None or item is False:
                continue
            if item is True:
                tags.append(str(key))
            elif isinstance(item, list):
                tags.extend(str(tag) for tag in item if tag is not None)
            else:
                tags.append(str(item))
        return tags
    if isinstance(value, list | tuple | set):
        return [str(item) for item in value if item is not None]
    return [str(value)]


# ------------------- Grammar -------------------

class GrammarBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    level: str = Field(default="A1")
    topic: str | None = None
    summary: str | None = None
    content: str
    examples: list[Any] | None = None
    tags: list[str] | None = None
    is_active: bool = True

    @field_validator("examples", mode="before")
    @classmethod
    def coerce_examples(cls, value: Any) -> list[Any] | None:
        return _coerce_json_list(value)

    @field_validator("tags", mode="before")
    @classmethod
    def coerce_tags(cls, value: Any) -> list[str] | None:
        return _coerce_tags(value)


class GrammarCreate(GrammarBase):
    pass


class GrammarUpdate(BaseModel):
    title: str | None = None
    level: str | None = None
    topic: str | None = None
    summary: str | None = None
    content: str | None = None
    examples: list[Any] | None = None
    tags: list[str] | None = None
    is_active: bool | None = None


class GrammarResponse(GrammarBase):
    id: UUID4
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ------------------- Question Bank -------------------

class QuestionBase(BaseModel):
    prompt: str
    question_type: str = "mcq"
    options: list[Any] | None = None
    answer: Any | None = None
    explanation: str | None = None
    difficulty_level: str = "A1"
    tags: list[str] | None = None
    grammar_id: UUID4 | None = None
    is_active: bool = True

    @field_validator("options", mode="before")
    @classmethod
    def coerce_options(cls, value: Any) -> list[Any] | None:
        return _coerce_json_list(value)

    @field_validator("tags", mode="before")
    @classmethod
    def coerce_tags(cls, value: Any) -> list[str] | None:
        return _coerce_tags(value)


class QuestionCreate(QuestionBase):
    pass


class QuestionUpdate(BaseModel):
    prompt: str | None = None
    question_type: str | None = None
    options: list[Any] | None = None
    answer: Any | None = None
    explanation: str | None = None
    difficulty_level: str | None = None
    tags: list[str] | None = None
    grammar_id: UUID4 | None = None
    is_active: bool | None = None


class QuestionResponse(QuestionBase):
    id: UUID4
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ------------------- Test Exams -------------------

class TestExamBase(BaseModel):
    title: str
    description: str | None = None
    level: str = "A1"
    duration_minutes: int = 20
    passing_score: int = 70
    question_ids: list[UUID4] | None = None
    is_published: bool = False

    @field_validator("question_ids", mode="before")
    @classmethod
    def coerce_question_ids(cls, value: Any) -> list[Any] | None:
        return _coerce_json_list(value)


class TestExamCreate(TestExamBase):
    pass


class TestExamUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    level: str | None = None
    duration_minutes: int | None = None
    passing_score: int | None = None
    question_ids: list[UUID4] | None = None
    is_published: bool | None = None


class TestExamResponse(TestExamBase):
    id: UUID4
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
