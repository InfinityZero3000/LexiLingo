"""Celery task: daily streak-at-risk notifications at 20:00 UTC."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from sqlalchemy import select

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db
from app.models.progress import Streak
from app.models.user import User, UserDevice
from app.services.push_copy import nudge_copy
from app.services.push_notification_service import PushNotificationService

logger = logging.getLogger(__name__)


@celery_app.task(name="app.tasks.streak_reminders.send_streak_alerts")
def send_streak_alerts() -> dict:
    return asyncio.run(_with_db_cleanup(_send_streak_alerts()))


async def _with_db_cleanup(coro):
    try:
        return await coro
    finally:
        await close_db()


async def _send_streak_alerts() -> dict:
    today = datetime.now(timezone.utc).date()
    sent = 0
    skipped = 0

    async with AsyncSessionLocal() as db:
        # Users with an active streak but no activity today
        active_streaks = (
            await db.execute(
                select(Streak, User.native_language)
                .join(User, User.id == Streak.user_id)
                .where(
                    Streak.current_streak > 0,
                    Streak.last_activity_date < today,
                )
            )
        ).all()

        push = PushNotificationService()

        for streak, native_language in active_streaks:
            # Get FCM tokens for this user
            devices = (
                await db.execute(
                    select(UserDevice).where(
                        UserDevice.user_id == streak.user_id,
                        UserDevice.fcm_token.isnot(None),
                    )
                )
            ).scalars().all()

            tokens = [d.fcm_token for d in devices if d.fcm_token]
            if not tokens:
                skipped += 1
                continue

            days = streak.current_streak
            title, body = nudge_copy("streak_at_risk", native_language, days=days)
            ok = await push.send_streak_at_risk(
                tokens=tokens,
                current_streak=days,
                title=title,
                body=body,
            )
            if ok:
                sent += 1
            else:
                skipped += 1

    result = {
        "sent": sent,
        "skipped": skipped,
        "total": sent + skipped,
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    logger.info("Streak alert scan: %s", result)
    return result
