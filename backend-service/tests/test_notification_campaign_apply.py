"""Unit tests for NotificationCampaignApplyService (mocked segments and senders)."""

from __future__ import annotations

import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.notification_campaign.apply import NotificationCampaignApplyService
from app.services.notification_campaign.sender import SendResult
from app.services.notification_campaign.segmenter import SegmentResult


def _make_job(
    job_type: str = "targeted_push",
    title: str = "Learn today!",
    body: str = "Open the app.",
    artifact: dict | None = None,
) -> SimpleNamespace:
    return SimpleNamespace(
        id=uuid.uuid4(),
        job_type=job_type,
        status="preview_ready",
        config={
            "content": {"title": title, "body": body, "notification_type": "campaign"},
            "audience": {"type": "all", "filters": {}},
        },
        artifact=artifact,
    )


def _make_segment(user_count: int = 5, token_count: int = 5) -> SegmentResult:
    user_ids = [str(uuid.uuid4()) for _ in range(user_count)]
    fcm_map = {uid: [f"tok-{i}"] for i, uid in enumerate(user_ids[:token_count])}
    return SegmentResult(
        user_ids=user_ids,
        fcm_token_map=fcm_map,
        audience_size=user_count,
        sample_users=[],
        filter_summary={},
    )


@pytest.mark.asyncio
async def test_targeted_push_delegates_to_push_sender() -> None:
    job = _make_job("targeted_push")
    segment = _make_segment(user_count=3, token_count=3)
    send_result = SendResult(sent=3, failed=0, skipped=0)

    db = AsyncMock()

    with (
        patch(
            "app.services.notification_campaign.apply.segment_users",
            new=AsyncMock(return_value=segment),
        ),
        patch(
            "app.services.notification_campaign.apply.send_campaign_push",
            new=AsyncMock(return_value=send_result),
        ),
        patch(
            "app.services.notification_campaign.apply.NotificationCampaignJobService.set_delivery_stats",
            new=AsyncMock(),
        ),
    ):
        result = await NotificationCampaignApplyService.apply(db, job)

    assert result["sent"] == 3
    assert result["failed"] == 0
    assert result["total"] == 3


@pytest.mark.asyncio
async def test_in_app_broadcast_delegates_to_in_app_sender() -> None:
    job = _make_job("in_app_broadcast")
    segment = _make_segment(user_count=10, token_count=0)
    send_result = SendResult(sent=10, failed=0, skipped=0)

    db = AsyncMock()

    with (
        patch(
            "app.services.notification_campaign.apply.segment_users",
            new=AsyncMock(return_value=segment),
        ),
        patch(
            "app.services.notification_campaign.apply.send_campaign_in_app",
            new=AsyncMock(return_value=send_result),
        ),
        patch(
            "app.services.notification_campaign.apply.NotificationCampaignJobService.set_delivery_stats",
            new=AsyncMock(),
        ),
    ):
        result = await NotificationCampaignApplyService.apply(db, job)

    assert result["sent"] == 10
    assert result["total"] == 10


@pytest.mark.asyncio
async def test_scheduled_push_delegates_to_push_sender() -> None:
    job = _make_job("scheduled_push")
    segment = _make_segment(user_count=2)
    send_result = SendResult(sent=2, failed=0, skipped=0)

    db = AsyncMock()

    with (
        patch(
            "app.services.notification_campaign.apply.segment_users",
            new=AsyncMock(return_value=segment),
        ),
        patch(
            "app.services.notification_campaign.apply.send_campaign_push",
            new=AsyncMock(return_value=send_result),
        ),
        patch(
            "app.services.notification_campaign.apply.NotificationCampaignJobService.set_delivery_stats",
            new=AsyncMock(),
        ),
    ):
        result = await NotificationCampaignApplyService.apply(db, job)

    assert result["sent"] == 2


@pytest.mark.asyncio
async def test_unknown_job_type_raises_value_error() -> None:
    job = _make_job("sms_blast")
    segment = _make_segment()

    db = AsyncMock()

    with (
        patch(
            "app.services.notification_campaign.apply.segment_users",
            new=AsyncMock(return_value=segment),
        ),
    ):
        with pytest.raises(ValueError, match="Unknown job_type"):
            await NotificationCampaignApplyService.apply(db, job)


@pytest.mark.asyncio
async def test_ai_copy_overrides_config_title_and_body() -> None:
    job = _make_job(
        "targeted_push",
        title="Original title",
        body="Original body",
        artifact={
            "ai_copy": {
                "title": "AI-generated title",
                "body": "AI-generated body",
            }
        },
    )
    segment = _make_segment(user_count=1)
    send_result = SendResult(sent=1, failed=0, skipped=0)

    captured_kwargs: list[dict] = []

    async def fake_push(**kwargs):
        captured_kwargs.append(kwargs)
        return send_result

    db = AsyncMock()

    with (
        patch(
            "app.services.notification_campaign.apply.segment_users",
            new=AsyncMock(return_value=segment),
        ),
        patch(
            "app.services.notification_campaign.apply.send_campaign_push",
            side_effect=fake_push,
        ),
        patch(
            "app.services.notification_campaign.apply.NotificationCampaignJobService.set_delivery_stats",
            new=AsyncMock(),
        ),
    ):
        await NotificationCampaignApplyService.apply(db, job)

    assert captured_kwargs[0]["title"] == "AI-generated title"
    assert captured_kwargs[0]["body"] == "AI-generated body"


@pytest.mark.asyncio
async def test_apply_total_equals_sent_plus_failed_plus_skipped() -> None:
    job = _make_job("targeted_push")
    segment = _make_segment(user_count=10, token_count=7)
    send_result = SendResult(sent=5, failed=2, skipped=3)

    db = AsyncMock()

    with (
        patch(
            "app.services.notification_campaign.apply.segment_users",
            new=AsyncMock(return_value=segment),
        ),
        patch(
            "app.services.notification_campaign.apply.send_campaign_push",
            new=AsyncMock(return_value=send_result),
        ),
        patch(
            "app.services.notification_campaign.apply.NotificationCampaignJobService.set_delivery_stats",
            new=AsyncMock(),
        ),
    ):
        result = await NotificationCampaignApplyService.apply(db, job)

    assert result["total"] == result["sent"] + result["failed"] + result["skipped"]
    assert result["total"] == 10


@pytest.mark.asyncio
async def test_apply_calls_set_delivery_stats_with_correct_values() -> None:
    job = _make_job("in_app_broadcast")
    segment = _make_segment(user_count=4, token_count=0)
    send_result = SendResult(sent=4, failed=0, skipped=0)

    db = AsyncMock()
    captured_stats: list[dict] = []

    async def fake_set_stats(db, job, *, sent, failed, skipped):
        captured_stats.append({"sent": sent, "failed": failed, "skipped": skipped})

    with (
        patch(
            "app.services.notification_campaign.apply.segment_users",
            new=AsyncMock(return_value=segment),
        ),
        patch(
            "app.services.notification_campaign.apply.send_campaign_in_app",
            new=AsyncMock(return_value=send_result),
        ),
        patch(
            "app.services.notification_campaign.apply.NotificationCampaignJobService.set_delivery_stats",
            side_effect=fake_set_stats,
        ),
    ):
        await NotificationCampaignApplyService.apply(db, job)

    assert len(captured_stats) == 1
    assert captured_stats[0]["sent"] == 4
    assert captured_stats[0]["failed"] == 0
    assert captured_stats[0]["skipped"] == 0
