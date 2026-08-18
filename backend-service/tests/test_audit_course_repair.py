"""Guard for scripts/audit_course_content.py::_repair_exercise."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from audit_course_content import _repair_exercise


def _arrange(**overrides):
    exercise = {
        "id": "ex_1",
        "type": "reorder",
        "ui_type": "arrange_the_sentence",
        "question": "Arrange the words.",
        "options": ["they", "study", "every", "day"],
        "correct_answer": "they study every day",
    }
    exercise.update(overrides)
    return exercise


def test_valid_arrange_is_left_alone():
    exercise = _arrange()
    assert _repair_exercise(exercise) is None
    assert exercise == _arrange()


def test_single_word_arrange_is_not_turned_into_a_one_option_mcq():
    # Its answer is legitimately in the bank; converting would self-grade.
    exercise = _arrange(options=["Yes"], correct_answer="Yes")
    assert _repair_exercise(exercise) is None
    assert exercise["ui_type"] == "arrange_the_sentence"


def test_candidate_sentences_become_multiple_choice():
    exercise = _arrange(
        options=["Go straight.", "Straight go.", "Go the straight."],
        correct_answer="Go straight.",
    )
    assert _repair_exercise(exercise) == "arrange -> multiple_choice"
    assert exercise["ui_type"] == "multiple_choice"
    assert exercise["type"] == "multiple_choice"


def test_empty_word_bank_is_rebuilt_from_the_answer():
    exercise = _arrange(options=[], correct_answer="Are you a student?")
    assert _repair_exercise(exercise) == "arrange word bank rebuilt"
    assert exercise["options"] == ["Are", "you", "a", "student"]
    # and the repair is idempotent
    assert _repair_exercise(exercise) is None


def test_arrange_without_an_answer_is_reported_not_emptied():
    exercise = _arrange(options=[], correct_answer="")
    assert _repair_exercise(exercise) is None
    assert exercise["options"] == []


def test_image_question_without_an_image_becomes_multiple_choice():
    exercise = {
        "id": "ex_2",
        "type": "multiple_choice",
        "ui_type": "image_based_choice",
        "question": "Which one is a table?",
        "options": ["Table", "Chair"],
        "correct_answer": "Table",
    }
    assert _repair_exercise(exercise).startswith("image_based_choice -> multiple_choice")
    assert exercise["ui_type"] == "multiple_choice"
    assert _repair_exercise(exercise) is None


def test_image_question_with_an_image_is_left_alone():
    exercise = {
        "id": "ex_3",
        "type": "multiple_choice",
        "ui_type": "image_based_choice",
        "question": "Which one is a table?",
        "options": ["Table", "Chair"],
        "correct_answer": "Table",
        "image_url": "https://example.test/table.png",
    }
    assert _repair_exercise(exercise) is None
