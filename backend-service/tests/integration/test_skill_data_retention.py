"""Per-user measurement data stays bounded.

exercise_attempts grows by one row per answer, is never read back, and had no
retention policy — after the pipeline work it also grows on every quiz
question, chat turn and mispronounced word. These tests pin the two things
that keep that from becoming unbounded: a per-day rollup that does not grow
with intensity, and a prune that removes the detail once it is stale.
"""

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.proficiency import ExerciseAttempt, SkillDailyStat
from app.models.proficiency import SkillType as ModelSkillType
from app.routes.proficiency import record_exercise_results_for_user
from app.schemas.proficiency import ExerciseResult, ProficiencyLevel, SkillType
from app.services.skill_history_service import (
    prune_exercise_attempts,
    snapshot_skill_scores,
)


def _result(skill: SkillType, correct: bool, score: float) -> ExerciseResult:
    return ExerciseResult(
        exercise_type="news_quiz",
        skill=skill,
        difficulty_level=ProficiencyLevel.B1,
        is_correct=correct,
        score=score,
    )


async def _rollups(db: AsyncSession, user_id) -> list[SkillDailyStat]:
    return list(
        (
            await db.scalars(
                select(SkillDailyStat).where(SkillDailyStat.user_id == user_id)
            )
        ).all()
    )


@pytest.mark.asyncio
async def test_a_days_practice_costs_one_row_per_skill(
    db_session: AsyncSession, test_user
):
    """Twenty answers across two skills must not cost twenty rollup rows."""
    for _ in range(10):
        await record_exercise_results_for_user(
            db_session,
            test_user,
            [
                _result(SkillType.READING, True, 100.0),
                _result(SkillType.SPEAKING, False, 40.0),
            ],
            award_xp=False,
        )

    rows = await _rollups(db_session, test_user.id)
    assert len(rows) == 2, [(r.skill, r.attempts) for r in rows]

    by_skill = {row.skill: row for row in rows}
    reading = by_skill[ModelSkillType.READING]
    assert reading.attempts == 10
    assert reading.correct == 10
    assert reading.average_score == pytest.approx(100.0)
    assert reading.accuracy == pytest.approx(1.0)

    speaking = by_skill[ModelSkillType.SPEAKING]
    assert speaking.attempts == 10
    assert speaking.correct == 0
    assert speaking.average_score == pytest.approx(40.0)


@pytest.mark.asyncio
async def test_prune_removes_stale_detail_and_keeps_recent(
    db_session: AsyncSession, test_user
):
    now = datetime.now(UTC)
    for age_days in (200, 120, 91, 89, 1):
        db_session.add(
            ExerciseAttempt(
                user_id=test_user.id,
                exercise_type="news_quiz",
                skill=ModelSkillType.READING,
                difficulty_level="B1",
                is_correct=True,
                score=100.0,
                attempted_at=now - timedelta(days=age_days),
            )
        )
    await db_session.commit()

    result = await prune_exercise_attempts(db_session, now=now)
    assert result.deleted == 3  # 200, 120 and 91 days old

    remaining = (
        await db_session.scalars(
            select(ExerciseAttempt).where(ExerciseAttempt.user_id == test_user.id)
        )
    ).all()
    assert len(remaining) == 2
    assert all(row.attempted_at >= result.cutoff for row in remaining)


@pytest.mark.asyncio
async def test_rollup_outlives_the_pruned_detail(db_session: AsyncSession, test_user):
    """The point of the rollup: history survives the retention window."""
    await record_exercise_results_for_user(
        db_session,
        test_user,
        [_result(SkillType.READING, True, 90.0)],
        award_xp=False,
    )

    # Age the detail row past the window, then prune.
    attempt = await db_session.scalar(
        select(ExerciseAttempt).where(ExerciseAttempt.user_id == test_user.id)
    )
    attempt.attempted_at = datetime.now(UTC) - timedelta(days=365)
    await db_session.commit()

    await prune_exercise_attempts(db_session)

    assert (
        await db_session.scalar(
            select(ExerciseAttempt).where(ExerciseAttempt.user_id == test_user.id)
        )
    ) is None
    rows = await _rollups(db_session, test_user.id)
    assert len(rows) == 1
    assert rows[0].attempts == 1


@pytest.mark.asyncio
async def test_snapshot_populates_the_trend_columns(
    db_session: AsyncSession, test_user
):
    """UserSkillScore.trend read two columns nothing ever wrote."""
    await record_exercise_results_for_user(
        db_session,
        test_user,
        [_result(SkillType.READING, True, 100.0)],
        award_xp=False,
    )

    from app.models.proficiency import UserProficiencyProfile, UserSkillScore

    profile = await db_session.scalar(
        select(UserProficiencyProfile).where(
            UserProficiencyProfile.user_id == test_user.id
        )
    )
    score = await db_session.scalar(
        select(UserSkillScore).where(UserSkillScore.profile_id == profile.id)
    )
    assert score.score_7d_ago is None
    assert score.trend == "stable"  # the only answer it could ever give before

    await snapshot_skill_scores(db_session, now=datetime.now(UTC))
    await db_session.refresh(score)
    assert score.score_7d_ago == pytest.approx(score.score)

    # A later improvement now reads as improving rather than stable.
    score.score = (score.score_7d_ago or 0) + 20
    await db_session.commit()
    await db_session.refresh(score)
    assert score.trend == "improving"
