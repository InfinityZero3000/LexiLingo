"""Generated exercises are written through the ORM, stamped with their origin."""
import pytest

from app.services.exercise_generation import VerifiedExercises, generated_content


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


def test_generated_content_keeps_the_verification_of_a_verified_batch():
    verification = {"method": "blind-answer-v1", "status": "verified", "checked": 4, "agreed": 3, "dropped": ["ex_2"]}
    assert generated_content(VerifiedExercises([], verification))["verification"] == verification


def test_generated_content_omits_verification_for_a_plain_list():
    assert "verification" not in generated_content([])
