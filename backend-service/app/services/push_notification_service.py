"""Firebase Cloud Messaging push notification service."""

from __future__ import annotations

import logging

from fastapi.concurrency import run_in_threadpool
from firebase_admin import messaging

from app.core.firebase_auth import _init_firebase_app
from app.services.push_copy import word_of_day_copy

logger = logging.getLogger(__name__)

# Android tints the small icon itself; it must be the monochrome drawable the
# app ships (res/drawable/ic_stat_lexilingo.xml), not the colour launcher icon,
# which renders as a grey square. Colour is AppColors.primary.
ANDROID_ICON = "ic_stat_lexilingo"
BRAND_COLOR = "#137FEC"

# Channels the app creates at start-up (NotificationService.init), so the
# learner can mute one kind without losing the others.
# FCM refuses a multicast of more than 500 tokens outright.
_MULTICAST_LIMIT = 500

_ANDROID_CHANNEL = {
    "vocabulary_review_reminder": "daily_reminder_channel",
    "word_of_day": "daily_reminder_channel",
    "streak_reminder": "checkin_reminder_channel",
}


class PushNotificationService:
    """Small FCM wrapper that fails closed when Firebase is not configured."""

    async def _send(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> bool:
        clean_tokens = [token for token in tokens if token]
        kind = data["type"]
        if not clean_tokens:
            logger.info("No FCM tokens available for %s push", kind)
            return False

        try:
            _init_firebase_app()
        except Exception as exc:
            logger.warning("Firebase is not configured; skipping %s push: %s", kind, exc)
            return False

        success_count = failure_count = 0
        for start in range(0, len(clean_tokens), _MULTICAST_LIMIT):
            batch = clean_tokens[start : start + _MULTICAST_LIMIT]
            sent, failed = await self._send_batch(batch, title=title, body=body, data=data)
            success_count += sent
            failure_count += failed

        if failure_count:
            logger.warning("%s push had %s failed FCM delivery attempt(s)", kind, failure_count)
        return success_count > 0

    async def _send_batch(
        self,
        tokens: list[str],
        *,
        title: str,
        body: str,
        data: dict[str, str],
    ) -> tuple[int, int]:
        kind = data["type"]
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={key: str(value) for key, value in data.items()},
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    icon=ANDROID_ICON,
                    color=BRAND_COLOR,
                    channel_id=_ANDROID_CHANNEL.get(kind),
                    # A newer push of the same kind replaces the older one.
                    tag=kind,
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", thread_id=kind),
                ),
            ),
            tokens=tokens,
        )

        try:
            response = await run_in_threadpool(messaging.send_each_for_multicast, message)
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception("Failed to send %s push: %s", kind, exc)
            return 0, len(tokens)

        return (
            int(getattr(response, "success_count", 0) or 0),
            int(getattr(response, "failure_count", 0) or 0),
        )

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
        return await self._send(
            tokens=tokens,
            title=title,
            body=body,
            data={
                "type": "vocabulary_review_reminder",
                "route": "/vocabulary/review",
                "due_count": str(due_count),
                **(data or {}),
            },
        )

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
        return await self._send(
            tokens=tokens,
            title=title,
            body=body,
            data={
                "type": "starter_reward",
                "route": "/",
                "reward_key": reward_key,
                "gems": str(gems),
            },
        )

    async def send_streak_at_risk(
        self,
        *,
        tokens: list[str],
        current_streak: int,
        title: str,
        body: str,
    ) -> bool:
        """Warn users their streak will reset if they don't study today."""
        return await self._send(
            tokens=tokens,
            title=title,
            body=body,
            data={
                "type": "streak_reminder",
                "route": "/",
                "current_streak": str(current_streak),
            },
        )

    async def send_word_of_day(
        self,
        *,
        tokens: list[str],
        word: str,
        definition: str,
        lang: str = "en",
        pronunciation: str | None = None,
        translation: dict | None = None,
    ) -> bool:
        """Send the daily Word of the Day push notification."""
        title, body = word_of_day_copy(
            lang,
            word=word,
            pronunciation=pronunciation,
            translation=translation,
            definition=definition,
        )
        return await self._send(
            tokens=tokens,
            title=title,
            body=body,
            data={"type": "word_of_day", "route": "/vocabulary/word-of-day", "word": word},
        )

    async def send_nurture(
        self,
        *,
        tokens: list[str],
        kind: str,
        title: str,
        body: str,
        route: str,
    ) -> bool:
        """Send an activation nudge; `kind` becomes the data `type`."""
        return await self._send(
            tokens=tokens,
            title=title,
            body=body,
            data={"type": kind, "route": route},
        )
