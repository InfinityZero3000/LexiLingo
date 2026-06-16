"""Schema validation tests for the Notification Campaign Agent."""

from __future__ import annotations

from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.schemas.notification_campaign import (
    AudienceFilters,
    NotificationCampaignJobCreate,
    NotificationContent,
)


# ---------------------------------------------------------------------------
# AudienceFilters
# ---------------------------------------------------------------------------


def test_audience_filters_defaults_require_fcm() -> None:
    filters = AudienceFilters()
    assert filters.has_fcm_token is True
    assert filters.leagues is None
    assert filters.cefr_levels is None


def test_audience_filters_accepts_valid_leagues() -> None:
    filters = AudienceFilters(leagues=["bronze", "gold", "master"])
    assert filters.leagues == ["bronze", "gold", "master"]


def test_audience_filters_rejects_unknown_league() -> None:
    with pytest.raises(ValidationError, match="Unknown leagues"):
        AudienceFilters(leagues=["diamond"])


def test_audience_filters_accepts_valid_cefr_levels() -> None:
    filters = AudienceFilters(cefr_levels=["A1", "B2"])
    assert filters.cefr_levels == ["A1", "B2"]


def test_audience_filters_rejects_unknown_cefr_level() -> None:
    with pytest.raises(ValidationError, match="Unknown CEFR levels"):
        AudienceFilters(cefr_levels=["Z9"])


def test_audience_filters_inactive_days_minimum_one() -> None:
    with pytest.raises(ValidationError):
        AudienceFilters(inactive_days=0)


def test_audience_filters_inactive_days_maximum_365() -> None:
    with pytest.raises(ValidationError):
        AudienceFilters(inactive_days=366)


def test_audience_filters_min_streak_cannot_be_negative() -> None:
    with pytest.raises(ValidationError):
        AudienceFilters(min_streak=-1)


# ---------------------------------------------------------------------------
# NotificationContent
# ---------------------------------------------------------------------------


def test_notification_content_requires_title() -> None:
    with pytest.raises(ValidationError):
        NotificationContent(title="", body="Something")


def test_notification_content_requires_body() -> None:
    with pytest.raises(ValidationError):
        NotificationContent(title="Hello", body="")


def test_notification_content_title_max_100_chars() -> None:
    with pytest.raises(ValidationError):
        NotificationContent(title="x" * 101, body="body text")


def test_notification_content_body_max_300_chars() -> None:
    with pytest.raises(ValidationError):
        NotificationContent(title="title", body="x" * 301)


def test_notification_content_defaults() -> None:
    content = NotificationContent(title="Learn today!", body="New lesson available.")
    assert content.notification_type == "campaign"
    assert content.deep_link is None
    assert content.use_ai_copy is False


# ---------------------------------------------------------------------------
# NotificationCampaignJobCreate
# ---------------------------------------------------------------------------


def test_targeted_push_job_create_valid() -> None:
    payload = NotificationCampaignJobCreate(
        job_type="targeted_push",
        config={
            "audience": {"type": "all"},
            "content": {"title": "Boost XP!", "body": "Double XP for next 24 hours!"},
        },
    )
    assert payload.job_type == "targeted_push"


def test_in_app_broadcast_job_create_valid() -> None:
    payload = NotificationCampaignJobCreate(
        job_type="in_app_broadcast",
        config={
            "audience": {"type": "segment", "filters": {"cefr_levels": ["A1", "A2"]}},
            "content": {"title": "Tip", "body": "Use flashcards daily!"},
        },
    )
    assert payload.job_type == "in_app_broadcast"


def test_scheduled_push_job_create_requires_send_at() -> None:
    with pytest.raises(ValidationError):
        NotificationCampaignJobCreate(
            job_type="scheduled_push",
            config={
                "audience": {"type": "all"},
                "content": {"title": "Hi", "body": "Reminder!"},
            },
        )


def test_scheduled_push_job_create_valid() -> None:
    send_at = datetime(2026, 12, 1, 9, 0, tzinfo=timezone.utc)
    payload = NotificationCampaignJobCreate(
        job_type="scheduled_push",
        config={
            "audience": {"type": "all"},
            "content": {"title": "Hi", "body": "Reminder!"},
            "send_at": send_at.isoformat(),
        },
    )
    assert payload.job_type == "scheduled_push"


def test_unknown_job_type_raises() -> None:
    with pytest.raises(ValidationError, match="Unknown job_type"):
        NotificationCampaignJobCreate(
            job_type="bulk_sms",
            config={},
        )


def test_targeted_push_missing_content_raises() -> None:
    with pytest.raises(ValidationError):
        NotificationCampaignJobCreate(
            job_type="targeted_push",
            config={"audience": {"type": "all"}},
        )
