"""Schemas for the Ranking/Gamification Agent job workflow."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator


# ---------------------------------------------------------------------------
# Per-type job configs
# ---------------------------------------------------------------------------

class LeagueResetConfig(BaseModel):
    job_type: Literal["league_reset"] = "league_reset"
    week_start: str | None = Field(
        None,
        description="ISO date (YYYY-MM-DD) for the Monday of the target week. "
        "Defaults to the most recently completed week.",
    )


class XPEventConfig(BaseModel):
    job_type: Literal["xp_event"] = "xp_event"
    name: str = Field(..., min_length=1, max_length=100)
    multiplier: float = Field(2.0, ge=1.1, le=5.0)
    duration_hours: int = Field(24, ge=1, le=168)
    target: str = Field(
        "all",
        description=(
            "'all', 'league:<name>' (e.g. 'league:gold'), "
            "or 'cefr:<level>' (e.g. 'cefr:B1')"
        ),
    )

    @model_validator(mode="after")
    def _validate_target(self) -> "XPEventConfig":
        t = self.target
        if t == "all":
            return self
        if t.startswith("league:"):
            valid = {"bronze", "silver", "gold", "platinum", "sapphire", "ruby", "amethyst", "master"}
            league = t.split(":", 1)[1]
            if league not in valid:
                raise ValueError(f"Unknown league '{league}'")
        elif t.startswith("cefr:"):
            valid_cefr = {"A1", "A2", "B1", "B2", "C1", "C2"}
            level = t.split(":", 1)[1].upper()
            if level not in valid_cefr:
                raise ValueError(f"Unknown CEFR level '{level}'")
        else:
            raise ValueError("target must be 'all', 'league:<name>', or 'cefr:<level>'")
        return self


class AchievementBatchCriteria(BaseModel):
    min_streak: int | None = Field(None, ge=0)
    min_vocabulary_mastered: int | None = Field(None, ge=0)
    leagues: list[str] | None = None
    cefr_levels: list[str] | None = None


class AchievementBatchConfig(BaseModel):
    job_type: Literal["achievement_batch"] = "achievement_batch"
    achievement_slugs: list[str] = Field(..., min_length=1)
    criteria: AchievementBatchCriteria = Field(default_factory=AchievementBatchCriteria)


# ---------------------------------------------------------------------------
# Job create — union discriminated by job_type
# ---------------------------------------------------------------------------

class RankingAgentJobCreate(BaseModel):
    job_type: str
    config: dict[str, Any] = Field(default_factory=dict)
    use_ai_insights: bool = Field(
        False,
        description="If True, Groq (qwen3-32b) will generate a short insight commentary "
        "during the validating phase. Skipped gracefully if all API keys are rate-limited.",
    )

    @model_validator(mode="after")
    def _parse_config(self) -> "RankingAgentJobCreate":
        jt = self.job_type
        cfg = {"job_type": jt, **self.config}
        if jt == "league_reset":
            LeagueResetConfig.model_validate(cfg)
        elif jt == "xp_event":
            XPEventConfig.model_validate(cfg)
        elif jt == "achievement_batch":
            AchievementBatchConfig.model_validate(cfg)
        else:
            raise ValueError(f"Unknown job_type '{jt}'")
        return self


# ---------------------------------------------------------------------------
# Response
# ---------------------------------------------------------------------------

class RankingAgentJobResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    job_type: str
    status: str
    progress: dict[str, Any]
    config: dict[str, Any]
    artifact: dict[str, Any] | None
    warnings: list[str]
    blocking_errors: list[str]
    created_entity_ids: dict[str, Any]
    celery_task_id: str | None
    error_message: str | None
    requested_by_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
    started_at: datetime | None
    completed_at: datetime | None
