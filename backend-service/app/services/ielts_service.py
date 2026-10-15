"""Grading an IELTS attempt end to end.

Test content shape (`IeltsTest.content`):

    {"sections": [
        {"skill": "listening", "duration_minutes": 30, "parts": [
            {"order": 1, "title": "Part 1", "audio_url": "...",
             "transcript": "...", "instructions": "...",
             "question_groups": [
                {"question_type": "form_completion",
                 "instructions": "Write NO MORE THAN TWO WORDS",
                 "questions": [{"key": "L1", "number": 1, "prompt": "...",
                                "accepted_answers": ["library"],
                                "options": [...]}]}]}]},
        {"skill": "writing", "duration_minutes": 60, "parts": [
            {"order": 1, "part_key": "writing_task_1", "prompt": "...",
             "image_url": "...", "min_words": 150}]}]}

A learner's `answers` is a flat map keyed by the question `key` for
Listening/Reading, and by `part_key` for Writing/Speaking. Flat because the
client posts answers as it goes and a nested structure would need merging on
every save.
"""

from __future__ import annotations

import logging
from typing import Any, Iterator

from app.models.ielts import PRODUCTIVE_SKILLS
from app.services.ielts_scoring import (
    answer_matches,
    listening_band,
    overall_band,
    reading_band,
    round_to_half_band,
)

logger = logging.getLogger(__name__)

OBJECTIVE_SKILLS = ("listening", "reading")


def iter_sections(content: dict | None, skill: str | None = None) -> Iterator[dict]:
    for section in (content or {}).get("sections") or []:
        if not isinstance(section, dict):
            continue
        if skill and (section.get("skill") or "").strip().lower() != skill:
            continue
        yield section


def iter_questions(content: dict | None, skill: str | None = None) -> Iterator[dict]:
    """Every answerable question in a paper, in order."""
    for section in iter_sections(content, skill):
        for part in section.get("parts") or []:
            if not isinstance(part, dict):
                continue
            for group in part.get("question_groups") or []:
                if not isinstance(group, dict):
                    continue
                for question in group.get("questions") or []:
                    if isinstance(question, dict) and question.get("key"):
                        yield question


def iter_productive_parts(content: dict | None) -> Iterator[tuple[str, dict]]:
    """(skill, part) for every Writing task and Speaking part."""
    for skill in PRODUCTIVE_SKILLS:
        for section in iter_sections(content, skill):
            for part in section.get("parts") or []:
                if isinstance(part, dict) and part.get("part_key"):
                    yield skill, part


def grade_objective_skill(
    content: dict | None,
    answers: dict[str, Any],
    skill: str,
    test_type: str = "academic",
) -> tuple[int, int, float | None]:
    """Return (raw, total, band) for Listening or Reading.

    Band is None when the paper has no questions for that skill, which is how a
    Writing-only paper avoids reporting a band 0 for Listening.
    """
    questions = list(iter_questions(content, skill))
    if not questions:
        return 0, 0, None

    raw = 0
    for question in questions:
        given = answers.get(str(question.get("key")))
        if given is None:
            continue
        accepted = question.get("accepted_answers")
        if accepted is None:
            accepted = question.get("correct_answer")
        if answer_matches(str(given), accepted):
            raw += 1

    total = len(questions)
    if skill == "listening":
        band = listening_band(raw, total)
    else:
        band = reading_band(raw, total, test_type=test_type)
    return raw, total, band


def writing_band_from_tasks(task_bands: dict[str, float]) -> float | None:
    """Combine Writing Task 1 and Task 2, with Task 2 weighted double.

    That 1:2 split is how IELTS weights the two tasks; averaging them flat
    inflates a candidate who wrote a strong 150-word Task 1 and a weak essay.
    """
    if not task_bands:
        return None
    task_1 = task_bands.get("writing_task_1")
    task_2 = task_bands.get("writing_task_2")
    if task_1 is not None and task_2 is not None:
        combined = (float(task_1) + 2 * float(task_2)) / 3
    else:
        values = [float(v) for v in task_bands.values() if v is not None]
        if not values:
            return None
        combined = sum(values) / len(values)
    return round_to_half_band(combined)


def speaking_band_from_parts(part_bands: dict[str, float]) -> float | None:
    """Speaking parts carry equal weight — the examiner scores the interview as
    one performance, so a flat mean is the closest honest approximation."""
    values = [float(v) for v in part_bands.values() if v is not None]
    if not values:
        return None
    return round_to_half_band(sum(values) / len(values))


def compute_overall(bands: dict[str, float | None], skill_scope: str) -> float | None:
    """Overall band, but only for a full four-skill sitting."""
    if (skill_scope or "full") != "full":
        return None
    return overall_band(bands)


def build_result_summary(
    content: dict | None,
    answers: dict[str, Any],
    bands: dict[str, float | None],
    raw_scores: dict[str, Any],
) -> dict:
    """What the results screen needs: per-question correctness for the
    objective skills, so a learner can review what they got wrong."""
    review: dict[str, list[dict]] = {}
    for skill in OBJECTIVE_SKILLS:
        questions = list(iter_questions(content, skill))
        if not questions:
            continue
        items = []
        for question in questions:
            key = str(question.get("key"))
            given = answers.get(key)
            accepted = question.get("accepted_answers")
            if accepted is None:
                accepted = question.get("correct_answer")
            items.append(
                {
                    "key": key,
                    "number": question.get("number"),
                    "prompt": question.get("prompt"),
                    "user_answer": given,
                    "correct_answer": accepted,
                    "is_correct": bool(
                        given is not None and answer_matches(str(given), accepted)
                    ),
                }
            )
        review[skill] = items
    return {"bands": bands, "raw_scores": raw_scores, "review": review}
