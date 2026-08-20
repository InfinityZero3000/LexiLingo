"""Band conversion and answer matching — the parts where being subtly wrong
produces a plausible score that is not an IELTS score."""

import pytest

from app.services.ielts_scoring import (
    answer_matches,
    listening_band,
    normalize_answer,
    overall_band,
    reading_band,
    round_to_half_band,
)
from app.services.ielts_service import (
    grade_objective_skill,
    speaking_band_from_parts,
    writing_band_from_tasks,
)


@pytest.mark.parametrize(
    "raw,expected",
    [(40, 9.0), (39, 9.0), (35, 8.0), (30, 7.0), (26, 6.5), (23, 6.0), (16, 5.0), (0, 0.0)],
)
def test_listening_band_boundaries(raw, expected):
    assert listening_band(raw) == expected


def test_reading_general_training_is_harder_than_academic():
    # 30/40 is band 7 Academic but only band 6 General Training. Using one table
    # for both papers inflates every GT result by up to a full band.
    assert reading_band(30, test_type="academic") == 7.0
    assert reading_band(30, test_type="general_training") == 6.0


def test_short_paper_scales_to_forty_question_equivalent():
    # A 20-question practice set at 15 correct is the same proportion as 30/40.
    assert listening_band(15, total=20) == listening_band(30, total=40)


@pytest.mark.parametrize(
    "value,expected",
    [(6.375, 6.5), (6.25, 6.5), (6.125, 6.0), (6.75, 7.0), (6.5, 6.5), (7.0, 7.0)],
)
def test_half_band_rounding_sends_quarters_up(value, expected):
    assert round_to_half_band(value) == expected


def test_overall_band_needs_all_four_skills():
    full = {"listening": 6.5, "reading": 6.5, "writing": 5.5, "speaking": 7.0}
    assert overall_band(full) == 6.5
    assert overall_band({"listening": 8.0, "reading": 8.0}) is None


def test_answer_matching_ignores_case_punctuation_and_articles():
    assert answer_matches("  LIBRARY.", ["library"])
    assert answer_matches("the library", ["library"])
    assert answer_matches("library", ["the library"])
    assert answer_matches("21st March", ["21st march"])
    assert not answer_matches("", ["library"])
    assert not answer_matches("museum", ["library"])


def test_answer_matching_accepts_any_listed_variant():
    assert answer_matches("15", ["fifteen", "15"])
    assert answer_matches("fifteen", ["fifteen", "15"])


def test_writing_weights_task_two_double():
    # Strong Task 1, weak Task 2 must not average out flat: (7 + 2*5)/3 = 5.67 → 5.5
    assert writing_band_from_tasks({"writing_task_1": 7.0, "writing_task_2": 5.0}) == 5.5
    assert writing_band_from_tasks({"writing_task_2": 6.0}) == 6.0
    assert writing_band_from_tasks({}) is None


def test_speaking_parts_weigh_equally():
    assert speaking_band_from_parts({"speaking_part_1": 6.0, "speaking_part_2": 7.0}) == 6.5
    assert speaking_band_from_parts({}) is None


def _paper(n_questions: int) -> dict:
    return {
        "sections": [
            {
                "skill": "reading",
                "parts": [
                    {
                        "order": 1,
                        "question_groups": [
                            {
                                "questions": [
                                    {
                                        "key": f"R{i}",
                                        "number": i,
                                        "prompt": f"Q{i}",
                                        "accepted_answers": [f"answer{i}"],
                                    }
                                    for i in range(1, n_questions + 1)
                                ]
                            }
                        ],
                    }
                ],
            }
        ]
    }


def test_grade_objective_skill_counts_only_matching_answers():
    content = _paper(10)
    answers = {f"R{i}": f"answer{i}" for i in range(1, 8)}
    answers["R8"] = "wrong"
    raw, total, band = grade_objective_skill(content, answers, "reading")
    assert (raw, total) == (7, 10)
    assert band == reading_band(7, 10)


def test_missing_skill_reports_no_band_rather_than_zero():
    # A Writing-only paper must not report Listening band 0 — that is a score
    # nobody sat for, and it would drag an overall band down.
    raw, total, band = grade_objective_skill(_paper(5), {}, "listening")
    assert (raw, total, band) == (0, 0, None)


def test_normalize_keeps_hyphens_and_apostrophes():
    assert normalize_answer("Mother's day-care!") == "mother's day-care"
