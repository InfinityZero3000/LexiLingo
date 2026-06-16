"""Schemas for the Notification Campaign Agent job workflow."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator

VALID_LEAGUES = {"bronze", "silver", "gold", "platinum", "sapphire", "ruby", "amethyst", "master"}
VALID_CEFR = {"A1", "A2", "B1", "B2", "C1", "C2"}


# ---------------------------------------------------------------------------
# Audience filters
# ---------------------------------------------------------------------------

class AudienceFilters(BaseModel):
    leagues: list[str] | None = Field(None, description="Filter by league names")
    cefr_levels: list[str] | None = Field(None, description="Filter by CEFR proficiency levels")
    min_streak: int | None = Field(None, ge=0, description="Minimum streak days")
    inactive_days: int | None = Field(
        None, ge=1, le=365, description="Users inactive for at least N days"
    )
    has_fcm_token: bool = Field(True, description="Only include users with FCM tokens")

    @model_validator(mode="after")
    def _validate_values(self) -> "AudienceFilters":
        if self.leagues:
            invalid = set(self.leagues) - VALID_LEAGUES
            if invalid:
                raise ValueError(f"Unknown leagues: {invalid}")
        if self.cefr_levels:
            invalid = {l.upper() for l in self.cefr_levels} - VALID_CEFR
            if invalid:
                raise ValueError(f"Unknown CEFR levels: {invalid}")
        return self


class AudienceConfig(BaseModel):
    type: Literal["all", "segment"] = "all"
    filters: AudienceFilters = Field(default_factory=AudienceFilters)


# ---------------------------------------------------------------------------
# Notification content
# ---------------------------------------------------------------------------

class NotificationContent(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    body: str = Field(..., min_length=1, max_length=300)
    notification_type: str = Field(
        "campaign",
        description="Notification type tag (campaign, announcement, reward, etc.)",
    )
    deep_link: str | None = Field(None, description="In-app deep link route (e.g. /vocabulary)")
    use_ai_copy: bool = Field(
        False,
        description="If True, ai-service will rewrite the copy using Groq to personalize for the audience segment.",
    )


# ---------------------------------------------------------------------------
# Per job type configs
# ---------------------------------------------------------------------------

class TargetedPushConfig(BaseModel):
    job_type: Literal["targeted_push"] = "targeted_push"
    audience: AudienceConfig = Field(default_factory=AudienceConfig)
    content: NotificationContent


class InAppBroadcastConfig(BaseModel):
    job_type: Literal["in_app_broadcast"] = "in_app_broadcast"
    audience: AudienceConfig = Field(default_factory=AudienceConfig)
    content: NotificationContent


class ScheduledPushConfig(BaseModel):
    job_type: Literal["scheduled_push"] = "scheduled_push"
    audience: AudienceConfig = Field(default_factory=AudienceConfig)
    content: NotificationContent
    send_at: datetime = Field(..., description="UTC datetime to send the push")


# ---------------------------------------------------------------------------
# Job create — discriminated by job_type
# ---------------------------------------------------------------------------

class NotificationCampaignJobCreate(BaseModel):
    job_type: str
    config: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _parse_config(self) -> "NotificationCampaignJobCreate":
        jt = self.job_type
        cfg = {"job_type": jt, **self.config}
        if jt == "targeted_push":
            TargetedPushConfig.model_validate(cfg)
        elif jt == "in_app_broadcast":
            InAppBroadcastConfig.model_validate(cfg)
        elif jt == "scheduled_push":
            ScheduledPushConfig.model_validate(cfg)
        else:
            raise ValueError(f"Unknown job_type '{jt}'")
        return self


# ---------------------------------------------------------------------------
# Response
# ---------------------------------------------------------------------------

class NotificationCampaignJobResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    job_type: str
    status: str
    progress: dict[str, Any]
    config: dict[str, Any]
    artifact: dict[str, Any] | None
    warnings: list[str]
    blocking_errors: list[str]
    delivery_stats: dict[str, Any]
    celery_task_id: str | None
    error_message: str | None
    requested_by_id: uuid.UUID | None
    scheduled_at: datetime | None
    created_at: datetime
    updated_at: datetime
    started_at: datetime | None
    completed_at: datetime | None
