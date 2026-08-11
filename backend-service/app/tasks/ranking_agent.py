"""Celery orchestration for Ranking/Gamification Agent jobs."""

from __future__ import annotations

import asyncio
import logging
import uuid

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal, close_db

logger = logging.getLogger(__name__)


class JobCancelled(Exception):
    pass


@celery_app.task(name="app.tasks.ranking_agent.run_ranking_agent_job")
def run_ranking_agent_job(job_id: str) -> dict:
    return asyncio.run(_with_db_cleanup(_run_ranking_agent_job(uuid.UUID(job_id))))


@celery_app.task(name="app.tasks.ranking_agent.auto_league_reset")
def auto_league_reset() -> dict:
    return asyncio.run(_with_db_cleanup(_auto_league_reset()))


async def _with_db_cleanup(coro):
    try:
        return await coro
    finally:
        await close_db()


async def _run_ranking_agent_job(job_id: uuid.UUID) -> dict:
    from app.services.ranking_agent_jobs import RankingAgentJobService

    async with AsyncSessionLocal() as db:
        job = await RankingAgentJobService.get(db, job_id, lock=True)
        if job is None:
            raise LookupError(f"Ranking-agent job {job_id} does not exist")
        if job.status == "cancelled":
            return {"job_id": str(job_id), "status": "cancelled"}
        if job.status != "queued":
            return {"job_id": str(job_id), "status": job.status}

        use_ai_insights: bool = bool(job.config.get("use_ai_insights", False))

        try:
            await RankingAgentJobService.transition(
                db, job, "calculating", percent=20
            )
            await db.commit()

            artifact = await _calculate_artifact(db, job.job_type, job.config)

            job = await RankingAgentJobService.get(db, job_id, lock=True)
            if job is None or job.status == "cancelled":
                raise JobCancelled

            await RankingAgentJobService.transition(
                db, job, "validating", percent=80
            )
            await db.commit()

            if use_ai_insights:
                ai_insight = await _fetch_ai_insights(job.job_type, artifact)
                if ai_insight:
                    artifact["ai_insights"] = ai_insight

            blocking_errors = artifact.pop("blocking_errors", [])
            warnings = artifact.pop("warnings", [])

            job = await RankingAgentJobService.get(db, job_id, lock=True)
            await RankingAgentJobService.set_preview(
                db,
                job,
                artifact=artifact,
                warnings=warnings,
                blocking_errors=blocking_errors,
            )
            await db.commit()

            logger.info("Ranking-agent job %s reached preview_ready", job_id)
            return {"job_id": str(job_id), "status": "preview_ready"}

        except JobCancelled:
            await db.rollback()
            return {"job_id": str(job_id), "status": "cancelled"}
        except Exception as exc:
            await db.rollback()
            job = await RankingAgentJobService.get(db, job_id)
            if job is not None and job.status not in {"cancelled", "completed"}:
                await RankingAgentJobService.fail(db, job, str(exc)[:2000])
                await db.commit()
            logger.exception("Ranking-agent job %s failed", job_id)
            raise


async def _fetch_ai_insights(job_type: str, artifact: dict) -> str | None:
    """Call ai-service for Groq insights; never raises — returns None on any failure."""
    try:
        from app.services.ranking_agent_ai_client import RankingAgentAIClient
        return await RankingAgentAIClient().get_insights(job_type, artifact)
    except Exception:
        logger.exception("Could not fetch AI insights for ranking-agent job (non-fatal)")
        return None


async def _calculate_artifact(db, job_type: str, config: dict) -> dict:
    if job_type == "league_reset":
        from app.core.config import settings
        from app.services.ranking_agent.league_reset import LeagueResetEngine
        engine = LeagueResetEngine(
            promotion_threshold=settings.LEAGUE_RESET_PROMOTION_THRESHOLD,
            demotion_threshold=settings.LEAGUE_RESET_DEMOTION_THRESHOLD,
        )
        return await engine.calculate(db, config)

    if job_type == "xp_event":
        from app.services.ranking_agent.xp_event import XPEventEngine
        return await XPEventEngine().calculate(db, config)

    if job_type == "achievement_batch":
        from app.services.ranking_agent.achievement_batch import AchievementBatchEngine
        return await AchievementBatchEngine().calculate(db, config)

    raise ValueError(f"Unknown job_type: {job_type}")


async def _auto_league_reset() -> dict:
    """Create and enqueue a league_reset job automatically (called by Celery Beat)."""
    from app.services.ranking_agent_jobs import RankingAgentJobService

    async with AsyncSessionLocal() as db:
        job = await RankingAgentJobService.create(
            db,
            requested_by_id=None,
            job_type="league_reset",
            config={"job_type": "league_reset"},
        )
        await db.commit()
        job_id = job.id
        try:
            result = run_ranking_agent_job.delay(str(job_id))
            job = await RankingAgentJobService.get(db, job_id)
            job.celery_task_id = result.id
            await db.commit()
        except Exception:
            logger.exception("Could not enqueue auto league-reset job %s", job_id)
            raise
        return {"job_id": str(job_id), "status": "queued"}
