"""Learner-facing IELTS mock tests: browse, sit, submit, review."""

from __future__ import annotations

import copy
import logging
from datetime import datetime, timezone
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select, and_, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal, get_db
from app.core.dependencies import get_current_user
from app.clients.ai_service_client import grade_ielts_submission
from app.models.ielts import IeltsAttempt, IeltsGrading, IeltsTest
from app.models.user import User
from app.schemas.response import ApiResponse
from app.services.ielts_service import (
    OBJECTIVE_SKILLS,
    build_result_summary,
    compute_overall,
    grade_objective_skill,
    iter_productive_parts,
    iter_questions,
    speaking_band_from_parts,
    writing_band_from_tasks,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/ielts", tags=["IELTS"])

# Keys stripped from a paper before it reaches the learner. Without this the
# answer key ships inside the same response the client renders the paper from.
_ANSWER_KEYS = ("accepted_answers", "correct_answer", "explanation", "transcript")


class IeltsTestSummary(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    test_type: str
    skill_scope: str
    target_band: Optional[str] = None
    section_count: int = 0
    question_count: int = 0
    duration_minutes: int = 0


class StartAttemptRequest(BaseModel):
    skill_scope: str = Field(default="full")


class SaveAnswersRequest(BaseModel):
    answers: dict[str, Any]
    time_spent_seconds: int = 0


class SubmitAttemptRequest(BaseModel):
    answers: dict[str, Any] = Field(default_factory=dict)
    time_spent_seconds: int = 0


def _strip_answers(content: dict | None) -> dict:
    """Deep-copy the paper with every answer-bearing field removed."""
    clean = copy.deepcopy(content or {})
    for section in clean.get("sections") or []:
        if not isinstance(section, dict):
            continue
        for part in section.get("parts") or []:
            if not isinstance(part, dict):
                continue
            part.pop("transcript", None)
            for group in part.get("question_groups") or []:
                if not isinstance(group, dict):
                    continue
                for question in group.get("questions") or []:
                    if isinstance(question, dict):
                        for key in _ANSWER_KEYS:
                            question.pop(key, None)
    return clean


def _summarize(test: IeltsTest) -> IeltsTestSummary:
    content = test.content or {}
    sections = content.get("sections") or []
    duration = sum(int(s.get("duration_minutes") or 0) for s in sections if isinstance(s, dict))
    return IeltsTestSummary(
        id=str(test.id),
        title=test.title,
        description=test.description,
        test_type=test.test_type,
        skill_scope=test.skill_scope,
        target_band=test.target_band,
        section_count=len(sections),
        question_count=len(list(iter_questions(content))),
        duration_minutes=duration,
    )


@router.get("/tests", response_model=ApiResponse[list[IeltsTestSummary]])
async def list_tests(
    test_type: Optional[str] = Query(None),
    skill_scope: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = select(IeltsTest).where(IeltsTest.is_published.is_(True))
    if test_type:
        query = query.where(IeltsTest.test_type == test_type)
    if skill_scope:
        query = query.where(IeltsTest.skill_scope == skill_scope)
    result = await db.execute(query.order_by(IeltsTest.created_at.desc()))
    return ApiResponse(data=[_summarize(t) for t in result.scalars().all()])


@router.get("/tests/{test_id}", response_model=ApiResponse[dict])
async def get_test(
    test_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    test = await db.get(IeltsTest, test_id)
    if not test or not test.is_published:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Test not found")
    summary = _summarize(test)
    return ApiResponse(
        data={**summary.model_dump(), "content": _strip_answers(test.content)}
    )


@router.post("/tests/{test_id}/start", response_model=ApiResponse[dict])
async def start_attempt(
    test_id: UUID,
    body: StartAttemptRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    test = await db.get(IeltsTest, test_id)
    if not test or not test.is_published:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Test not found")

    # Resume rather than start a second sitting of the same paper — a learner
    # who reloads mid-test must not lose what they have already answered.
    existing = await db.execute(
        select(IeltsAttempt).where(
            and_(
                IeltsAttempt.user_id == current_user.id,
                IeltsAttempt.test_id == test_id,
                IeltsAttempt.status == "in_progress",
            )
        )
    )
    attempt = existing.scalar_one_or_none()
    if attempt is None:
        attempt = IeltsAttempt(
            user_id=current_user.id,
            test_id=test_id,
            skill_scope=body.skill_scope or test.skill_scope,
            answers={},
        )
        db.add(attempt)
        await db.commit()
        await db.refresh(attempt)

    return ApiResponse(
        data={
            "attempt_id": str(attempt.id),
            "status": attempt.status,
            "skill_scope": attempt.skill_scope,
            "answers": attempt.answers or {},
            "started_at": attempt.started_at.isoformat() if attempt.started_at else None,
            "content": _strip_answers(test.content),
        }
    )


async def _load_attempt(db: AsyncSession, attempt_id: UUID, user: User) -> IeltsAttempt:
    attempt = await db.get(IeltsAttempt, attempt_id)
    if not attempt or attempt.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Attempt not found")
    return attempt


@router.patch("/attempts/{attempt_id}/answers", response_model=ApiResponse[dict])
async def save_answers(
    attempt_id: UUID,
    body: SaveAnswersRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Merge in-progress answers. Called as the learner works, so it merges
    rather than replaces — a Reading autosave must not wipe Listening."""
    attempt = await _load_attempt(db, attempt_id, current_user)
    if attempt.status != "in_progress":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Attempt already submitted")

    merged = dict(attempt.answers or {})
    merged.update(body.answers or {})
    attempt.answers = merged
    attempt.time_spent_seconds = max(attempt.time_spent_seconds, body.time_spent_seconds)
    await db.commit()
    return ApiResponse(data={"saved": len(merged)})


async def _grade_productive_in_background(attempt_id: UUID) -> None:
    """Grade every pending Writing/Speaking row, then finalise the attempt.

    Runs on its own session: the request that scheduled it has already
    returned and its session is closed.
    """
    async with AsyncSessionLocal() as db:
        attempt = await db.get(IeltsAttempt, attempt_id)
        if attempt is None:
            return
        test = await db.get(IeltsTest, attempt.test_id)
        content = (test.content or {}) if test else {}
        prompts = {
            part.get("part_key"): part for _, part in iter_productive_parts(content)
        }

        result = await db.execute(
            select(IeltsGrading).where(
                and_(
                    IeltsGrading.attempt_id == attempt_id,
                    IeltsGrading.status == "pending",
                )
            )
        )
        for grading in result.scalars().all():
            part = prompts.get(grading.part_key) or {}
            graded = await grade_ielts_submission(
                skill=grading.skill,
                part_key=grading.part_key,
                task_prompt=str(part.get("prompt") or part.get("cue_card") or ""),
                answer_text=grading.submission_text or "",
                test_type=(test.test_type if test else "academic"),
            )
            if graded is None:
                grading.status = "failed"
                grading.error_detail = "Grader unavailable"
                continue
            grading.criteria_scores = graded.get("criteria")
            grading.band = graded.get("band")
            grading.feedback = graded.get("feedback")
            grading.word_count = int(graded.get("word_count") or 0)
            grading.grader_version = graded.get("grader_version")
            grading.status = "graded"
            grading.graded_at = datetime.now(timezone.utc)

        await db.commit()
        await _finalize_bands(db, attempt_id)


async def _finalize_bands(db: AsyncSession, attempt_id: UUID) -> None:
    attempt = await db.get(IeltsAttempt, attempt_id)
    if attempt is None:
        return
    result = await db.execute(
        select(IeltsGrading).where(IeltsGrading.attempt_id == attempt_id)
    )
    gradings = result.scalars().all()

    writing = {
        g.part_key: float(g.band)
        for g in gradings
        if g.skill == "writing" and g.band is not None
    }
    speaking = {
        g.part_key: float(g.band)
        for g in gradings
        if g.skill == "speaking" and g.band is not None
    }
    attempt.writing_band = writing_band_from_tasks(writing)
    attempt.speaking_band = speaking_band_from_parts(speaking)

    bands = {
        "listening": float(attempt.listening_band) if attempt.listening_band is not None else None,
        "reading": float(attempt.reading_band) if attempt.reading_band is not None else None,
        "writing": attempt.writing_band,
        "speaking": attempt.speaking_band,
    }
    attempt.overall_band = compute_overall(bands, attempt.skill_scope)

    still_pending = any(g.status == "pending" for g in gradings)
    if not still_pending:
        attempt.status = "graded"
        attempt.graded_at = datetime.now(timezone.utc)
    await db.commit()


@router.post("/attempts/{attempt_id}/submit", response_model=ApiResponse[dict])
async def submit_attempt(
    attempt_id: UUID,
    body: SubmitAttemptRequest,
    background: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Grade the objective skills now, queue the AI-graded ones.

    Listening and Reading are an answer key and finish in milliseconds, so the
    learner sees those bands immediately. Writing and Speaking take a model
    call each and are graded in the background; the attempt stays `submitted`
    until they land.
    """
    attempt = await _load_attempt(db, attempt_id, current_user)
    if attempt.status not in {"in_progress", "submitted"}:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Attempt already graded")

    test = await db.get(IeltsTest, attempt.test_id)
    if test is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Test not found")

    answers = dict(attempt.answers or {})
    answers.update(body.answers or {})
    attempt.answers = answers
    attempt.time_spent_seconds = max(attempt.time_spent_seconds, body.time_spent_seconds)
    attempt.submitted_at = datetime.now(timezone.utc)
    attempt.status = "submitted"

    raw_scores: dict[str, Any] = {}
    for skill in OBJECTIVE_SKILLS:
        raw, total, band = grade_objective_skill(
            test.content, answers, skill, test_type=test.test_type
        )
        if total:
            raw_scores[skill] = {"raw": raw, "total": total}
            if skill == "listening":
                attempt.listening_band = band
            else:
                attempt.reading_band = band
    attempt.raw_scores = raw_scores

    queued = 0
    for skill, part in iter_productive_parts(test.content):
        part_key = str(part.get("part_key"))
        submission = answers.get(part_key)
        if not submission or not str(submission).strip():
            continue
        db.add(
            IeltsGrading(
                attempt_id=attempt.id,
                skill=skill,
                part_key=part_key,
                submission_text=str(submission),
                word_count=len(str(submission).split()),
                status="pending",
            )
        )
        queued += 1

    await db.commit()

    if queued:
        background.add_task(_grade_productive_in_background, attempt.id)
    else:
        await _finalize_bands(db, attempt.id)
        await db.refresh(attempt)

    return ApiResponse(
        message="Submitted",
        data={
            "attempt_id": str(attempt.id),
            "status": attempt.status,
            "listening_band": float(attempt.listening_band) if attempt.listening_band is not None else None,
            "reading_band": float(attempt.reading_band) if attempt.reading_band is not None else None,
            "pending_gradings": queued,
            "raw_scores": raw_scores,
        },
    )


@router.get("/attempts/{attempt_id}/result", response_model=ApiResponse[dict])
async def get_result(
    attempt_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    attempt = await _load_attempt(db, attempt_id, current_user)
    test = await db.get(IeltsTest, attempt.test_id)

    bands = {
        "listening": float(attempt.listening_band) if attempt.listening_band is not None else None,
        "reading": float(attempt.reading_band) if attempt.reading_band is not None else None,
        "writing": float(attempt.writing_band) if attempt.writing_band is not None else None,
        "speaking": float(attempt.speaking_band) if attempt.speaking_band is not None else None,
    }
    summary = build_result_summary(
        test.content if test else {},
        attempt.answers or {},
        bands,
        attempt.raw_scores or {},
    )
    return ApiResponse(
        data={
            "attempt_id": str(attempt.id),
            "test_title": test.title if test else None,
            "test_type": test.test_type if test else None,
            "status": attempt.status,
            "overall_band": float(attempt.overall_band) if attempt.overall_band is not None else None,
            "time_spent_seconds": attempt.time_spent_seconds,
            "submitted_at": attempt.submitted_at.isoformat() if attempt.submitted_at else None,
            **summary,
            "gradings": [
                {
                    "skill": g.skill,
                    "part_key": g.part_key,
                    "status": g.status,
                    "band": float(g.band) if g.band is not None else None,
                    "criteria": g.criteria_scores,
                    "feedback": g.feedback,
                    "word_count": g.word_count,
                    "submission_text": g.submission_text,
                }
                for g in attempt.gradings
            ],
        }
    )


@router.get("/attempts", response_model=ApiResponse[list[dict]])
async def list_attempts(
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(IeltsAttempt)
        .where(IeltsAttempt.user_id == current_user.id)
        .order_by(desc(IeltsAttempt.started_at))
        .limit(limit)
    )
    attempts = result.scalars().all()
    return ApiResponse(
        data=[
            {
                "attempt_id": str(a.id),
                "test_id": str(a.test_id),
                "test_title": a.test.title if a.test else None,
                "status": a.status,
                "skill_scope": a.skill_scope,
                "overall_band": float(a.overall_band) if a.overall_band is not None else None,
                "listening_band": float(a.listening_band) if a.listening_band is not None else None,
                "reading_band": float(a.reading_band) if a.reading_band is not None else None,
                "writing_band": float(a.writing_band) if a.writing_band is not None else None,
                "speaking_band": float(a.speaking_band) if a.speaking_band is not None else None,
                "started_at": a.started_at.isoformat() if a.started_at else None,
                "submitted_at": a.submitted_at.isoformat() if a.submitted_at else None,
            }
            for a in attempts
        ]
    )
