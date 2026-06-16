"""LangGraph state for the Notification Agent content generation pipeline."""

from __future__ import annotations

from typing import Any, TypedDict


class NotificationVariant(TypedDict):
    title: str
    body: str
    rationale: str


class NotificationAgentState(TypedDict):
    # Input
    original_title: str
    original_body: str
    notification_type: str
    audience_profile: dict[str, Any]

    # Derived
    audience_summary: str  # Human-readable summary built in analyze node

    # Generation
    variants: list[NotificationVariant]
    retries: int

    # Evaluation
    best_variant: NotificationVariant | None
    best_score: float

    # Output
    final_title: str
    final_body: str
    generation_skipped: bool
