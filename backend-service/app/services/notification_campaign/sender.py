"""FCM batch sender for Notification Campaign Agent."""

from __future__ import annotations

import logging
from dataclasses import dataclass

from fastapi.concurrency import run_in_threadpool
from firebase_admin import messaging

from app.core.firebase_auth import _init_firebase_app

logger = logging.getLogger(__name__)

_FCM_BATCH_SIZE = 500  # FCM multicast supports up to 500 tokens per call


@dataclass
class SendResult:
    sent: int
    failed: int
    skipped: int


async def send_campaign_push(
    *,
    fcm_token_map: dict[str, list[str]],
    title: str,
    body: str,
    notification_type: str = "campaign",
    deep_link: str | None = None,
) -> SendResult:
    """Send a push notification campaign to all users in fcm_token_map."""
    all_tokens = [token for tokens in fcm_token_map.values() for token in tokens]
    if not all_tokens:
        logger.info("Campaign send skipped — no FCM tokens in segment")
        return SendResult(sent=0, failed=0, skipped=len(fcm_token_map))

    try:
        _init_firebase_app()
    except Exception as exc:
        logger.warning("Firebase not configured; skipping campaign push: %s", exc)
        return SendResult(sent=0, failed=0, skipped=len(all_tokens))

    data: dict[str, str] = {
        "type": notification_type,
        "route": deep_link or "/",
    }

    total_sent = 0
    total_failed = 0

    # Batch in chunks of FCM_BATCH_SIZE
    for i in range(0, len(all_tokens), _FCM_BATCH_SIZE):
        chunk = all_tokens[i : i + _FCM_BATCH_SIZE]
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data=data,
            tokens=chunk,
        )
        try:
            response = await run_in_threadpool(messaging.send_each_for_multicast, message)
            total_sent += int(getattr(response, "success_count", 0) or 0)
            total_failed += int(getattr(response, "failure_count", 0) or 0)
        except Exception as exc:
            logger.exception("FCM batch %d failed: %s", i // _FCM_BATCH_SIZE, exc)
            total_failed += len(chunk)

    logger.info(
        "Campaign push complete: sent=%d failed=%d total_tokens=%d",
        total_sent,
        total_failed,
        len(all_tokens),
    )
    return SendResult(sent=total_sent, failed=total_failed, skipped=0)


async def send_campaign_in_app(
    db,
    *,
    user_ids: list[str],
    title: str,
    body: str,
    notification_type: str = "campaign",
    deep_link: str | None = None,
) -> SendResult:
    """Create persisted Notification records for in-app broadcast."""
    import uuid
    from datetime import datetime, timezone

    from sqlalchemy import insert

    from app.models.notification import Notification

    if not user_ids:
        return SendResult(sent=0, failed=0, skipped=0)

    now = datetime.now(timezone.utc)
    rows = [
        {
            "id": uuid.uuid4(),
            "user_id": uuid.UUID(uid),
            "title": title,
            "body": body,
            "type": notification_type,
            "data": {"route": deep_link or "/", "campaign": True},
            "is_read": False,
            "created_at": now,
        }
        for uid in user_ids
    ]

    try:
        await db.execute(insert(Notification), rows)
        await db.flush()
        return SendResult(sent=len(rows), failed=0, skipped=0)
    except Exception as exc:
        logger.exception("In-app broadcast DB insert failed: %s", exc)
        return SendResult(sent=0, failed=len(rows), skipped=0)
