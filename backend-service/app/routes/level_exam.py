"""CEFR promotion exam: the only way a learner's certified level goes up after placement."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.refusal import refusal
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.proficiency import LevelAssessmentTest, LevelExamAttempt
from app.models.user import User
from app.services import level_exam_service as exam
from app.services.cefr_level_service import (
    apply_level_change,
    get_or_create_profile,
    level_index,
    level_verified,
    normalise_level,
    publish_level_change,
)
from app.services.rank_service import rank_proficiency_level

router = APIRouter(prefix="/proficiency/level-exam", tags=["proficiency"])


class ExamSubmission(BaseModel):
    # question id -> chosen option text (or its index)
    answers: dict[str, str | int] = Field(default_factory=dict)


async def _own_attempt(db: AsyncSession, attempt_id: UUID, user: User) -> LevelExamAttempt:
    attempt = await db.get(LevelExamAttempt, attempt_id)
    if attempt is None or attempt.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Exam attempt not found")
    return attempt


async def _paper(db: AsyncSession, attempt: LevelExamAttempt) -> dict[str, Any]:
    questions = await exam.load_questions(db, attempt.sections)
    return {
        "attempt_id": str(attempt.id),
        "status": attempt.status,
        "from_level": attempt.from_level,
        "started_at": attempt.started_at.isoformat(),
        "expires_at": attempt.expires_at.isoformat(),
        "answers": attempt.answers or {},
        "sections": [
            {
                "level": section["level"],
                "pass_percent": section["pass_percent"],
                "questions": [
                    exam.public_question(questions[question_id], section["level"])
                    for question_id in section["question_ids"]
                    if question_id in questions
                ],
            }
            for section in attempt.sections
        ],
    }


@router.get("/eligibility", response_model=dict)
async def get_eligibility(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Whether the learner may sit the exam now: ready, in_progress, cooldown,
    not_ready, no_questions or max_level."""
    profile = await get_or_create_profile(db, current_user)
    result = await exam.eligibility(db, current_user, profile)
    await db.commit()
    return result


@router.post("/start", response_model=dict)
async def start_exam(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Open a sitting, or resume the one already open (a reload keeps its paper)."""
    profile = await get_or_create_profile(db, current_user)
    gate = await exam.eligibility(db, current_user, profile)
    if gate["reason"] == "in_progress":
        attempt = await _own_attempt(db, UUID(gate["attempt_id"]), current_user)
        await db.commit()
        return await _paper(db, attempt)
    if not gate["available"]:
        await db.commit()
        raise refusal(status.HTTP_403_FORBIDDEN, f"Level exam unavailable: {gate['reason']}", gate)

    from_level = rank_proficiency_level(current_user)
    sections = await exam.build_paper(db, from_level)
    if not sections:
        await db.commit()
        raise refusal(
            status.HTTP_409_CONFLICT,
            "Level exam unavailable: no_questions",
            {**gate, "available": False, "reason": "no_questions"},
        )
    now = datetime.now(UTC)
    question_count = sum(len(section["question_ids"]) for section in sections)
    attempt = LevelExamAttempt(
        user_id=current_user.id,
        from_level=from_level,
        sections=sections,
        answers={},
        status="in_progress",
        started_at=now,
        expires_at=now + timedelta(seconds=exam.SECONDS_PER_QUESTION * question_count),
    )
    db.add(attempt)
    await db.commit()
    await db.refresh(attempt)
    return await _paper(db, attempt)


@router.post("/{attempt_id}/submit", response_model=dict)
async def submit_exam(
    attempt_id: UUID,
    submission: ExamSubmission,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Grade on the server. Passing certifies the highest level reached through
    an unbroken run of passed sections; failing changes nothing and starts the
    cooldown. A sitting submitted after its deadline is closed as expired."""
    attempt = await _own_attempt(db, attempt_id, current_user)
    if attempt.status != "in_progress":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Exam already closed")
    now = datetime.now(UTC)
    if exam.is_past_deadline(attempt, now):
        attempt.status = "expired"
        attempt.submitted_at = now
        await db.commit()
        raise refusal(
            status.HTTP_410_GONE,
            "Exam time is over",
            {"reason": "expired", "retry_at": exam.retry_at(attempt).isoformat()},
        )

    questions = await exam.load_questions(db, attempt.sections)
    answers = {str(key): value for key, value in submission.answers.items()}
    result_level, section_scores, percent = exam.grade(attempt.sections, questions, answers)

    attempt.answers = answers
    attempt.status = "submitted"
    attempt.submitted_at = now
    attempt.result_level = result_level
    attempt.section_scores = section_scores
    attempt.score = percent

    profile = await get_or_create_profile(db, current_user)
    change = None
    if result_level is not None:
        working = normalise_level(current_user.level) or "A1"
        if level_index(result_level) > level_index(working):
            working = result_level
        change = await apply_level_change(
            db,
            current_user,
            profile,
            source="exam",
            working=working,
            certified=result_level,
            score=percent,
        )
    db.add(
        LevelAssessmentTest(
            user_id=current_user.id,
            test_type="promotion",
            assessed_level=result_level or attempt.from_level,
            overall_score=percent,
            skill_scores={},
            questions_count=sum(section["total"] for section in section_scores),
            correct_count=sum(section["correct"] for section in section_scores),
            time_taken_seconds=int((now - exam.as_utc(attempt.started_at)).total_seconds()),
            started_at=attempt.started_at,
            completed_at=now,
            level_changed=change is not None and change.certified_changed,
            previous_level=attempt.from_level,
        )
    )
    await db.commit()
    await publish_level_change(change)

    return {
        "attempt_id": str(attempt.id),
        "passed": result_level is not None,
        "result_level": result_level,
        "from_level": attempt.from_level,
        "certified_level": rank_proficiency_level(current_user),
        "level": current_user.level,
        "level_verified": level_verified(current_user),
        "score": percent,
        "sections": section_scores,
        "retry_at": exam.retry_at(attempt).isoformat() if result_level is None else None,
    }


@router.get("/{attempt_id}/result", response_model=dict)
async def get_exam_result(
    attempt_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The graded paper with the right answers and explanations — only once closed."""
    attempt = await _own_attempt(db, attempt_id, current_user)
    if attempt.status == "in_progress":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Exam still open")
    questions = await exam.load_questions(db, attempt.sections)
    answers = attempt.answers or {}
    review = []
    for section in attempt.sections:
        for question_id in section["question_ids"]:
            question = questions.get(question_id)
            if question is None:
                continue
            correct = exam.correct_option(question)
            given = exam.answer_text(question, answers.get(question_id))
            review.append(
                {
                    **exam.public_question(question, section["level"]),
                    "your_answer": given,
                    "correct_answer": correct,
                    "is_correct": given is not None
                    and exam.normalise_answer(given) == exam.normalise_answer(correct),
                    "explanation": question.explanation,
                }
            )
    return {
        "attempt_id": str(attempt.id),
        "status": attempt.status,
        "from_level": attempt.from_level,
        "result_level": attempt.result_level,
        "score": attempt.score,
        "sections": attempt.section_scores or [],
        "retry_at": exam.retry_at(attempt).isoformat() if exam.retry_at(attempt) else None,
        "questions": review,
    }
