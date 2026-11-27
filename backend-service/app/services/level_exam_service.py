"""The CEFR promotion exam: who may sit it, what the paper is, how it is graded.

The paper has one section per level above the learner's certified level, as far
as the question bank reaches. A section passes at its exam's `passing_score`;
the result is the highest level reached through an unbroken run of passed
sections, so one sitting can certify several levels at once. Failing the first
section changes nothing and starts a cooldown.

Questions come from `question_bank`. A published `test_exams` row for a level
narrows the pool to its curated `question_ids` when it holds enough of that
level, and supplies the pass mark. A question the server cannot grade with
certainty (not multiple choice, or its answer is not one of its options) is
left out of the paper rather than guessed.
"""

from __future__ import annotations

import random
import re
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import QuestionItem, TestExam
from app.models.progress import Streak
from app.models.proficiency import (
    LevelExamAttempt,
    UserProficiencyProfile,
    UserSkillScore,
)
from app.models.user import User
from app.schemas.proficiency import ProficiencyLevel, SkillType
from app.services.cefr_level_service import CEFR_LEVELS, level_index
from app.services.proficiency_service import ProficiencyService
from app.services.rank_service import rank_proficiency_level

SECTION_SIZE = 5
MIN_GRADED_QUESTIONS = 3
SECONDS_PER_QUESTION = 90
SUBMIT_GRACE = timedelta(seconds=60)
COOLDOWN = timedelta(hours=24)
DEFAULT_PASS_PERCENT = 70
_CHOICE_TYPES = {"mcq", "multiple_choice", "single_choice"}


def normalise_answer(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value)).strip().casefold()


def _options(question: QuestionItem) -> list[str]:
    raw = question.options
    if not isinstance(raw, list):
        return []
    return [str(option) for option in raw if isinstance(option, (str, int, float))]


def correct_option(question: QuestionItem) -> str | None:
    """The option text that is correct, or None when it cannot be told for sure."""
    options = _options(question)
    answer = question.answer
    if isinstance(answer, dict):
        for key in ("correct", "answer", "value"):
            if key in answer:
                answer = answer[key]
                break
        else:
            return None
    if isinstance(answer, list) and len(answer) == 1:
        answer = answer[0]
    if isinstance(answer, int) and not isinstance(answer, bool):
        return options[answer] if 0 <= answer < len(options) else None
    if isinstance(answer, str):
        matches = [option for option in options if normalise_answer(option) == normalise_answer(answer)]
        return matches[0] if len(matches) == 1 else None
    return None


def is_gradable(question: QuestionItem) -> bool:
    return (
        (question.question_type or "mcq").lower() in _CHOICE_TYPES
        and len(_options(question)) >= 2
        and correct_option(question) is not None
    )


def answer_text(question: QuestionItem, given: Any) -> str | None:
    options = _options(question)
    if isinstance(given, int) and not isinstance(given, bool):
        return options[given] if 0 <= given < len(options) else None
    if isinstance(given, str):
        return given
    return None


def public_question(question: QuestionItem, level: str) -> dict[str, Any]:
    """What the learner sees while sitting the exam: no answer, no explanation."""
    return {
        "id": str(question.id),
        "level": level,
        "question_type": question.question_type or "mcq",
        "prompt": question.prompt,
        "options": _options(question),
    }


async def _section_pool(db: AsyncSession, level: str) -> tuple[list[QuestionItem], int]:
    exam = (
        await db.execute(
            select(TestExam)
            .where(TestExam.level == level, TestExam.is_published.is_(True))
            .order_by(desc(TestExam.updated_at))
            .limit(1)
        )
    ).scalar_one_or_none()
    questions = [
        question
        for question in (
            await db.execute(
                select(QuestionItem).where(
                    QuestionItem.difficulty_level == level,
                    QuestionItem.is_active.is_(True),
                )
            )
        ).scalars()
        if is_gradable(question)
    ]
    if exam is not None and isinstance(exam.question_ids, list):
        curated = {str(question_id) for question_id in exam.question_ids}
        preferred = [question for question in questions if str(question.id) in curated]
        if len(preferred) >= SECTION_SIZE:
            questions = preferred
    pass_percent = exam.passing_score if exam is not None and exam.passing_score else DEFAULT_PASS_PERCENT
    return questions, int(pass_percent)


def levels_above(level: str) -> list[str]:
    return list(CEFR_LEVELS[level_index(level) + 1 :])


async def build_paper(
    db: AsyncSession, from_level: str, rng: random.Random | None = None
) -> list[dict[str, Any]]:
    """Sections from the next level up, stopping at the first level the bank cannot fill."""
    rng = rng or random.SystemRandom()
    sections: list[dict[str, Any]] = []
    for level in levels_above(from_level):
        pool, pass_percent = await _section_pool(db, level)
        if len(pool) < SECTION_SIZE:
            break
        picked = rng.sample(pool, SECTION_SIZE)
        sections.append(
            {
                "level": level,
                "question_ids": [str(question.id) for question in picked],
                "pass_percent": pass_percent,
            }
        )
    return sections


async def load_questions(
    db: AsyncSession, sections: list[dict[str, Any]]
) -> dict[str, QuestionItem]:
    ids = [question_id for section in sections for question_id in section["question_ids"]]
    if not ids:
        return {}
    rows = (
        await db.execute(select(QuestionItem).where(QuestionItem.id.in_(ids)))
    ).scalars()
    return {str(row.id): row for row in rows}


