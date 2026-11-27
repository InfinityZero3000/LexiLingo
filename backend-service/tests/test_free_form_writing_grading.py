"""Free-form writing must not be graded by string equality.

Production went from ~6 to 440 `short_writing_answer` exercises in one content
regeneration — roughly one exercise in six. Each one was graded by comparing
the learner's sentence to a single stored phrasing, so any correct answer worded
differently scored zero. That did not just lower a score: the wrong answer fed
`_emit_concept_observation`, which moves the BKT/FSRS schedule, and lowered the
lesson score that credits a CEFR skill.
"""

import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.core.free_form_writing import shape_problems  # noqa: E402
from app.routes.learning import (  # noqa: E402
    _answers_match,
    _is_free_form_writing,
)

MODEL = "The cartels want to use soccer to gain power"


class TestFreeFormWriting:
    def test_a_correctly_worded_answer_is_not_marked_wrong(self):
        # The exact case from the audit: same meaning, different words.
        learner = "Cartels see soccer as a way to gain power."
        assert _answers_match(learner, MODEL, "fill_blank", "short_writing_answer")

    def test_the_same_answer_would_fail_exact_matching(self):
        # Proves the fix is doing the work, not that the strings happen to match.
        learner = "Cartels see soccer as a way to gain power."
        assert not _answers_match(learner, MODEL, "fill_blank", "multiple_choice")

    def test_a_blank_or_throwaway_answer_is_still_refused(self):
        for answer in ("", "   ", "ok", "a"):
            assert not _answers_match(
                answer, MODEL, "fill_blank", "short_writing_answer"
            ), f"{answer!r} should not count as an attempt"

    def test_a_keyboard_mash_or_another_language_is_wrong(self):
        # The reported case: anything of 3+ characters used to pass.
        prompt = 'Write in English: "Xin chào, chào buổi sáng".'
        for answer in ("ádasdasdddddddddddddddddddd", "asdf qwer zxcv", "Xin chào buổi sáng"):
            assert not _answers_match(
                answer, "Hello, good morning", "fill_blank", "short_writing_answer", prompt
            ), answer

    def test_a_translation_must_carry_the_model_answers_meaning(self):
        prompt = "Write in English: 'Cô ấy nói tiếng Anh.'"
        model = "She speaks English"
        for answer in ("She speaks English.", "she can speak english", "She speaks English very well"):
            assert _answers_match(answer, model, "fill_blank", "short_writing_answer", prompt), answer
        for answer in ("He plays football every day.", "Hello there friend"):
            assert not _answers_match(answer, model, "fill_blank", "short_writing_answer", prompt), answer

    def test_an_open_gap_accepts_any_real_answer_but_not_a_filler(self):
        prompt = "I have a {blank} on my desk."
        assert _answers_match("book", "pen", "fill_blank", "short_writing_answer", prompt)
        assert not _answers_match("ok", "pen", "fill_blank", "short_writing_answer", prompt)

    def test_true_false_and_choice_questions_are_not_free_writing(self):
        assert shape_problems("True or False: Overviews come last.", "False")
        assert shape_problems("Match the question type to the correct essay structure.", "Opinion essay")
        assert shape_problems("Which phrase is most appropriate here?", "whereas")
        assert not shape_problems("Describe your weekend in one sentence.", "I went to the beach.")

    def test_a_vietnamese_task_wants_vietnamese(self):
        prompt = "Translate into Vietnamese: 'I am a student.'"
        model = "Tôi là sinh viên."
        assert _answers_match("Tôi là một sinh viên", model, "fill_blank", "short_writing_answer", prompt)
        assert not _answers_match("I am a student", model, "fill_blank", "short_writing_answer", prompt)
        assert not _answers_match("ádasd đđđđđ", model, "fill_blank", "short_writing_answer", prompt)

    def test_an_open_prompt_still_accepts_any_real_sentence(self):
        prompt = "Describe your weekend in one sentence."
        model = "I went to the beach with my family."
        assert _answers_match(
            "I visited my grandparents and played football.", model, "fill_blank",
            "short_writing_answer", prompt,
        )

    def test_a_translation_prompt_without_a_model_answer_cannot_be_graded(self):
        assert shape_problems("Write in English: 'Cảm ơn bạn.'", "")
        assert shape_problems("Write a sentence in English.", "Cảm ơn | Thank you")
        assert not shape_problems("Write in English: 'Cảm ơn bạn.'", "Thank you.")


class TestNeighbouringTypesAreUnchanged:
    """Types with exactly one right answer must keep exact matching."""

    def test_dictation_still_requires_the_right_words(self):
        assert not _answers_match("teh cat sat", "the cat sat", "fill_blank", "dictation")
        assert _answers_match("The cat sat.", "the cat sat", "fill_blank", "dictation")

    def test_translation_still_requires_the_right_answer(self):
        assert not _answers_match(
            "xin chao ban", "xin chao", "translate", "translation_choice"
        )

    def test_speaking_still_uses_similarity(self):
        assert _answers_match(
            "I go to the store", "I go to the store.", "translate", "speaking_repeat"
        )

    def test_only_writing_is_classified_as_free_form(self):
        assert _is_free_form_writing("short_writing_answer")
        for other in ("dictation", "translation_choice", "multiple_choice",
                      "fill_in_the_blank", "speaking_repeat", None):
            assert not _is_free_form_writing(other), other
