"""
Learning Session Routes
Endpoints for lesson attempts and learning sessions (Start/Submit/Complete)
"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from datetime import datetime, timedelta
from uuid import UUID

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.course import Course, Unit, Lesson
from app.models.progress import (
    UserProgress,
    LessonAttempt,
    QuestionAttempt,
    Streak
)
from app.schemas.progress import (
    LessonStartRequest,
    LessonStartResponse,
    AnswerSubmitRequest,
    AnswerSubmitResponse,
    LessonCompleteRequest,
    LessonCompleteResponse,
    CourseRoadmapResponse,
    UnitProgressRoadmap,
    LessonProgressItem,
)
from app.schemas.response import ApiResponse

router = APIRouter(prefix="/learning", tags=["Learning Sessions"])


@router.post("/lessons/{lesson_id}/start", response_model=ApiResponse[LessonStartResponse])
async def start_lesson(
    lesson_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Start a new lesson or resume existing attempt"""
    
    # Check if lesson exists
    result = await db.execute(select(Lesson).where(Lesson.id == lesson_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lesson not found")
    
    # Check for active attempt (not finished)
    result = await db.execute(
        select(LessonAttempt).where(
            and_(
                LessonAttempt.user_id == current_user.id,
                LessonAttempt.lesson_id == lesson_id,
                LessonAttempt.finished_at == None
            )
        )
    )
    existing = result.scalar_one_or_none()
    
    if existing:
        return ApiResponse(
            success=True,
            message="Resumed lesson",
            data=LessonStartResponse(
                attempt_id=existing.id,
                lesson_id=existing.lesson_id,
                started_at=existing.started_at,
                total_questions=existing.total_questions,
                lives_remaining=existing.lives_remaining,
                hints_available=3 - existing.hints_used
            )
        )
    
    # Create new attempt
    new_attempt = LessonAttempt(
        user_id=current_user.id,
        lesson_id=lesson_id,
        started_at=datetime.utcnow(),
        total_questions=10,  # TODO: Get from lesson content
        lives_remaining=3,
        hints_used=0,
        passed=False,
        score=0,
        xp_earned=0,
        time_spent_ms=0,
        correct_answers=0
    )
    
    db.add(new_attempt)
    await db.commit()
    await db.refresh(new_attempt)
    
    return ApiResponse(
        success=True,
        message="Lesson started",
        data=LessonStartResponse(
            attempt_id=new_attempt.id,
            lesson_id=new_attempt.lesson_id,
            started_at=new_attempt.started_at,
            total_questions=new_attempt.total_questions,
            lives_remaining=3,
            hints_available=3
        )
    )


@router.post("/attempts/{attempt_id}/answer", response_model=ApiResponse[AnswerSubmitResponse])
async def submit_answer(
    attempt_id: UUID,
    request: AnswerSubmitRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Submit answer for a question"""
    
    # Get attempt
    result = await db.execute(
        select(LessonAttempt).where(
            and_(
                LessonAttempt.id == attempt_id,
                LessonAttempt.user_id == current_user.id
            )
        )
    )
    attempt = result.scalar_one_or_none()
    
    if not attempt:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Attempt not found")
    if attempt.finished_at is not None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Lesson completed")
    
    # TODO: Validate answer
    is_correct = True  # Mock
    xp = 10 if is_correct else 0
    if request.hint_used:
        xp = max(0, xp - 3)
    
    # Record question attempt
    import json
    qa = QuestionAttempt(
        lesson_attempt_id=attempt_id,
        question_id=str(request.question_id),
        question_type=request.question_type.value,
        user_answer=json.dumps(request.user_answer) if isinstance(request.user_answer, dict) else str(request.user_answer),
        is_correct=is_correct,
        time_spent_ms=request.time_spent_ms,
        hint_used=request.hint_used,
        confidence_score=request.confidence_score
    )
    db.add(qa)
    
    # Update attempt
    if is_correct:
        attempt.correct_answers += 1
    else:
        attempt.lives_remaining = max(0, attempt.lives_remaining - 1)
    
    if request.hint_used:
        attempt.hints_used += 1
    
    attempt.score = int((attempt.correct_answers / attempt.total_questions) * 100)
    attempt.xp_earned += xp
    attempt.time_spent_ms += request.time_spent_ms
    
    await db.commit()
    await db.refresh(qa)
    
    return ApiResponse(
        success=True,
        message="Answer submitted",
        data=AnswerSubmitResponse(
            question_attempt_id=qa.id,
            is_correct=is_correct,
            correct_answer="Sample answer" if not is_correct else None,
            explanation="Great!" if is_correct else "Try again",
            xp_earned=xp,
            lives_remaining=attempt.lives_remaining,
            hints_remaining=max(0, 3 - attempt.hints_used),
            current_score=float(attempt.score)
        )
    )


@router.post("/attempts/{attempt_id}/complete", response_model=ApiResponse[LessonCompleteResponse])
async def complete_lesson(
    attempt_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Complete lesson attempt"""
    
    result = await db.execute(
        select(LessonAttempt).where(
            and_(
                LessonAttempt.id == attempt_id,
                LessonAttempt.user_id == current_user.id
            )
        )
    )
    attempt = result.scalar_one_or_none()
    
    if not attempt:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Attempt not found")
    if attempt.finished_at is not None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Already completed")
    
    # Get lesson info for course_id
    result = await db.execute(select(Lesson).where(Lesson.id == attempt.lesson_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lesson not found")
    
    # Complete
    attempt.finished_at = datetime.utcnow()
    attempt.passed = attempt.score >= 70.0
    
    # Stars
    if attempt.score >= 90:
        stars = 3
    elif attempt.score >= 80:
        stars = 2
    elif attempt.score >= 70:
        stars = 1
    else:
        stars = 0
    
    # Update UserProgress
    result = await db.execute(
        select(UserProgress).where(
            and_(
                UserProgress.user_id == current_user.id,
                UserProgress.lesson_id == attempt.lesson_id
            )
        )
    )
    progress = result.scalar_one_or_none()
    
    if not progress:
        progress = UserProgress(
            user_id=current_user.id,
            lesson_id=attempt.lesson_id,
            course_id=lesson.course_id,
            status="completed" if attempt.passed else "in_progress",
            score=attempt.score,
            completed_at=datetime.utcnow() if attempt.passed else None,
            time_spent_seconds=attempt.time_spent_ms // 1000,
            attempts=1
        )
        db.add(progress)
    else:
        if attempt.passed:
            progress.status = "completed"
            progress.completed_at = datetime.utcnow()
        progress.score = max(progress.score, attempt.score)
        progress.time_spent_seconds += attempt.time_spent_ms // 1000
        progress.attempts += 1
    
    # Update streak
    await _update_streak(db, current_user.id)
    
    await db.commit()
    
    time_sec = attempt.time_spent_ms // 1000
    accuracy = (attempt.correct_answers / attempt.total_questions * 100) if attempt.total_questions > 0 else 0
    
    return ApiResponse(
        success=True,
        message="Congratulations!" if attempt.passed else "Keep practicing!",
        data=LessonCompleteResponse(
            attempt_id=attempt.id,
            passed=attempt.passed,
            final_score=attempt.score,
            total_xp_earned=attempt.xp_earned,
            time_spent_seconds=time_sec,
            accuracy=accuracy,
            stars_earned=stars,
            next_lesson_unlocked=None,  # TODO
            achievements_unlocked=[],  # TODO
            total_questions=attempt.total_questions,
            correct_answers=attempt.correct_answers,
            wrong_answers=attempt.total_questions - attempt.correct_answers,
            hints_used=attempt.hints_used
        )
    )


@router.get("/courses/{course_id}/roadmap", response_model=ApiResponse[CourseRoadmapResponse])
async def get_course_roadmap(
    course_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get course roadmap for UI visualization"""
    
    # Get course with units and lessons
    result = await db.execute(
        select(Course)
        .options(selectinload(Course.units).selectinload(Unit.lessons))
        .where(Course.id == course_id)
    )
    course = result.scalar_one_or_none()
    
    if not course:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Course not found")
    
    # Get progress for all lessons
    lesson_ids = [lesson.id for unit in course.units for lesson in unit.lessons]
    result = await db.execute(
        select(UserProgress).where(
            and_(
                UserProgress.user_id == current_user.id,
                UserProgress.lesson_id.in_(lesson_ids)
            )
        )
    )
    progress_map = {p.lesson_id: p for p in result.scalars().all()}
    
    # Get streak
    result = await db.execute(select(Streak).where(Streak.user_id == current_user.id))
    streak = result.scalar_one_or_none()
    current_streak = streak.current_streak if streak else 0
    
    # Build roadmap
    units_roadmap = []
    completed_units = 0
    completed_lessons_count = 0
    
    for unit in sorted(course.units, key=lambda u: u.order_index):
        lessons_items = []
        unit_completed = 0
        
        for lesson in sorted(unit.lessons, key=lambda l: l.order_index):
            progress = progress_map.get(lesson.id)
            
            # Check if locked
            is_locked = False
            if lesson.order_index > 0:
                prev = next((l for l in unit.lessons if l.order_index == lesson.order_index - 1), None)
                if prev:
                    prev_prog = progress_map.get(prev.id)
                    is_locked = not (prev_prog and prev_prog.status == "completed")
            
            is_completed = (progress.status == "completed") if progress else False
            if is_completed:
                unit_completed += 1
                completed_lessons_count += 1
            
            is_current = not is_locked and not is_completed
            
            lesson_item = LessonProgressItem(
                lesson_id=lesson.id,
                lesson_number=lesson.order_index + 1,
                title=lesson.title,
                description=lesson.description,
                is_locked=is_locked,
                is_current=is_current,
                is_completed=is_completed,
                best_score=progress.score if progress else None,
                stars_earned=_calc_stars(progress.score) if progress and progress.score else 0,
                attempts_count=progress.attempts if progress else 0,
                completion_percentage=100.0 if is_completed else 0.0,
                icon_url=None,  # Lesson model doesn't have icon_url
                background_color="#4CAF50" if is_completed else "#9E9E9E" if is_locked else "#2196F3"
            )
            lessons_items.append(lesson_item)
        
        unit_comp = (unit_completed / len(unit.lessons) * 100) if unit.lessons else 0
        is_unit_current = any(l.is_current for l in lessons_items)
        
        if unit_comp >= 100:
            completed_units += 1
        
        unit_roadmap = UnitProgressRoadmap(
            unit_id=unit.id,
            unit_number=unit.order_index + 1,
            title=unit.title,
            description=unit.description,
            total_lessons=len(unit.lessons),
            completed_lessons=unit_completed,
            completion_percentage=unit_comp,
            is_current=is_unit_current,
            lessons=lessons_items,
            icon_url=unit.icon_url,
            background_color=unit.background_color or "#2196F3"
        )
        units_roadmap.append(unit_roadmap)
    
    total_lessons = sum(len(u.lessons) for u in course.units)
    overall_comp = (completed_lessons_count / total_lessons * 100) if total_lessons > 0 else 0
    
    return ApiResponse(
        success=True,
        message="Roadmap retrieved",
        data=CourseRoadmapResponse(
            course_id=course.id,
            course_title=course.title,
            level=course.level,
            total_units=len(course.units),
            completed_units=completed_units,
            total_lessons=total_lessons,
            completed_lessons=completed_lessons_count,
            completion_percentage=overall_comp,
            total_xp_earned=0,  # TODO: Calculate from attempts
            current_streak=current_streak,
            units=units_roadmap
        )
    )


async def _update_streak(db: AsyncSession, user_id: UUID):
    """Update streak"""
    result = await db.execute(select(Streak).where(Streak.user_id == user_id))
    streak = result.scalar_one_or_none()
    
    today = datetime.utcnow().date()
    
    if not streak:
        streak = Streak(
            user_id=user_id,
            current_streak=1,
            longest_streak=1,
            last_activity_date=today
        )
        db.add(streak)
    else:
        last = streak.last_activity_date
        if last == today:
            pass
        elif last == today - timedelta(days=1):
            streak.current_streak += 1
            streak.longest_streak = max(streak.longest_streak, streak.current_streak)
            streak.last_activity_date = today
        else:
            streak.current_streak = 1
            streak.last_activity_date = today


def _calc_stars(score: float) -> int:
    """Calculate stars"""
    if score >= 90:
        return 3
    elif score >= 80:
        return 2
    elif score >= 70:
        return 1
    return 0
