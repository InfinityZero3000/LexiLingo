"""Generated exercises are written through the ORM, stamped with their origin."""
import pytest

from app.services.exercise_generation import generated_content


@pytest.mark.asyncio
async def test_generated_content_is_stamped_and_counted_by_the_content_hook(
    db_session, test_lesson
):
    exercises = [
        {
            "id": "ex_1",
            "ui_type": "multiple_choice",
            "question": "Pick one",
            "options": ["a", "b"],
            "correct_answer": "a",
        }
    ]
    test_lesson.content = generated_content(exercises, "some/model")
    await db_session.commit()
    await db_session.refresh(test_lesson)

    assert test_lesson.content["generated_by"] == "exercise-generation"
    assert test_lesson.content["model"] == "some/model"
    assert test_lesson.content["generated_at"].endswith("+00:00")
    assert test_lesson.content["exercises"][0]["type"] == "multiple_choice"
    assert test_lesson.exercise_count == 1
