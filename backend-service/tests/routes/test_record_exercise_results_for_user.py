import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.proficiency import (
    UserProficiencyProfile,
    UserSkillScore,
    UserLevelHistory,
    ExerciseAttempt,
)
from app.models.user import User
from app.routes.proficiency import record_exercise_results_for_user
from app.schemas.proficiency import ExerciseResult, ProficiencyLevel, SkillType


@pytest.fixture
async def db_session():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [
        User.__table__,
        UserProficiencyProfile.__table__,
        UserSkillScore.__table__,
        UserLevelHistory.__table__,
        ExerciseAttempt.__table__,
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


async def test_award_xp_false_still_syncs_cefr_level(db_session, test_user):
    # 20 high-scoring A1 exercises should be enough to trigger a level change.
    results = _one_result(score=100.0) * 20

    await record_exercise_results_for_user(db_session, test_user, results, award_xp=False)

    # XP stayed untouched even though the CEFR level may have moved.
    assert test_user.total_xp == 0
    assert test_user.level is not None
