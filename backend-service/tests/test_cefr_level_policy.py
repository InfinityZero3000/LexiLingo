"""CEFR moves only through a level test; practice and profile edits cannot move it."""

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
from app.models.user import User
from app.routes.proficiency import PLACEMENT_QUESTIONS, submit_placement_test
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


async def test_retake_cannot_lower_the_level(db_session, user):
    first = await submit_placement_test(_submission(True), db_session, user)
    held = first["assessed_level"]

    retake = await submit_placement_test(_submission(False), db_session, user)

    assert retake["test_level"] == "A1"
    assert retake["assessed_level"] == held
    assert retake["level_changed"] is False
    assert user.level == held
    assert (await _profile(db_session, user)).assessed_level == held
    assert len(await _history(db_session)) == 1


async def test_passing_a_retake_promotes_and_records_it(db_session, user):
    await submit_placement_test(_submission(False), db_session, user)
    assert user.level == "A1"

    retake = await submit_placement_test(_submission(True), db_session, user)

    assert retake["level_changed"] is True
    rows = sorted(await _history(db_session), key=lambda r: r.new_level)
    assert any(r.change_type == "promotion" and r.previous_level == "A1" for r in rows)
    assert "demotion" not in {r.change_type for r in rows}


async def test_profile_update_accepts_a_starting_level_only_during_onboarding(
    db_session, user
):
    await update_current_user_profile(
        UserUpdate(level="b1", is_onboarding_completed=True), user, db_session
    )
    assert user.level == "B1"
    assert (await _profile(db_session, user)).assessed_level == "B1"

    await update_current_user_profile(UserUpdate(level="C2"), user, db_session)
    await update_current_user_profile(UserUpdate(cefr_level="C2"), user, db_session)

    assert user.level == "B1"
    assert (await _profile(db_session, user)).assessed_level == "B1"


async def test_profile_update_ignores_an_unknown_level(db_session, user):
    await update_current_user_profile(UserUpdate(level="Z9"), user, db_session)

    assert user.level == "A1"
