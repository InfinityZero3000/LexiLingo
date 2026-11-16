"""Working vs certified CEFR level: tests certify, the learner picks, rank reads the certified one."""

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.proficiency import (
    LevelAssessmentTest,
    UserLevelHistory,
    UserProficiencyProfile,
)
from app.models.learner_state import LearnerStateProfile
from app.models.progress import LessonAttempt, LessonCompletion, UserProgress
from app.models.user import User
from app.routes.proficiency import (
    PLACEMENT_QUESTIONS,
    WorkingLevelUpdate,
    set_working_level,
    submit_placement_test,
)
from app.routes.users import update_current_user_profile
from app.schemas.user import UserUpdate


@pytest.fixture
async def db_session():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [
        User.__table__,
        UserProficiencyProfile.__table__,
        UserLevelHistory.__table__,
        LevelAssessmentTest.__table__,
        LearnerStateProfile.__table__,
        LessonCompletion.__table__,
        LessonAttempt.__table__,
        UserProgress.__table__,
    ]
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda c: Base.metadata.create_all(c, tables=tables)
        )
    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


@pytest.fixture
async def user(db_session):
    row = User(
        email="cefr@example.com",
        username="cefr_user",
        hashed_password="not-used",
        level="A1",
        is_onboarding_completed=False,
    )
    db_session.add(row)
    await db_session.commit()
    await db_session.refresh(row)
    return row


def _submission(correct: bool):
    from app.routes.proficiency import PlacementSubmission

    return PlacementSubmission(
        answers=[
            {
                "question_id": q["id"],
                "selected_option": q["correct"] if correct else (q["correct"] + 1) % 4,
            }
            for q in PLACEMENT_QUESTIONS
        ]
    )


async def _history(db_session):
    return (await db_session.execute(select(UserLevelHistory))).scalars().all()


async def _profile(db_session, user):
    return (
        await db_session.execute(
            select(UserProficiencyProfile).where(
                UserProficiencyProfile.user_id == user.id
            )
        )
    ).scalar_one()


async def test_first_placement_sets_the_level_and_is_recorded(db_session, user):
    result = await submit_placement_test(_submission(True), db_session, user)

    assert result["assessed_level"] in {"C1", "C2"}
    assert user.level == result["assessed_level"]
    rows = await _history(db_session)
    assert [(r.previous_level, r.new_level, r.change_type) for r in rows] == [
        ("A1", result["assessed_level"], "initial")
    ]


async def test_first_placement_may_land_below_a_self_reported_level(db_session, user):
    user.level = "B2"
    db_session.add(UserProficiencyProfile(user_id=user.id, assessed_level="B2"))
    await db_session.commit()

    result = await submit_placement_test(_submission(False), db_session, user)

    assert result["assessed_level"] == "A1"
    assert user.level == "A1"


async def test_a_placement_retake_can_only_raise(db_session, user):
    first = await submit_placement_test(_submission(True), db_session, user)
    held = first["certified_level"]

    retake = await submit_placement_test(_submission(False), db_session, user)

    assert retake["test_level"] == "A1"
    assert retake["level_changed"] is False
    assert user.certified_level == held
    assert user.level == held


async def test_a_placement_retake_certifies_higher(db_session, user):
    await submit_placement_test(_submission(False), db_session, user)

    retake = await submit_placement_test(_submission(True), db_session, user)

    assert retake["level_changed"] is True
    assert user.certified_level == retake["test_level"]
    rows = await _history(db_session)
    assert {r.change_type for r in rows} <= {"initial", "promotion"}


async def test_first_placement_certifies_what_it_scored(db_session, user):
    result = await submit_placement_test(_submission(True), db_session, user)

    assert user.certified_level == result["assessed_level"]
    assert result["certified_level"] == result["assessed_level"]


async def test_learner_may_pick_a_working_level_both_ways_without_certifying(
    db_session, user
):
    await submit_placement_test(_submission(False), db_session, user)
    rank_before = user.rank_proficiency_score

    await update_current_user_profile(UserUpdate(level="c1"), user, db_session)
    assert user.level == "C1"
    assert (await _profile(db_session, user)).assessed_level == "C1"
    assert user.certified_level == "A1"
    assert user.rank_proficiency_score == rank_before

    await set_working_level(WorkingLevelUpdate(level="A2"), db_session, user)
    assert user.level == "A2"
    assert user.certified_level == "A1"

    rows = sorted(await _history(db_session), key=lambda r: r.triggered_at)
    assert [r.change_type for r in rows] == ["self_set", "self_set"]
    assert "demotion" not in {r.change_type for r in rows}


async def test_a_working_level_above_the_certified_one_is_unverified(db_session, user):
    from app.services.cefr_level_service import level_verified

    await submit_placement_test(_submission(False), db_session, user)
    assert level_verified(user)

    await set_working_level(WorkingLevelUpdate(level="B2"), db_session, user)
    assert not level_verified(user)

    await set_working_level(WorkingLevelUpdate(level="A1"), db_session, user)
    assert level_verified(user)


async def test_every_level_change_advances_the_learner_state_epoch(db_session, user):
    async def epoch():
        row = (
            await db_session.execute(
                select(LearnerStateProfile).where(LearnerStateProfile.user_id == user.id)
            )
        ).scalar_one_or_none()
        return row.state_epoch if row else 0

    await submit_placement_test(_submission(False), db_session, user)
    first = await epoch()
    await set_working_level(WorkingLevelUpdate(level="B1"), db_session, user)
    second = await epoch()
    await set_working_level(WorkingLevelUpdate(level="B1"), db_session, user)

    assert first >= 1
    assert second == first + 1
    assert await epoch() == second  # no change, no bump


async def test_a_change_drops_the_learner_card_and_the_insights_cache(
    db_session, user
):
    from unittest.mock import AsyncMock, patch

    redis = AsyncMock()
    with patch(
        "app.services.cefr_level_service.invalidate_learner_card", autospec=True
    ) as card, patch(
        "app.services.cefr_level_service.get_redis",
        autospec=True,
        return_value=redis,
    ):
        await set_working_level(WorkingLevelUpdate(level="B1"), db_session, user)

    card.assert_awaited_once_with(user.id)
    redis.delete.assert_awaited_once_with(f"rec:insights:{user.id}")


async def test_set_working_level_rejects_an_unknown_level(db_session, user):
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as raised:
        await set_working_level(WorkingLevelUpdate(level="Z9"), db_session, user)
    assert raised.value.status_code == 422


async def test_profile_update_ignores_an_unknown_level(db_session, user):
    await update_current_user_profile(UserUpdate(level="Z9"), user, db_session)

    assert user.level == "A1"


def test_rank_reads_the_certified_level_not_the_working_one():
    from app.services.rank_service import rank_proficiency_level

    user = User(level="C2", certified_level="A2")
    assert rank_proficiency_level(user) == "A2"
    assert rank_proficiency_level(User(level="C2", certified_level=None)) == "A1"
    assert rank_proficiency_level(User(level="B1", certified_level="b1")) == "B1"
