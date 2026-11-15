import pytest
from sqlalchemy import select
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


async def test_records_skills_without_awarding_any_xp(db_session, test_user):
    """This function never grants XP, and has no flag to make it.

    It used to, behind `award_xp=True`, which raised `User.total_xp` while
    writing no XPTransaction, no DailyActivity and no LeaderboardEntry — XP that
    no other table could account for. Every caller already passed False. XP
    belongs to the calling route or to `award_xp_transaction`.
    """
    await record_exercise_results_for_user(db_session, test_user, _one_result())

    assert test_user.total_xp == 0


async def test_reports_zero_xp_in_its_result(db_session, test_user):
    result = await record_exercise_results_for_user(
        db_session, test_user, _one_result()
    )

    assert result["xp_earned"] == 0
    assert result["exercises_recorded"] == 1


def test_no_award_xp_parameter_remains():
    """A caller that forgot the flag would have minted unaccounted XP."""
    import inspect

    params = inspect.signature(record_exercise_results_for_user).parameters
    assert "award_xp" not in params


async def _a2_worthy_batch():
    return [
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


async def test_activity_alone_never_promotes_cefr(db_session, test_user):
    """Every A2 gate cleared by practice still does not move the level.

    CEFR is earned by passing a level test. It used to be re-derived from the
    skill scores on every batch, so a strong week promoted the learner with no
    test at all.
    """
    db_session.add(
        UserProficiencyProfile(
            user_id=test_user.id, assessed_level="A1", total_lessons_completed=15
        )
    )
    await db_session.commit()

    result = await record_exercise_results_for_user(
        db_session, test_user, await _a2_worthy_batch()
    )

    assert result["level_changed"] is False
    assert result["current_level"] == "A1"
    assert test_user.level == "A1"
    history = (await db_session.execute(select(UserLevelHistory))).scalars().all()
    assert history == []


async def test_poor_practice_never_demotes_cefr(db_session, test_user):
    test_user.level = "B1"
    db_session.add(UserProficiencyProfile(user_id=test_user.id, assessed_level="B1"))
    await db_session.commit()

    bad = [
        ExerciseResult(
            exercise_type="lesson",
            skill=SkillType.VOCABULARY,
            difficulty_level=ProficiencyLevel.B1,
            is_correct=False,
            score=0.0,
            time_spent_seconds=30,
        )
        for _ in range(30)
    ]
    result = await record_exercise_results_for_user(db_session, test_user, bad)

    assert result["level_changed"] is False
    assert test_user.level == "B1"
    profile = (
        await db_session.execute(
            select(UserProficiencyProfile).where(
                UserProficiencyProfile.user_id == test_user.id
            )
        )
    ).scalar_one()
    assert profile.assessed_level == "B1"
    history = (await db_session.execute(select(UserLevelHistory))).scalars().all()
    assert history == []


async def test_user_level_is_settled_on_the_profile_not_the_scores(
    db_session, test_user
):
    """users.level drifting from the profile is repaired toward the profile."""
    test_user.level = "A1"
    db_session.add(UserProficiencyProfile(user_id=test_user.id, assessed_level="B2"))
    await db_session.commit()

    await record_exercise_results_for_user(db_session, test_user, _one_result())

    assert test_user.level == "B2"
    expected_rank = calculate_rank(
        numeric_level=test_user.numeric_level or 1, proficiency_level="B2"
    )
    assert test_user.rank_proficiency_score == expected_rank.proficiency_score
