"""Schemas for the recommendation API."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class RecommendationItem(BaseModel):
    item_id: str
    item_type: str
    title: str = ""
    description: str = ""
    topic: str | None = None
    level: str | None = None
    skill: str | None = None
    score: float = 0.0
    reason: str = ""
    features: dict[str, float] = Field(default_factory=dict)
    payload: dict[str, Any] = Field(default_factory=dict)


class RecommendationResponse(BaseModel):
    items: list[RecommendationItem]
    surface: str
    cache_hit: bool = False
    degraded: bool = False
    latency_ms: int = 0
