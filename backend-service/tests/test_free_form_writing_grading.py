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

from app.routes.learning import (  # noqa: E402
    _answers_match,
    _free_form_answer_is_substantive,
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

    def test_substantive_check_is_about_length_not_content(self):
        assert _free_form_answer_is_substantive("soccer gives them reach")
        assert not _free_form_answer_is_substantive("  ")


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
