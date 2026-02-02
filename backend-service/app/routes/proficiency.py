"""
Proficiency Assessment API Routes

Provides endpoints for:
1. Getting user's proficiency profile
2. Recording exercise results
3. Checking level up requirements
4. Triggering formal level assessments
"""

from typing import List, Optional
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.proficiency import (
    UserProficiencyProfile,
    UserSkillScore,
    UserLevelHistory,
    ExerciseAttempt,
    SkillType,
)
from app.schemas.proficiency import (
    ProficiencyProfile,
    SkillAssessment,
    ProficiencyLevel,
    ExerciseResult,
    UpdateProficiencyRequest,
    ProficiencyAssessmentResult,
    LevelCheckResponse,
    LEVEL_THRESHOLDS,
)
from app.services.proficiency_service import ProficiencyService


router = APIRouter(prefix="/proficiency", tags=["proficiency"])


@router.get("/profile", response_model=dict)
async def get_proficiency_profile(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get the current user's proficiency profile.
    
    Returns comprehensive information about:
    - Overall assessed level
    - Individual skill scores
    - Progress toward next level
    - Improvement recommendations
    """
    # Get or create profile
    result = await db.execute(
        select(UserProficiencyProfile)
        .where(UserProficiencyProfile.user_id == current_user.id)
    )
    profile = result.scalar_one_or_none()
    
    if not profile:
        # Create new profile for user
        profile = UserProficiencyProfile(
            user_id=current_user.id,
            assessed_level="A1",
            overall_score=0.0,
            total_xp=current_user.xp or 0,
        )
        db.add(profile)
        await db.commit()
        await db.refresh(profile)
    
    # Get skill scores
    skill_result = await db.execute(
        select(UserSkillScore)
        .where(UserSkillScore.profile_id == profile.id)
    )
    skill_scores = skill_result.scalars().all()
    
    # Build skill map
    skills = {}
    for skill_score in skill_scores:
        skills[skill_score.skill.value] = {
            "score": skill_score.score,
            "confidence": skill_score.confidence,
            "estimated_level": skill_score.estimated_level,
            "accuracy": skill_score.accuracy,
            "trend": skill_score.trend,
            "exercises_completed": skill_score.exercises_completed,
        }
    
    # Fill in missing skills with defaults
    for skill_type in SkillType:
        if skill_type.value not in skills:
            skills[skill_type.value] = {
                "score": 0,
                "confidence": 0,
                "estimated_level": "A1",
                "accuracy": 0,
                "trend": "stable",
                "exercises_completed": 0,
            }
    
    # Get level check info
    skill_scores_dict = {
        SkillType(k): v["score"] for k, v in skills.items()
    }
    level_check = ProficiencyService.get_level_requirements_check(
        current_level=ProficiencyLevel(profile.assessed_level),
        skill_scores=skill_scores_dict,
        exercises_completed=profile.total_exercises_completed,
        lessons_completed=profile.total_lessons_completed,
        accuracy=profile.accuracy,
        streak_days=0,  # TODO: Get from streak tracking
    )
    
    return {
        "user_id": str(current_user.id),
        "assessed_level": profile.assessed_level,
        "overall_score": profile.overall_score,
        "total_xp": profile.total_xp,
        "skills": skills,
        "statistics": {
            "exercises_completed": profile.total_exercises_completed,
            "correct_exercises": profile.total_correct_exercises,
            "accuracy": round(profile.accuracy * 100, 1),
            "lessons_completed": profile.total_lessons_completed,
        },
        "next_level": {
            "level": level_check.next_level.value if level_check.next_level else None,
            "progress": level_check.overall_progress,
            "qualifies": level_check.qualifies_for_next,
            "requirements": level_check.requirements,
            "blockers": level_check.blockers,
        },
        "last_assessment": profile.last_assessment_at.isoformat() if profile.last_assessment_at else None,
    }


@router.post("/record-exercises", response_model=dict)
async def record_exercise_results(
    results: List[ExerciseResult],
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Record exercise results and update proficiency scores.
    
    This endpoint should be called after completing exercises to:
    1. Update skill scores based on performance
    2. Check for potential level changes
    3. Award XP for gamification
    
    Returns:
    - Updated skill scores
    - Level change notification (if applicable)
    - XP earned
    """
    # Get profile
    result = await db.execute(
        select(UserProficiencyProfile)
        .where(UserProficiencyProfile.user_id == current_user.id)
    )
    profile = result.scalar_one_or_none()
    
    if not profile:
        profile = UserProficiencyProfile(
            user_id=current_user.id,
            assessed_level="A1",
        )
        db.add(profile)
        await db.commit()
        await db.refresh(profile)
    
    # Record individual exercise attempts
    for exercise in results:
        attempt = ExerciseAttempt(
            user_id=current_user.id,
            exercise_type=exercise.exercise_type,
            skill=SkillType(exercise.skill.value),
            difficulty_level=exercise.difficulty_level.value,
            is_correct=exercise.is_correct,
            score=exercise.score,
            time_spent_seconds=exercise.time_spent_seconds,
            lesson_id=exercise.lesson_id,
            course_id=exercise.course_id,
        )
        db.add(attempt)
    
    # Update profile statistics
    correct_count = sum(1 for r in results if r.is_correct)
    profile.total_exercises_completed += len(results)
    profile.total_correct_exercises += correct_count
    
    # Update skill scores
    previous_level = profile.assessed_level
    skill_updates = {}
    
    for skill_type in SkillType:
        skill_results = [r for r in results if r.skill == SkillType(skill_type.value)]
        
        if not skill_results:
            continue
        
        # Get or create skill score record
        skill_result = await db.execute(
            select(UserSkillScore)
            .where(
                UserSkillScore.profile_id == profile.id,
                UserSkillScore.skill == skill_type
            )
        )
        skill_score = skill_result.scalar_one_or_none()
        
        if not skill_score:
            skill_score = UserSkillScore(
                profile_id=profile.id,
                skill=skill_type,
            )
            db.add(skill_score)
        
        # Calculate new score using the service
        new_score, confidence = ProficiencyService.calculate_skill_score(
            exercises=results,
            skill=skill_type,
            current_score=skill_score.score,
        )
        
        old_score = skill_score.score
        skill_score.score = new_score
        skill_score.confidence = confidence
        skill_score.exercises_completed += len(skill_results)
        skill_score.correct_exercises += sum(1 for r in skill_results if r.is_correct)
        skill_score.last_updated = datetime.utcnow()
        
        skill_updates[skill_type.value] = {
            "previous_score": old_score,
            "new_score": new_score,
            "change": round(new_score - old_score, 2),
        }
    
    # Recalculate overall level
    skill_scores_result = await db.execute(
        select(UserSkillScore)
        .where(UserSkillScore.profile_id == profile.id)
    )
    all_skill_scores = skill_scores_result.scalars().all()
    
    skill_scores_dict = {
        skill_score.skill: skill_score.score
        for skill_score in all_skill_scores
    }
    
    new_level, progress = ProficiencyService.calculate_overall_level(
        skill_scores=skill_scores_dict,
        exercises_completed=profile.total_exercises_completed,
        lessons_completed=profile.total_lessons_completed,
        accuracy=profile.accuracy,
        current_level=ProficiencyLevel(profile.assessed_level),
    )
    
    level_changed = new_level.value != previous_level
    
    if level_changed:
        # Record level change
        history = UserLevelHistory(
            profile_id=profile.id,
            previous_level=previous_level,
            new_level=new_level.value,
            change_type="promotion" if ProficiencyService.get_level_index(new_level) > ProficiencyService.get_level_index(ProficiencyLevel(previous_level)) else "demotion",
            overall_score=profile.overall_score,
            skill_scores_snapshot={s.skill.value: s.score for s in all_skill_scores},
            exercises_completed=profile.total_exercises_completed,
            accuracy=profile.accuracy,
            reason=f"Level updated based on proficiency assessment",
        )
        db.add(history)
        
        profile.assessed_level = new_level.value
        profile.last_level_change_at = datetime.utcnow()
    
    # Calculate XP earned (separate from proficiency)
    xp_earned = ProficiencyService._calculate_xp_from_exercises(results)
    profile.total_xp += xp_earned
    
    # Update overall score
    if all_skill_scores:
        profile.overall_score = sum(s.score for s in all_skill_scores) / len(all_skill_scores)
    
    profile.last_assessment_at = datetime.utcnow()
    
    await db.commit()
    
    return {
        "exercises_recorded": len(results),
        "skill_updates": skill_updates,
        "level_changed": level_changed,
        "previous_level": previous_level,
        "current_level": new_level.value,
        "progress_to_next": progress,
        "xp_earned": xp_earned,
        "total_xp": profile.total_xp,
        "message": f"Congratulations! You've advanced to {new_level.value}!" if level_changed else "Keep practicing to improve your skills!",
    }


@router.get("/level-check", response_model=dict)
async def check_level_requirements(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Check detailed requirements for the next level.
    
    Returns:
    - Current level
    - Requirements for next level with met/unmet status
    - Progress percentage toward each requirement
    - Blockers preventing level up
    """
    # Get profile
    result = await db.execute(
        select(UserProficiencyProfile)
        .where(UserProficiencyProfile.user_id == current_user.id)
    )
    profile = result.scalar_one_or_none()
    
    if not profile:
        return {
            "current_level": "A1",
            "next_level": "A2",
            "overall_progress": 0,
            "qualifies_for_next": False,
            "requirements": {},
            "blockers": ["No proficiency data yet. Complete exercises to start tracking."],
        }
    
    # Get skill scores
    skill_result = await db.execute(
        select(UserSkillScore)
        .where(UserSkillScore.profile_id == profile.id)
    )
    skill_scores = skill_result.scalars().all()
    
    skill_scores_dict = {
        skill_score.skill: skill_score.score
        for skill_score in skill_scores
    }
    
    level_check = ProficiencyService.get_level_requirements_check(
        current_level=ProficiencyLevel(profile.assessed_level),
        skill_scores=skill_scores_dict,
        exercises_completed=profile.total_exercises_completed,
        lessons_completed=profile.total_lessons_completed,
        accuracy=profile.accuracy,
        streak_days=0,  # TODO: Integrate with streak system
    )
    
    return {
        "current_level": profile.assessed_level,
        "next_level": level_check.next_level.value if level_check.next_level else None,
        "overall_progress": level_check.overall_progress,
        "qualifies_for_next": level_check.qualifies_for_next,
        "requirements": level_check.requirements,
        "blockers": level_check.blockers,
    }


@router.get("/level-thresholds", response_model=dict)
async def get_level_thresholds():
    """
    Get all level threshold requirements.
    
    Returns the requirements for each CEFR level (A1-C2).
    Useful for displaying level requirements in the UI.
    """
    thresholds = {}
    
    for level, threshold in LEVEL_THRESHOLDS.items():
        thresholds[level.value] = {
            "min_vocabulary_score": threshold.min_vocabulary_score,
            "min_grammar_score": threshold.min_grammar_score,
            "min_reading_score": threshold.min_reading_score,
            "min_listening_score": threshold.min_listening_score,
            "min_speaking_score": threshold.min_speaking_score,
            "min_writing_score": threshold.min_writing_score,
            "min_overall_score": threshold.min_overall_score,
            "min_exercises_completed": threshold.min_exercises_completed,
            "min_lessons_completed": threshold.min_lessons_completed,
            "min_accuracy": threshold.min_accuracy,
            "min_streak_days": threshold.min_streak_days,
        }
    
    return {
        "levels": thresholds,
        "skill_weights": {
            "vocabulary": 0.25,
            "grammar": 0.25,
            "reading": 0.15,
            "listening": 0.15,
            "speaking": 0.10,
            "writing": 0.10,
        },
        "description": "Requirements for each CEFR level. Users must meet ALL criteria to advance.",
    }


@router.get("/history", response_model=dict)
async def get_level_history(
    limit: int = 10,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get the user's level change history.
    
    Shows past level changes with context about what triggered each change.
    """
    # Get profile
    result = await db.execute(
        select(UserProficiencyProfile)
        .where(UserProficiencyProfile.user_id == current_user.id)
    )
    profile = result.scalar_one_or_none()
    
    if not profile:
        return {"history": []}
    
    # Get level history
    history_result = await db.execute(
        select(UserLevelHistory)
        .where(UserLevelHistory.profile_id == profile.id)
        .order_by(UserLevelHistory.triggered_at.desc())
        .limit(limit)
    )
    history = history_result.scalars().all()
    
    return {
        "current_level": profile.assessed_level,
        "history": [
            {
                "previous_level": h.previous_level,
                "new_level": h.new_level,
                "change_type": h.change_type,
                "reason": h.reason,
                "overall_score": h.overall_score,
                "accuracy": h.accuracy,
                "triggered_at": h.triggered_at.isoformat() if h.triggered_at else None,
            }
            for h in history
        ],
    }
