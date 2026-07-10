"""Schemas for synced mistake notebook entries."""

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

MistakeStatus = Literal["open", "reviewed"]


class MistakeNotebookEntryCreate(BaseModel):
    """Payload accepted from Flutter's current local mistake entry shape."""

    id: str | None = Field(
        default=None,
        max_length=128,
        pattern=r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$",
    )
    source_type: str = Field(min_length=1, max_length=80)
    source_id: str = Field(min_length=1, max_length=255)
    source_title: str = Field(default="", max_length=500)
    question: str = Field(min_length=1, max_length=5000)
    selected_answer: str = Field(default="", max_length=5000)
    correct_answer: str = Field(default="", max_length=5000)
    explanation: str = Field(default="", max_length=5000)
    skill: str = Field(default="general", max_length=80)
    metadata: dict[str, Any] | None = None

    @field_validator(
        "id",
        "source_type",
        "source_id",
        "source_title",
        "question",
        "selected_answer",
        "correct_answer",
        "explanation",
        "skill",
    )
    @classmethod
    def strip_text(cls, value: str | None) -> str | None:
        if value is None:
            return value
        return value.strip()

    @field_validator("id")
    @classmethod
    def reject_uuid_like_client_id(cls, value: str | None) -> str | None:
        if not value:
            return value
        try:
            uuid.UUID(value)
        except ValueError:
            return value
        raise ValueError("id must be a stable client id, not a server UUID")


class MistakeNotebookEntryResponse(BaseModel):
    """Mistake entry returned to Flutter and future web clients."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    source_type: str
    source_id: str
    source_title: str
    question: str
    selected_answer: str
    correct_answer: str
    explanation: str
    skill: str
    status: MistakeStatus
    created_at: datetime
    updated_at: datetime
    reviewed_at: datetime | None = None
    review_count: int
    attempt_count: int
    metadata: dict[str, Any] | None = None
