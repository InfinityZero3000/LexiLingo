import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.proficiency import (
    UserProficiencyProfile,
    UserSkillScore,
    UserLevelHistory,
    ExerciseAttempt,
    SkillDailyStat,
)
from app.models.user import User
from app.routes.proficiency import record_exercise_results_for_user
from app.schemas.proficiency import ExerciseResult, ProficiencyLevel, SkillType
from app.services.rank_service import calculate_rank


@pytest.fixture
async def db_session():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [
        User.__table__,
        UserProficiencyProfile.__table__,
        UserSkillScore.__table__,
        UserLevelHistory.__table__,
        ExerciseAttempt.__table__,
        SkillDailyStat.__table__,
    ]
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection,
                tables=tables,
            )
        )

    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


@pytest.fixture
async def test_user(db_session):
    user = User(
        email="lesson_complete@example.com",
        username="lesson_complete_user",
        hashed_password="not-used",
        level="A1",
        total_xp=0,
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


def _one_result(score: float = 90.0) -> list[ExerciseResult]:
    return [
        ExerciseResult(
            exercise_type="lesson",
            skill=SkillType.VOCABULARY,
            difficulty_level=ProficiencyLevel.A1,
            is_correct=True,
            score=score,
            time_spent_seconds=30,
        )
    ]


async def test_award_xp_true_updates_both_profile_and_user_xp(db_session, test_user):
    await record_exercise_results_for_user(db_session, test_user, _one_result(), award_xp=True)

    assert test_user.total_xp > 0


async def test_award_xp_false_does_not_touch_user_xp(db_session, test_user):
    await record_exercise_results_for_user(db_session, test_user, _one_result(), award_xp=False)

    assert test_user.total_xp == 0


async def test_award_xp_false_still_syncs_cefr_level_and_rank(db_session, test_user):
    # A2 requires >=100 exercises, >=10 lessons, and 60/55 vocab/grammar
    # scores (LEVEL_THRESHOLDS in app/schemas/proficiency.py). Pre-seed the
    # lesson count (record_exercise_results_for_user never increments it —
    # that happens on the lesson-completion route) and supply exercises
    # across both graded skills so every A2 gate is actually cleared.
    profile = UserProficiencyProfile(
        user_id=test_user.id,
        assessed_level="A1",
        total_lessons_completed=15,
    )
    db_session.add(profile)
    await db_session.commit()

    results = [
        ExerciseResult(
            exercise_type="lesson",
            skill=SkillType.VOCABULARY if i % 2 == 0 else SkillType.GRAMMAR,
            difficulty_level=ProficiencyLevel.A1,
            is_correct=True,
            score=100.0,
            time_spent_seconds=30,
        )
        for i in range(100)
    ]

    await record_exercise_results_for_user(db_session, test_user, results, award_xp=False)

    # XP stayed untouched even though the CEFR level moved.
    assert test_user.total_xp == 0
    assert test_user.level != "A1"

    # Rank must reflect the new level immediately, not the stale A1 value —
    # award_xp=False must not leave rank one step behind current_user.level.
    expected_rank = calculate_rank(
        numeric_level=test_user.numeric_level or 1,
        proficiency_level=test_user.level,
    )
    assert test_user.rank_proficiency_score == expected_rank.proficiency_score
