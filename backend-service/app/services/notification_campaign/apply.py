"""Apply service — coordinate FCM/in-app dispatch for a campaign job."""

from __future__ import annotations

import logging
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification_campaign import NotificationCampaignJob
from app.services.notification_campaign.segmenter import segment_users
from app.services.notification_campaign.sender import (
    send_campaign_in_app,
    send_campaign_push,
)
from app.services.notification_campaign_jobs import NotificationCampaignJobService

logger = logging.getLogger(__name__)


class NotificationCampaignApplyService:
    @staticmethod
    async def apply(
        db: AsyncSession,
        job: NotificationCampaignJob,
    ) -> dict:
        cfg = job.config
        content_cfg = cfg.get("content", {})
        audience_cfg = cfg.get("audience", {})

        title = content_cfg.get("title", "")
        body = content_cfg.get("body", "")
        notification_type = content_cfg.get("notification_type", "campaign")
        deep_link = content_cfg.get("deep_link")

        # If AI rewrite was used, prefer the AI-generated copy stored in artifact
        if job.artifact and job.artifact.get("ai_copy"):
            ai_copy = job.artifact["ai_copy"]
            title = ai_copy.get("title", title)
            body = ai_copy.get("body", body)

        # Re-segment to get fresh user list (may have changed since preview)
        segment = await segment_users(
            db,
            audience_type=audience_cfg.get("type", "all"),
            filters=audience_cfg.get("filters", {}),
        )

        if job.job_type in ("targeted_push", "scheduled_push"):
            result = await send_campaign_push(
                fcm_token_map=segment.fcm_token_map,
                title=title,
                body=body,
                notification_type=notification_type,
                deep_link=deep_link,
            )
        elif job.job_type == "in_app_broadcast":
            result = await send_campaign_in_app(
                db,
                user_ids=segment.user_ids,
                title=title,
                body=body,
                notification_type=notification_type,
                deep_link=deep_link,
            )
        else:
            raise ValueError(f"Unknown job_type: {job.job_type!r}")

        await NotificationCampaignJobService.set_delivery_stats(
            db,
            job,
            sent=result.sent,
            failed=result.failed,
            skipped=result.skipped,
        )

        logger.info(
            "Campaign job %s applied: sent=%d failed=%d skipped=%d",
            job.id,
            result.sent,
            result.failed,
            result.skipped,
        )

        return {
            "sent": result.sent,
            "failed": result.failed,
            "skipped": result.skipped,
            "total": result.sent + result.failed + result.skipped,
        }
