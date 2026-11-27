"""A failed proficiency update must not turn a finished lesson into a 500."""

from httpx import AsyncClient
from sqlalchemy import text

from app.routes import learning


async def test_completion_survives_a_failed_proficiency_statement(
    async_client: AsyncClient,
    auth_headers: dict,
    test_lesson_attempt,
    test_course,
    db_session,
    monkeypatch,
):
    # A passed attempt: the route queries the next lesson after the update.
    test_lesson_attempt.score = 100
    test_course.level = "A1"  # proficiency is only tracked for CEFR courses
    await db_session.commit()
    attempt_id = str(test_lesson_attempt.id)

    async def failing_update(db, current_user, results):
        await db.execute(text("SELECT * FROM table_that_does_not_exist"))

    monkeypatch.setattr(learning, "record_exercise_results_for_user", failing_update)

    response = await async_client.post(
        f"/api/v1/learning/attempts/{attempt_id}/complete", headers=auth_headers
    )

    assert response.status_code == 200, response.text
    assert response.json()["data"]["attempt_id"] == attempt_id
