"""When the card goes stale, backend must say so — and only then."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Course
from app.models.user import User
from app.routes import courses as courses_routes


@pytest.mark.asyncio
async def test_enrolment_invalidates_the_card(
    db_session: AsyncSession, test_user: User, monkeypatch
) -> None:
    course = Course(
        title="Business English",
        language="en",
        level="B1",
        is_published=True,
        total_lessons=8,
    )
    db_session.add(course)
    await db_session.commit()
    await db_session.refresh(course)

    invalidated: list[str] = []

    async def spy(user_id) -> None:
        invalidated.append(str(user_id))

    monkeypatch.setattr(courses_routes, "invalidate_learner_card", spy)

    await courses_routes.enroll_in_course(
        course_id=course.id, db=db_session, current_user=test_user
    )
    assert invalidated == [str(test_user.id)]

    # Enrolling again changes nothing, so it must not fire a second time.
    await courses_routes.enroll_in_course(
        course_id=course.id, db=db_session, current_user=test_user
    )
    assert invalidated == [str(test_user.id)]


@pytest.mark.asyncio
async def test_a_failing_invalidation_does_not_fail_the_enrolment(
    db_session: AsyncSession, test_user: User, monkeypatch
) -> None:
    """The card carries a TTL; losing the push must never cost the enrolment."""
    from app.clients import ai_service_client

    course = Course(
        title="Everyday English",
        language="en",
        level="A2",
        is_published=True,
        total_lessons=5,
    )
    db_session.add(course)
    await db_session.commit()
    await db_session.refresh(course)

    monkeypatch.setenv("AI_ADMIN_API_KEY", "set-so-the-call-is-attempted")

    def explode(*args, **kwargs):
        raise RuntimeError("ai-service is down")

    monkeypatch.setattr(ai_service_client.httpx, "AsyncClient", explode)

    response = await courses_routes.enroll_in_course(
        course_id=course.id, db=db_session, current_user=test_user
    )
    assert response.data.course_id == course.id
