"""Guard for scripts/generate_exercises_ai.py::sanitize_exercises."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from generate_exercises_ai import (
    exercises_from_payload,
    lesson_is_varied,
    needs_regeneration,
    sanitize_exercises,
)


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


def _arrange(**overrides):
    defaults = {
        "type": "reorder",
        "ui_type": "arrange_the_sentence",
        "question": "Arrange the words into a sentence.",
        "options": ["day", "every", "study", "they"],
        "correct_answer": "they study every day",
    }
    return _mc(**{**defaults, **overrides})


def test_accepts_arrange_whose_answer_is_not_an_option():
    assert len(sanitize_exercises([_arrange()])) == 1


def test_accepts_arrange_with_punctuation_in_the_answer():
    assert len(sanitize_exercises([
        _arrange(options=["Are", "you", "a", "student"],
                 correct_answer="Are you a student?")
    ])) == 1


def test_rejects_arrange_without_word_bank():
    assert sanitize_exercises([_arrange(options=[])]) == []


def test_rejects_arrange_whose_bank_is_not_the_sentence():
    # The model answered with candidate sentences instead of a word bank.
    assert sanitize_exercises([
        _arrange(options=["Go straight.", "Straight go."],
                 correct_answer="Go straight.")
    ]) == []


def test_rejects_empty_and_malformed_payloads():
    assert sanitize_exercises([]) == []
    assert sanitize_exercises("nope") == []
    assert sanitize_exercises([_mc(), "nope"]) == []


def test_rejects_single_option_flashcard():
    assert sanitize_exercises([
        _mc(ui_type="vocabulary_flashcard", options=["Got it!"],
            correct_answer="Got it!")
    ]) == []


# ── lesson-level bar ─────────────────────────────────────────────────────────

def _lesson(*ui_types, question="Complete the booking email."):
    return [_mc(ui_type=ui, question=question) for ui in ui_types]


def test_varied_lesson_passes():
    assert lesson_is_varied(
        _lesson("multiple_choice", "true_or_false", "fill_in_the_blank",
                "short_writing_answer")
    )


def test_recognition_only_lesson_is_rejected():
    assert not lesson_is_varied(
        _lesson("multiple_choice", "true_or_false", "translation_choice",
                "reading_comprehension")
    )


def test_repeated_ui_types_are_rejected():
    assert not lesson_is_varied(
        _lesson("multiple_choice", "multiple_choice", "dictation")
    )


def test_generic_instruction_is_rejected():
    assert not lesson_is_varied(
        _lesson("multiple_choice", "match_word_to_meaning", "dictation",
                question="Match the words with their meanings")
    )


def test_needs_regeneration_reports_weak_content():
    weak = {"exercises": _lesson("multiple_choice", "true_or_false",
                                 "translation_choice")}
    strong = {"exercises": _lesson("multiple_choice", "true_or_false",
                                   "dictation")}

    assert needs_regeneration(None) == "empty"
    assert needs_regeneration({"exercises": []}) == "empty"
    assert needs_regeneration(weak) is not None
    assert needs_regeneration(strong) is None


def test_payload_unwrapping_covers_what_the_model_actually_returns():
    # A bare array cost a full retry ("'list' object has no attribute 'get'")
    # during the production run.
    assert exercises_from_payload({"exercises": [_mc()]}) == [_mc()]
    assert exercises_from_payload([_mc()]) == [_mc()]
    assert exercises_from_payload({"exercises": "nope"}) == []
    assert exercises_from_payload({}) == []
    assert exercises_from_payload("nope") == []


def test_type_is_derived_from_ui_type_not_taken_from_the_model():
    cleaned = sanitize_exercises([
        _mc(ui_type="short_writing_answer", type="short_writing_answer",
            options=[], correct_answer="I visited my grandmother.")
    ])
    assert cleaned[0]["type"] == "fill_blank"


def test_unknown_ui_type_is_rejected():
    assert sanitize_exercises([_mc(ui_type="made_up_type")]) == []
