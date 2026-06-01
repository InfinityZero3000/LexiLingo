"""Schemas for user reminder preferences."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ReminderPreferenceResponse(BaseModel):
    """Current user's review reminder preferences."""

    model_config = ConfigDict(from_attributes=True)

    enabled: bool
    push_enabled: bool
    email_enabled: bool
    reminder_time_local: str
    timezone: str
    min_due_count: int
    email_cadence_days: int
    next_check_at: datetime
    last_push_sent_at: datetime | None = None
    last_email_sent_at: datetime | None = None


class ReminderPreferenceUpdate(BaseModel):
    """Partial update for review reminder preferences."""

    enabled: bool | None = None
    push_enabled: bool | None = None
    email_enabled: bool | None = None
    reminder_time_local: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    timezone: str | None = Field(default=None, min_length=1, max_length=64)
    min_due_count: int | None = Field(default=None, ge=1, le=1000)
    email_cadence_days: int | None = Field(default=None, ge=1, le=30)

    @field_validator("reminder_time_local")
    @classmethod
    def validate_time(cls, value: str | None) -> str | None:
        if value is None:
            return value

        hour, minute = [int(part) for part in value.split(":")]
        if hour > 23 or minute > 59:
            raise ValueError("reminder_time_local must be HH:MM")
        return value
