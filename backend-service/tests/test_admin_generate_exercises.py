from unittest.mock import patch

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Course, Lesson, Unit
from app.services import exercise_generation as svc

PATCH = "app.services.exercise_generation.generate_lesson_exercises"


def _ex(ex_id: str | None, n: int = 1) -> dict:
    return {
        "id": ex_id,
        "type": "multiple_choice",
        "ui_type": "multiple_choice",
        "question": f"Question {n}?",
        "options": ["a", "b"],
        "correct_answer": "a",
        "explanation": "because",
    }


@pytest.fixture
async def lesson(db_session: AsyncSession) -> Lesson:
    course = Course(title="Kitchen English", language="en", level="B1", is_published=False)
    db_session.add(course)
    await db_session.flush()
    unit = Unit(course_id=course.id, title="Cooking", order_index=0)
    db_session.add(unit)
    await db_session.flush()
    row = Lesson(
        course_id=course.id,
        unit_id=unit.id,
        title="Utensils",
        order_index=0,
        lesson_type="lesson",
        content={"exercises": [_ex("ex_old_1")]},
    )
    db_session.add(row)
    await db_session.commit()
    await db_session.refresh(row)
    return row


def _url(lesson_id) -> str:
    return f"/api/v1/admin/lessons/{lesson_id}/generate-exercises"


@pytest.mark.asyncio
async def test_returns_draft_and_does_not_write(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession, lesson: Lesson
):
    with patch(PATCH, autospec=True, return_value=[_ex("g1"), _ex("g2", 2)]) as gen:
        response = await async_client.post(_url(lesson.id), headers=admin_headers)

    assert response.status_code == 200
    assert [e["id"] for e in response.json()["data"]["exercises"]] == ["g1", "g2"]
    kwargs = gen.call_args.kwargs
    assert (kwargs["course_title"], kwargs["level"], kwargs["unit_title"], kwargs["lesson_title"]) == (
        "Kitchen English",
        "B1",
        "Cooking",
        "Utensils",
    )
    await db_session.refresh(lesson)
    assert lesson.content == {"exercises": [_ex("ex_old_1")]}


@pytest.mark.asyncio
async def test_colliding_and_missing_ids_are_reissued(
    async_client: AsyncClient, admin_headers: dict, lesson: Lesson
):
    drafted = [_ex("ex_old_1"), _ex("dup", 2), _ex("dup", 3), _ex(None, 4)]
    with patch(PATCH, autospec=True, return_value=drafted):
        response = await async_client.post(_url(lesson.id), headers=admin_headers)

    ids = [e["id"] for e in response.json()["data"]["exercises"]]
    assert len(set(ids)) == 4
    assert "ex_old_1" not in ids
    assert ids[1] == "dup"


@pytest.mark.asyncio
async def test_unknown_lesson_is_404(async_client: AsyncClient, admin_headers: dict):
    with patch(PATCH, autospec=True) as gen:
        response = await async_client.post(
            _url("00000000-0000-0000-0000-000000000000"), headers=admin_headers
        )
    assert response.status_code == 404
    gen.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("error", "code", "text"),
    [
        (svc.ExerciseGenerationUnavailable("x"), 503, "not configured"),
        (svc.ExerciseGenerationFailed("x"), 502, "try again"),
    ],
)
async def test_service_errors_map_to_status(
    async_client: AsyncClient, admin_headers: dict, lesson: Lesson, error: Exception, code: int, text: str
):
    with patch(PATCH, autospec=True, side_effect=error):
        response = await async_client.post(_url(lesson.id), headers=admin_headers)
    assert response.status_code == code
    assert text in response.text


@pytest.mark.asyncio
async def test_non_admin_is_forbidden(async_client: AsyncClient, auth_headers: dict, lesson: Lesson):
    with patch(PATCH, autospec=True) as gen:
        response = await async_client.post(_url(lesson.id), headers=auth_headers)
    assert response.status_code == 403
    gen.assert_not_called()


@pytest.mark.asyncio
async def test_transaction_ends_before_the_ai_call(
    async_client: AsyncClient, admin_headers: dict, lesson: Lesson
):
    order: list[str] = []
    real_rollback = AsyncSession.rollback

    async def rollback(self):
        order.append("rollback")
        return await real_rollback(self)

    async def generate(**_):
        order.append("generate")
        return [_ex("g1")]

    with patch.object(AsyncSession, "rollback", rollback), patch(PATCH, side_effect=generate):
        response = await async_client.post(_url(lesson.id), headers=admin_headers)

    assert response.status_code == 200
    assert order.index("rollback") < order.index("generate")
