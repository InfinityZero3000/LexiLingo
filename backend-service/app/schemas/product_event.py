import json
import math
from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

ALLOWED_PROPERTY_KEYS = {
    "achievement_count",
    "completed",
    "destination",
    "due_count",
    "error_type",
    "level",
    "message_id",
    "mistakes_saved",
    "score",
    "story_id",
    "streak",
    "surface",
    "task_type",
    "total_xp",
    "words_saved",
}


class ProductEventCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    event_id: UUID
    event_name: str = Field(min_length=1, max_length=100, pattern=r"^[a-z][a-z0-9_]*$")
    properties: dict[str, Any] = Field(default_factory=dict)
    source: str = Field(min_length=1, max_length=50, pattern=r"^[a-z][a-z0-9_]*$")
    client_timestamp: datetime

    @field_validator("properties")
    @classmethod
    def validate_properties(cls, value: dict[str, Any]) -> dict[str, Any]:
        if len(value) > 16 or set(value) - ALLOWED_PROPERTY_KEYS:
            raise ValueError("properties contain unsupported keys")
        for item in value.values():
            if item is None or isinstance(item, bool | int):
                continue
            if isinstance(item, float):
                if math.isfinite(item):
                    continue
                raise ValueError("properties contain a non-finite number")
            if isinstance(item, str) and len(item) <= 100:
                continue
            raise ValueError("properties contain an unsupported value")
        if len(json.dumps(value, separators=(",", ":")).encode()) > 2048:
            raise ValueError("properties exceed 2048 bytes")
        return value

    @field_validator("client_timestamp")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("client_timestamp must include a timezone")
        return value


class ProductEventBatchCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    events: list[ProductEventCreate] = Field(min_length=1, max_length=20)


class ProductEventBatchResponse(BaseModel):
    accepted: int
