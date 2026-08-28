"""Aggregation contract for the internal learner-card route."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Course
from app.models.progress import UserCourseProgress
from app.models.user import User
from app.routes.learner_card import get_learner_card


async def _make_course(db: AsyncSession, title: str, level: str) -> Course:
    course = Course(
        title=title,
        description=f"{title} description",
        language="en",
        level=level,
        is_published=True,
        total_lessons=10,
    )
    db.add(course)
    await db.commit()
    await db.refresh(course)
    return course


@pytest.mark.asyncio
async def test_card_suggests_nearest_level_and_hides_enrolled(
    db_session: AsyncSession, test_user: User
) -> None:
    test_user.level = "B1"
    far = await _make_course(db_session, "Advanced", "C2")
    near = await _make_course(db_session, "Pre-Intermediate", "B1")
    enrolled_course = await _make_course(db_session, "Everyday English", "B1")
    db_session.add(
        UserCourseProgress(
            user_id=test_user.id,
            course_id=enrolled_course.id,
            progress_percentage=42.0,
            lessons_completed=4,
        )
    )
    await db_session.commit()

    card = await get_learner_card(str(test_user.id), _caller="ai-service", db=db_session)

    assert card["display_name"] == "Test User"
    assert card["assessed_level"] == "B1"

    titles = [item["title"] for item in card["suggested_courses"]]
    # The course they are already taking is not a suggestion...
    assert "Everyday English" not in titles
    # ...and the one at their own level outranks the one four levels away.
    assert titles.index("Pre-Intermediate") < titles.index("Advanced")
    assert {far.title, near.title} <= set(titles)

    enrolled = card["enrolled_courses"]
    assert len(enrolled) == 1
    assert enrolled[0]["title"] == "Everyday English"
    assert enrolled[0]["progress"] == 42.0


@pytest.mark.asyncio
async def test_a_course_with_a_legacy_level_sorts_last_not_as_a1(
    db_session: AsyncSession, test_user: User
) -> None:
    """Older rows carry values like "beginner". Treating those as A1 would let
    a course we cannot place outrank one labelled at the learner's own level."""
    test_user.level = "B1"
    await _make_course(db_session, "Legacy Course", "beginner")
    await _make_course(db_session, "At My Level", "B1")
    await _make_course(db_session, "One Band Up", "B2")
    await db_session.commit()

    card = await get_learner_card(str(test_user.id), _caller="ai-service", db=db_session)
    titles = [item["title"] for item in card["suggested_courses"]]

    assert titles.index("At My Level") < titles.index("Legacy Course")
    assert titles.index("One Band Up") < titles.index("Legacy Course")


@pytest.mark.asyncio
async def test_card_rejects_a_non_uuid_user_id(db_session: AsyncSession) -> None:
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as excinfo:
        await get_learner_card("not-a-uuid", _caller="ai-service", db=db_session)
    assert excinfo.value.status_code == 400
