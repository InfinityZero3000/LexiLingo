"""Guard for scripts/generate_exercises_ai.py::sanitize_exercises."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from generate_exercises_ai import sanitize_exercises


def _mc(**overrides):
    exercise = {
        "id": "ex_1",
        "type": "multiple_choice",
        "ui_type": "multiple_choice",
        "question": "Which day comes after Tuesday?",
        "options": ["Monday", "Wednesday"],
        "correct_answer": "Wednesday",
        "explanation": "It follows Tuesday.",
    }
    exercise.update(overrides)
    return exercise


def test_keeps_valid_multiple_choice():
    assert sanitize_exercises([_mc()]) == [_mc()]


def test_rejects_missing_required_field():
    assert sanitize_exercises([_mc(explanation="")]) == []


def test_rejects_answer_outside_options():
    assert sanitize_exercises([_mc(correct_answer="Friday")]) == []


def test_fills_true_false_options():
    cleaned = sanitize_exercises([
        _mc(
            type="true_false",
            ui_type="true_or_false",
            options=[],
            correct_answer="False",
            question="There are 8 days in a week.",
        )
    ])
    assert cleaned[0]["options"] == ["True", "False"]


def test_rejects_true_false_with_non_boolean_answer():
    assert sanitize_exercises([
        _mc(ui_type="true_or_false", options=[], correct_answer="Wednesday")
    ]) == []


def test_rejects_gap_exercise_without_blank_marker():
    assert sanitize_exercises([
        _mc(ui_type="fill_in_the_blank", options=[], question="I ___ to work.")
    ]) == []


def test_accepts_gap_exercise_with_blank_marker():
    assert len(sanitize_exercises([
        _mc(ui_type="fill_in_the_blank", options=[], question="I {blank} to work.")
    ])) == 1


def test_rejects_matching_without_four_options():
    assert sanitize_exercises([
        _mc(ui_type="match_word_to_meaning", options=["dog", "cat"],
            correct_answer="dog:con chó")
    ]) == []


def test_accepts_valid_matching():
    assert len(sanitize_exercises([
        _mc(ui_type="match_word_to_meaning",
            options=["dog", "cat", "con chó", "con mèo"],
            correct_answer="dog:con chó, cat:con mèo")
    ])) == 1


def test_rejects_empty_and_malformed_payloads():
    assert sanitize_exercises([]) == []
    assert sanitize_exercises("nope") == []
    assert sanitize_exercises([_mc(), "nope"]) == []
