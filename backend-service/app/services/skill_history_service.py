"""Retention and trend maintenance for skill measurement data.

Two jobs that keep the learner model bounded and honest:

* ``prune_exercise_attempts`` — ExerciseAttempt keeps one row per answer and
  nothing reads it back; `skill_daily_stats` carries the same information for
  the long term, so the detail is only worth keeping while it can still be used
  to debug a recent score.
* ``snapshot_skill_scores`` — UserSkillScore.trend reads score_7d_ago /
  score_30d_ago, but nothing in the running system ever wrote them, so every
  skill reported "stable" no matter how a learner was doing.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.proficiency import ExerciseAttempt, UserSkillScore

logger = logging.getLogger(__name__)

# How long an individual answer stays queryable. Long enough to investigate a
# score a learner is asking about, short enough that the table stops growing.
ATTEMPT_RETENTION_DAYS = 90

# Deleted per statement, so one night's cleanup cannot hold a long lock on the
# 2-vCPU production box. Mirrors cleanup_observation_events' batching.
PRUNE_BATCH_SIZE = 5000


@dataclass(frozen=True, slots=True)
class PruneResult:
    deleted: int
    cutoff: datetime


async def prune_exercise_attempts(
    session: AsyncSession,
    *,
    now: datetime | None = None,
    retention_days: int = ATTEMPT_RETENTION_DAYS,
    batch_size: int = PRUNE_BATCH_SIZE,
    dry_run: bool = False,
) -> PruneResult:
    """Delete answer-level rows older than the retention window."""
    now = now or datetime.now(UTC)
    cutoff = now - timedelta(days=retention_days)

    if dry_run:
        stale = await session.scalar(
            select(ExerciseAttempt.id)
            .where(ExerciseAttempt.attempted_at < cutoff)
            .limit(batch_size)
            .with_only_columns(ExerciseAttempt.id)
        )
        count = 0 if stale is None else 1
        return PruneResult(deleted=count, cutoff=cutoff)

    deleted = 0
    while True:
        ids = (
            await session.scalars(
                select(ExerciseAttempt.id)
                .where(ExerciseAttempt.attempted_at < cutoff)
                .limit(batch_size)
            )
        ).all()
        if not ids:
            break
        result = await session.execute(
            delete(ExerciseAttempt)
            .where(ExerciseAttempt.id.in_(ids))
            .execution_options(synchronize_session=False)
        )
        await session.commit()
        deleted += int(result.rowcount or 0)
        if len(ids) < batch_size:
            break

    return PruneResult(deleted=deleted, cutoff=cutoff)


async def snapshot_skill_scores(
    session: AsyncSession,
    *,
    now: datetime | None = None,
) -> dict[str, int]:
    """Roll today's scores into the 7-day and 30-day comparison columns.

    Run weekly. `score_30d_ago` takes what `score_7d_ago` held before this
    call, so after four runs it is roughly a month behind — close enough for a
    direction arrow, and it costs two columns rather than a history table.
    """
    now = now or datetime.now(UTC)
    month_boundary = now.day <= 7  # once a month, on the first weekly run

    moved_30d = 0
    if month_boundary:
        result = await session.execute(
            update(UserSkillScore)
            .where(UserSkillScore.score_7d_ago.isnot(None))
            .values(score_30d_ago=UserSkillScore.score_7d_ago)
            .execution_options(synchronize_session=False)
        )
        moved_30d = int(result.rowcount or 0)

    result = await session.execute(
        update(UserSkillScore)
        .values(score_7d_ago=UserSkillScore.score)
        .execution_options(synchronize_session=False)
    )
    await session.commit()

    return {"snapshots_7d": int(result.rowcount or 0), "snapshots_30d": moved_30d}