def grade(
    sections: list[dict[str, Any]],
    questions: dict[str, QuestionItem],
    answers: dict[str, Any],
) -> tuple[str | None, list[dict[str, Any]], float]:
    """(result level or None, per-section scores, overall percent).

    A question deleted since the paper was drawn is not counted against the
    learner: a section is marked over the questions still there, and one left
    with fewer than MIN_GRADED_QUESTIONS is `graded: False` rather than failed.
    An ungraded section ends the run of passed sections, so nothing is
    certified on evidence we do not have.
    """
    scores: list[dict[str, Any]] = []
    result: str | None = None
    unbroken = True
    correct_total = 0
    question_total = 0
    for section in sections:
        correct = 0
        total = 0
        for question_id in section["question_ids"]:
            question = questions.get(question_id)
            if question is None:
                continue
            total += 1
            given = answer_text(question, answers.get(question_id))
            if given is not None and normalise_answer(given) == normalise_answer(correct_option(question)):
                correct += 1
        graded = total >= MIN_GRADED_QUESTIONS
        passed = graded and correct * 100 >= section["pass_percent"] * total
        scores.append(
            {
                "level": section["level"],
                "correct": correct,
                "total": total,
                "passed": passed,
                "graded": graded,
            }
        )
        if unbroken and passed:
            result = section["level"]
        else:
            unbroken = False
        if graded:
            correct_total += correct
            question_total += total
    percent = round(correct_total * 100 / question_total, 1) if question_total else 0.0
    return result, scores, percent


def is_void(section_scores: list[dict[str, Any]] | None) -> bool:
    """The run of passed sections ended before it began, on a section we could not grade.

    That says nothing about the learner, whatever the later sections scored:
    no level is certified and no cooldown starts. A run that ends on a graded,
    failed section is an ordinary failure.
    """
    return bool(section_scores) and not section_scores[0].get("graded", True)


async def latest_attempt(db: AsyncSession, user_id: Any) -> LevelExamAttempt | None:
    return (
        await db.execute(
            select(LevelExamAttempt)
            .where(LevelExamAttempt.user_id == user_id)
            .order_by(desc(LevelExamAttempt.started_at))
            .limit(1)
        )
    ).scalar_one_or_none()


def as_utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def is_past_deadline(attempt: LevelExamAttempt, now: datetime) -> bool:
    return now > as_utc(attempt.expires_at) + SUBMIT_GRACE


def retry_at(attempt: LevelExamAttempt) -> datetime | None:
    """When a failed or lapsed sitting allows the next one; None if it did not fail."""
    failed = attempt.status == "expired" or (
        attempt.status == "submitted"
        and attempt.result_level is None
        and not is_void(attempt.section_scores)
    )
    if not failed:
        return None
    ended = attempt.submitted_at or attempt.expires_at
    return as_utc(ended) + COOLDOWN


async def requirements_check(
    db: AsyncSession, user: User, profile: UserProficiencyProfile, current_level: str
):
    """The same readiness check `GET /proficiency/profile` shows, from a given level."""
    rows = (
        await db.execute(
            select(UserSkillScore).where(UserSkillScore.profile_id == profile.id)
        )
    ).scalars()
    scores = {skill: 0.0 for skill in SkillType}
    confidences = {skill: 0.0 for skill in SkillType}
    for row in rows:
        scores[SkillType(row.skill.value)] = row.score or 0.0
        confidences[SkillType(row.skill.value)] = row.confidence or 0.0
    streak = (
        await db.execute(select(Streak).where(Streak.user_id == user.id))
    ).scalar_one_or_none()
    return ProficiencyService.get_level_requirements_check(
        current_level=ProficiencyLevel(current_level),
        skill_scores=scores,
        exercises_completed=profile.total_exercises_completed or 0,
        lessons_completed=profile.total_lessons_completed or 0,
        accuracy=profile.accuracy if profile.total_exercises_completed else 0.0,
        streak_days=streak.current_streak if streak else 0,
        skill_confidences=confidences,
    )


async def eligibility(
    db: AsyncSession,
    user: User,
    profile: UserProficiencyProfile,
    now: datetime | None = None,
) -> dict[str, Any]:
    """Whether the learner may start a sitting now, and if not, why.

    Checked in this order: nothing above to reach, a sitting already open,
    the cooldown after a failure, readiness, and a bank that can fill the
    first section.
    """
    now = now or datetime.now(UTC)
    certified = rank_proficiency_level(user)
    above = levels_above(certified)
    base: dict[str, Any] = {
        "available": False,
        "reason": None,
        "from_level": certified,
        "target_level": above[0] if above else None,
        "retry_at": None,
        "attempt_id": None,
        "progress": None,
        "blockers": [],
    }
    if not above:
        return {**base, "reason": "max_level"}

    last = await latest_attempt(db, user.id)
    if last is not None and last.status == "in_progress" and not is_past_deadline(last, now):
        return {**base, "available": True, "reason": "in_progress", "attempt_id": str(last.id)}
    if last is not None and last.status == "in_progress":
        # Lapsed but never submitted: counts as a failure from its deadline.
        lapsed_until = as_utc(last.expires_at) + COOLDOWN
        if now < lapsed_until:
            return {**base, "reason": "cooldown", "retry_at": lapsed_until.isoformat()}
    elif last is not None:
        until = retry_at(last)
        if until is not None and now < until:
            return {**base, "reason": "cooldown", "retry_at": until.isoformat()}

    check = await requirements_check(db, user, profile, certified)
    if not check.qualifies_for_next:
        return {
            **base,
            "reason": "not_ready",
            "progress": check.overall_progress,
            "blockers": list(check.blockers),
        }

    pool, _ = await _section_pool(db, above[0])
    if len(pool) < SECTION_SIZE:
        return {**base, "reason": "no_questions"}

    return {**base, "available": True, "reason": "ready", "progress": check.overall_progress}
