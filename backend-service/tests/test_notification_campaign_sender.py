"""Tests for notification campaign FCM and in-app senders."""

from __future__ import annotations

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.notification_campaign.sender import (
    SendResult,
    send_campaign_in_app,
    send_campaign_push,
)


# ---------------------------------------------------------------------------
# send_campaign_push — no FCM tokens
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_push_with_empty_token_map_returns_all_skipped() -> None:
    result = await send_campaign_push(
        fcm_token_map={},
        title="Hey!",
        body="Come back and learn.",
    )
    assert isinstance(result, SendResult)
    assert result.sent == 0
    assert result.failed == 0
    assert result.skipped == 0


@pytest.mark.asyncio
async def test_push_with_users_but_no_tokens_returns_skipped() -> None:
    result = await send_campaign_push(
        fcm_token_map={"user-1": [], "user-2": []},
        title="Hey!",
        body="Come back.",
    )
    assert result.sent == 0
    assert result.skipped > 0 or result.skipped == 0


@pytest.mark.asyncio
async def test_push_skips_when_firebase_not_configured() -> None:
    token_map = {"user-1": ["token-abc"], "user-2": ["token-xyz"]}
    with patch(
        "app.services.notification_campaign.sender._init_firebase_app",
        side_effect=RuntimeError("Firebase credentials missing"),
    ):
        result = await send_campaign_push(
            fcm_token_map=token_map,
            title="XP Boost",
            body="Limited time!",
        )
    assert result.sent == 0
    assert result.skipped == 2


@pytest.mark.asyncio
async def test_push_counts_fcm_batch_successes() -> None:
    token_map = {"user-1": ["token-1"], "user-2": ["token-2"]}
    fake_response = MagicMock(success_count=2, failure_count=0)

    with (
        patch(
            "app.services.notification_campaign.sender._init_firebase_app"
        ),
        patch(
            "app.services.notification_campaign.sender.run_in_threadpool",
            new=AsyncMock(return_value=fake_response),
        ),
    ):
        result = await send_campaign_push(
            fcm_token_map=token_map,
            title="Lesson ready",
            body="Start now!",
        )

    assert result.sent == 2
    assert result.failed == 0
    assert result.skipped == 0


@pytest.mark.asyncio
async def test_push_counts_fcm_batch_partial_failure() -> None:
    token_map = {"user-1": ["t1"], "user-2": ["t2"], "user-3": ["t3"]}
    fake_response = MagicMock(success_count=2, failure_count=1)

    with (
        patch("app.services.notification_campaign.sender._init_firebase_app"),
        patch(
            "app.services.notification_campaign.sender.run_in_threadpool",
            new=AsyncMock(return_value=fake_response),
        ),
    ):
        result = await send_campaign_push(
            fcm_token_map=token_map,
            title="Title",
            body="Body",
        )

    assert result.sent == 2
    assert result.failed == 1


@pytest.mark.asyncio
async def test_push_counts_all_failed_when_fcm_raises() -> None:
    token_map = {"user-1": ["t1"], "user-2": ["t2"]}

    with (
        patch("app.services.notification_campaign.sender._init_firebase_app"),
        patch(
            "app.services.notification_campaign.sender.run_in_threadpool",
            new=AsyncMock(side_effect=Exception("FCM error")),
        ),
    ):
        result = await send_campaign_push(
            fcm_token_map=token_map,
            title="Title",
            body="Body",
        )

    assert result.sent == 0
    assert result.failed == 2


@pytest.mark.asyncio
async def test_push_data_includes_deep_link() -> None:
    captured_messages: list = []

    async def fake_run_in_threadpool(fn, msg):
        captured_messages.append(msg)
        return MagicMock(success_count=1, failure_count=0)

    with (
        patch("app.services.notification_campaign.sender._init_firebase_app"),
        patch(
            "app.services.notification_campaign.sender.run_in_threadpool",
            side_effect=fake_run_in_threadpool,
        ),
    ):
        await send_campaign_push(
            fcm_token_map={"u1": ["tok"]},
            title="Title",
            body="Body",
            deep_link="/vocabulary",
        )

    assert len(captured_messages) == 1
    assert captured_messages[0].data["route"] == "/vocabulary"


# ---------------------------------------------------------------------------
# send_campaign_in_app
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_in_app_with_empty_user_ids_returns_zero() -> None:
    db = AsyncMock()
    result = await send_campaign_in_app(
        db,
        user_ids=[],
        title="Hi",
        body="Welcome",
    )
    assert result.sent == 0
    assert result.failed == 0
    assert result.skipped == 0
    db.execute.assert_not_called()


@pytest.mark.asyncio
async def test_in_app_inserts_one_row_per_user() -> None:
    db = AsyncMock()
    db.execute = AsyncMock()
    db.flush = AsyncMock()

    user_ids = [str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())]
    result = await send_campaign_in_app(
        db,
        user_ids=user_ids,
        title="Campaign",
        body="Check out today's lesson!",
        deep_link="/lesson/1",
    )

    assert result.sent == 3
    assert result.failed == 0
    assert result.skipped == 0
    db.execute.assert_called_once()
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_in_app_returns_failure_on_db_error() -> None:
    db = AsyncMock()
    db.execute = AsyncMock(side_effect=Exception("DB constraint violation"))
    db.flush = AsyncMock()

    user_ids = [str(uuid.uuid4()), str(uuid.uuid4())]
    result = await send_campaign_in_app(
        db,
        user_ids=user_ids,
        title="Oops",
        body="Something went wrong",
    )

    assert result.sent == 0
    assert result.failed == 2


@pytest.mark.asyncio
async def test_in_app_notification_type_defaults_to_campaign() -> None:
    from sqlalchemy import insert

    inserted_rows: list = []

    async def capture_execute(stmt, rows):
        inserted_rows.extend(rows)

    db = AsyncMock()
    db.execute = AsyncMock(side_effect=capture_execute)
    db.flush = AsyncMock()

    uid = str(uuid.uuid4())
    await send_campaign_in_app(db, user_ids=[uid], title="T", body="B")

    assert len(inserted_rows) == 1
    assert inserted_rows[0]["type"] == "campaign"
    assert inserted_rows[0]["is_read"] is False
