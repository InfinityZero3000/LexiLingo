"""Celery orchestration for Notification Campaign Agent jobs."""

from __future__ import annotations

import asyncio
import logging
import os
import uuid
from datetime import UTC, datetime

import httpx

from app.core.celery_app import celery_app
from app.core.config import settings
from app.core.database import AsyncSessionLocal

logger = logging.getLogger(__name__)


class JobCancelled(Exception):
    pass


@celery_app.task(name="app.tasks.notification_campaign.run_notification_campaign_job")
def run_notification_campaign_job(job_id: str) -> dict:
    return asyncio.run(_run_notification_campaign_job(uuid.UUID(job_id)))


async def _run_notification_campaign_job(job_id: uuid.UUID) -> dict:
    from app.services.notification_campaign.segmenter import segment_users
    from app.services.notification_campaign_jobs import NotificationCampaignJobService

    async with AsyncSessionLocal() as db:
        job = await NotificationCampaignJobService.get(db, job_id, lock=True)
        if job is None:
            raise LookupError(f"Notification-campaign job {job_id} does not exist")
        if job.status == "cancelled":
            return {"job_id": str(job_id), "status": "cancelled"}
        if job.status != "queued":
            return {"job_id": str(job_id), "status": job.status}

        cfg = job.config
        use_ai_copy: bool = bool(cfg.get("content", {}).get("use_ai_copy", False))

        try:
            # Stage 1: segmenting
            await NotificationCampaignJobService.transition(
                db, job, "segmenting", percent=20, stage="segmenting"
            )
            await db.commit()

            audience_cfg = cfg.get("audience", {})
            filters = dict(audience_cfg.get("filters", {}))
            # in_app_broadcast doesn't use FCM — don't filter by token availability
            if job.job_type == "in_app_broadcast":
                filters["has_fcm_token"] = False
            segment = await segment_users(
                db,
                audience_type=audience_cfg.get("type", "all"),
                filters=filters,
            )

            # Stage 2: generating (AI copy or passthrough)
            job = await NotificationCampaignJobService.get(db, job_id, lock=True)
            if job is None or job.status == "cancelled":
                raise JobCancelled

            await NotificationCampaignJobService.transition(
                db, job, "generating", percent=50, stage="generating"
            )
            await db.commit()

            ai_copy: dict | None = None
            if use_ai_copy:
                ai_copy = await _fetch_ai_copy(cfg, segment)

            # Stage 3: validating
            job = await NotificationCampaignJobService.get(db, job_id, lock=True)
            if job is None or job.status == "cancelled":
                raise JobCancelled

            await NotificationCampaignJobService.transition(
                db, job, "validating", percent=80, stage="validating"
            )
            await db.commit()

            warnings: list[str] = []
            blocking_errors: list[str] = []

            if segment.audience_size == 0:
                blocking_errors.append(
                    "No users match the selected audience filters. "
                    "Adjust the segment criteria before applying."
                )

            content_cfg = cfg.get("content", {})
            fcm_eligible = len(segment.fcm_token_map)

            if job.job_type in ("targeted_push", "scheduled_push") and fcm_eligible == 0:
                blocking_errors.append(
                    "No users in the segment have FCM tokens registered. "
                    "Use 'In-App Broadcast' instead, or wait for users to register devices."
                )

            artifact = {
                "audience_size": segment.audience_size,
                "fcm_eligible": fcm_eligible,
                "sample_users": segment.sample_users,
                "filter_summary": segment.filter_summary,
                "content_preview": {
                    "title": content_cfg.get("title", ""),
                    "body": content_cfg.get("body", ""),
                },
            }

            if ai_copy:
                artifact["ai_copy"] = ai_copy
                artifact["content_preview"] = {
                    "title": ai_copy.get("title", content_cfg.get("title", "")),
                    "body": ai_copy.get("body", content_cfg.get("body", "")),
                }

            if job.job_type == "scheduled_push":
                send_at = cfg.get("send_at")
                if send_at:
                    artifact["scheduled_for"] = send_at

            job = await NotificationCampaignJobService.get(db, job_id, lock=True)
            if job is None or job.status == "cancelled":
                raise JobCancelled

            await NotificationCampaignJobService.set_preview(
                db,
                job,
                artifact=artifact,
                warnings=warnings,
                blocking_errors=blocking_errors,
            )
            await db.commit()

            logger.info("Notification-campaign job %s reached preview_ready", job_id)
            return {"job_id": str(job_id), "status": "preview_ready"}

        except JobCancelled:
            await db.rollback()
            logger.info("Notification-campaign job %s was cancelled", job_id)
            # Safety guard: ensure `cancelled` is persisted even if the cancel route
            # committed between two of our commits (leaving an intermediate status).
            async with AsyncSessionLocal() as cancel_db:
                cancel_job = await NotificationCampaignJobService.get(cancel_db, job_id, lock=True)
                if cancel_job and cancel_job.status not in ("cancelled", "completed", "failed"):
                    cancel_job.status = "cancelled"
                    cancel_job.updated_at = datetime.now(UTC)
                    await cancel_db.commit()
            return {"job_id": str(job_id), "status": "cancelled"}
        except Exception as exc:
            await db.rollback()
            logger.exception("Notification-campaign job %s failed: %s", job_id, exc)
            async with AsyncSessionLocal() as err_db:
                err_job = await NotificationCampaignJobService.get(err_db, job_id, lock=True)
                if err_job:
                    await NotificationCampaignJobService.set_failed(err_db, err_job, str(exc))
                    await err_db.commit()
            return {"job_id": str(job_id), "status": "failed", "error": str(exc)}


async def _fetch_ai_copy(cfg: dict, segment) -> dict | None:
    """Call ai-service to generate personalized notification copy."""
    ai_service_url = os.getenv("AI_SERVICE_URL", "http://ai-service:8001")
    timeout = settings.NOTIFICATION_CAMPAIGN_AI_TIMEOUT_SECONDS
    ai_admin_key = os.getenv("AI_ADMIN_API_KEY", "").strip()

    content = cfg.get("content", {})
    audience = cfg.get("audience", {})

    payload = {
        "title": content.get("title", ""),
        "body": content.get("body", ""),
        "notification_type": content.get("notification_type", "campaign"),
        "audience_profile": {
            "size": segment.audience_size,
            "cefr_levels": audience.get("filters", {}).get("cefr_levels"),
            "leagues": audience.get("filters", {}).get("leagues"),
            "inactive_days": audience.get("filters", {}).get("inactive_days"),
        },
    }

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(
                f"{ai_service_url}/api/notification-agent/generate-content",
                headers={"X-Admin-Api-Key": ai_admin_key},
                json=payload,
            )
            if resp.status_code == 200:
                data = resp.json()
                return data.get("best_variant")
    except Exception as exc:
        logger.warning("AI copy generation failed (skipping): %s", exc)
    return None
