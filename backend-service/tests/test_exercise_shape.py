"""exercise_shape_problems: each rejected shape once reached learners as an
unanswerable question."""
import pytest

from app.models.course import Lesson, exercise_shape_problems, repaired_shape_problems


def _ex(ui_type, **fields):
    return {"id": "e1", "ui_type": ui_type, "question": "Q?", **fields}


@pytest.mark.parametrize(
    "exercise",
    [
        _ex("multiple_choice", options=["a", "b"], correct_answer="b"),
        _ex("true_or_false", correct_answer="True"),
        _ex(
            "arrange_the_sentence",
            options=["every", "she", "reads", "morning"],
            correct_answer="She reads every morning.",
        ),
        _ex(
            "match_word_to_meaning",
            options=["one", "two", "một", "hai"],
            correct_answer="one:một, two:hai",
        ),
        # Categories repeat: one per word, not one per bucket.
        _ex(
            "categorization",
            options=["apple", "pear", "dog", "fruit", "fruit", "animal"],
            correct_answer="apple:fruit, pear:fruit, dog:animal",
        ),
        _ex("dialogue_completion", question="A: Hi! B: {blank}", correct_answer="Hello"),
        _ex("short_writing_answer", correct_answer=""),
        _ex("dictation", correct_answer="I like tea"),
        _ex(
            "multiple_choice",
            options=[{"id": "0", "text": "a"}, {"id": "1", "text": "b"}],
            correct_answer="a",
        ),
    ],
)
def test_playable_shapes_pass(exercise):
    assert exercise_shape_problems(exercise) == []


@pytest.mark.parametrize(
    "exercise, expected",
    [
        (_ex("nonsense", correct_answer="x"), "unknown ui_type"),
        (_ex("multiple_choice", options=["a", "b"], correct_answer="c"), "not one of the options"),
        (_ex("multiple_choice", options=[], correct_answer="a"), "at least 2 options"),
        (_ex("true_or_false", correct_answer="yes"), "True or False"),
        # Bank missing a word: the sentence can never be completed.
        (
            _ex("arrange_the_sentence", options=["she", "reads"], correct_answer="she reads books"),
            "exactly the words",
        ),
        (_ex("arrange_the_sentence", options=None, correct_answer="she reads"), "exactly the words"),
        # "|" join: the grader splits on "," and grades every answer wrong.
        (
            _ex("match_word_to_meaning", options=["one", "two", "một", "hai"], correct_answer="one:một | two:hai"),
            "pairs joined by",
        ),
        (
            _ex("match_word_to_meaning", options=["one", "two", "một", "hai"], correct_answer="one:hai, two:ba"),
            "do not match",
        ),
        (_ex("match_word_to_meaning", options=None, correct_answer="one:một"), "every key then every value"),
        (_ex("image_based_choice", options=["a", "b"], correct_answer="a"), "image_url"),
        (_ex("dialogue_completion", question="A: Hi! B: Hello", correct_answer="Hello"), "{blank}"),
        (_ex("fill_in_the_blank", correct_answer=""), "correct_answer is empty"),
    ],
)
def test_unplayable_shapes_are_named(exercise, expected):
    problems = exercise_shape_problems(exercise)
    assert any(expected in p for p in problems), problems


def test_content_write_derives_type_from_ui_type():
    lesson = Lesson()
    lesson.content = {"exercises": [_ex("arrange_the_sentence", type="multiple_choice")]}
    assert lesson.content["exercises"][0]["type"] == "reorder"


@pytest.mark.parametrize(
    "exercise",
    [
        _ex("multiple_choice", options=["Cat", "cat.", "dog"], correct_answer="dog"),
        _ex("multiple_choice", options=["a b", "a  b", "c"], correct_answer="c"),
        _ex("listen_and_choose", options=["Yes!", "yes", "no"], correct_answer="no"),
        _ex("fill_in_the_blank", options=["go", "Go", "went"], correct_answer="went"),
    ],
)
def test_options_that_read_the_same_are_ambiguous(exercise):
    problems = exercise_shape_problems(exercise)
    assert any("ambiguous" in p for p in problems), problems


@pytest.mark.parametrize(
    "exercise",
    [
        _ex("multiple_choice", options=["a", "b", "c"], correct_answer="b"),
        _ex(
            "match_word_to_meaning",
            options=["one", "One", "một", "Một"],
            correct_answer="one:một, One:Một",
        ),
        _ex("arrange_the_sentence", options=["so", "So", "it", "is"], correct_answer="So so it is"),
        _ex("categorization", options=["a", "b", "x", "x"], correct_answer="a:x, b:x"),
    ],
)
def test_pair_and_arrange_types_keep_repeated_words(exercise):
    assert exercise_shape_problems(exercise) == []


def test_repaired_shape_problems_applies_the_retype_apply_would():
    misused = _ex("short_writing_answer", options=["True", "False"], correct_answer="True")
    assert exercise_shape_problems(misused)
    assert repaired_shape_problems(misused) == []
    assert misused["ui_type"] == "short_writing_answer"
