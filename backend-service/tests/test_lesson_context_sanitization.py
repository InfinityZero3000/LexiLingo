from app.routes.learning import _sanitize_lesson_context


def test_lesson_context_recursively_removes_answer_material():
    content = {
        "objectives": ["Practice greetings"],
        "exercises": [
            {
                "question": "Choose hello",
                "correct_answer": "hello",
                "options": [
                    {"text": "hello", "is_correct": True},
                    {"text": "bye", "is_correct": False},
                ],
            }
        ],
    }

    sanitized = _sanitize_lesson_context(content)

    assert sanitized["objectives"] == ["Practice greetings"]
    assert sanitized["exercises"][0]["question"] == "Choose hello"
    assert "correct_answer" not in sanitized["exercises"][0]
    assert all(
        "is_correct" not in option
        for option in sanitized["exercises"][0]["options"]
    )
