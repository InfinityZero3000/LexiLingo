"""Firebase Cloud Messaging push notification service."""

from __future__ import annotations

import logging

from fastapi.concurrency import run_in_threadpool
from firebase_admin import messaging

from app.core.firebase_auth import _init_firebase_app

logger = logging.getLogger(__name__)


class PushNotificationService:
    """Small FCM wrapper that fails closed when Firebase is not configured."""

    async def send_review_reminder(
        self,
        *,
        tokens: list[str],
        due_count: int,
        title: str,
        body: str,
        data: dict[str, str] | None = None,
    ) -> bool:
        """Send a review reminder to FCM device tokens."""
        clean_tokens = [token for token in tokens if token]
        if not clean_tokens:
            logger.info("No FCM tokens available for review reminder")
            return False

        try:
            _init_firebase_app()
        except Exception as exc:
            logger.warning("Firebase is not configured; skipping push reminder: %s", exc)
            return False

        payload = {
            "type": "vocabulary_review_reminder",
            "route": "/vocabulary/review",
            "due_count": str(due_count),
            **(data or {}),
        }
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={key: str(value) for key, value in payload.items()},
            tokens=clean_tokens,
        )

        try:
            response = await run_in_threadpool(messaging.send_each_for_multicast, message)
            success_count = int(getattr(response, "success_count", 0) or 0)
            failure_count = int(getattr(response, "failure_count", 0) or 0)
            if failure_count:
                logger.warning(
                    "Review reminder push had %s failed FCM delivery attempt(s)",
                    failure_count,
                )
            return success_count > 0
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception("Failed to send review reminder push: %s", exc)
            return False

    async def send_starter_reward(
        self,
        *,
        tokens: list[str],
        gems: int,
        reward_key: str,
        title: str,
        body: str,
    ) -> bool:
        """Send the durable starter reward notification to known devices."""
        clean_tokens = [token for token in tokens if token]
        if not clean_tokens:
            return False

        try:
            _init_firebase_app()
        except Exception as exc:
            logger.warning(
                "Firebase is not configured; skipping starter reward push: %s",
                exc,
            )
            return False

        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={
                "type": "starter_reward",
                "route": "/",
                "reward_key": reward_key,
                "gems": str(gems),
            },
            tokens=clean_tokens,
        )
        try:
            response = await run_in_threadpool(
                messaging.send_each_for_multicast,
                message,
            )
            return int(getattr(response, "success_count", 0) or 0) > 0
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception("Failed to send starter reward push: %s", exc)
            return False

    async def send_streak_at_risk(
        self,
        *,
        tokens: list[str],
        current_streak: int,
        title: str,
        body: str,
    ) -> bool:
        """Warn users their streak will reset if they don't study today."""
        clean_tokens = [t for t in tokens if t]
        if not clean_tokens:
            return False

        try:
            _init_firebase_app()
        except Exception as exc:
            logger.warning("Firebase not configured; skipping streak alert: %s", exc)
            return False

        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={
                "type": "streak_reminder",
                "route": "/",
                "current_streak": str(current_streak),
            },
            tokens=clean_tokens,
        )
        try:
            response = await run_in_threadpool(messaging.send_each_for_multicast, message)
            return int(getattr(response, "success_count", 0) or 0) > 0
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception("Failed to send streak alert push: %s", exc)
            return False
