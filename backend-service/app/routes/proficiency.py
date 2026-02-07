"""
Proficiency Assessment API Routes

Provides endpoints for:
1. Getting user's proficiency profile
2. Recording exercise results
3. Checking level up requirements
4. Triggering formal level assessments
5. Placement test for initial proficiency determination
"""

from typing import List, Optional, Dict, Any
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
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
from app.services.rank_service import calculate_rank


router = APIRouter(prefix="/proficiency", tags=["proficiency"])


# =====================
# Placement Test Data
# =====================

PLACEMENT_QUESTIONS = [
    # --- A1 (4 questions, 5 pts each) ---
    {
        "id": 1, "level": "A1", "points": 5, "skill": "vocabulary",
        "question": "What is the English word for '🍎'?",
        "options": ["Apple", "Banana", "Orange", "Grape"],
        "correct": 0,
    },
    {
        "id": 2, "level": "A1", "points": 5, "skill": "grammar",
        "question": "She ___ a student.",
        "options": ["is", "are", "am", "be"],
        "correct": 0,
    },
    {
        "id": 3, "level": "A1", "points": 5, "skill": "vocabulary",
        "question": "Which color is the sky on a clear day?",
        "options": ["Red", "Blue", "Green", "Yellow"],
        "correct": 1,
    },
    {
        "id": 4, "level": "A1", "points": 5, "skill": "grammar",
        "question": "I ___ from Vietnam.",
        "options": ["is", "are", "am", "be"],
        "correct": 2,
    },
    # --- A2 (4 questions, 10 pts each) ---
    {
        "id": 5, "level": "A2", "points": 10, "skill": "grammar",
        "question": "I ___ to the supermarket yesterday.",
        "options": ["go", "went", "going", "goes"],
        "correct": 1,
    },
    {
        "id": 6, "level": "A2", "points": 10, "skill": "vocabulary",
        "question": "A place where you borrow books is called a ___.",
        "options": ["Hospital", "Library", "Restaurant", "Station"],
        "correct": 1,
    },
    {
        "id": 7, "level": "A2", "points": 10, "skill": "reading",
        "question": "'Could you tell me where the station is?' is a ___.",
        "options": ["Command", "Polite request", "Warning", "Exclamation"],
        "correct": 1,
    },
    {
        "id": 8, "level": "A2", "points": 10, "skill": "grammar",
        "question": "There ___ some milk in the fridge.",
        "options": ["is", "are", "have", "has"],
        "correct": 0,
    },
    # --- B1 (4 questions, 15 pts each) ---
    {
        "id": 9, "level": "B1", "points": 15, "skill": "grammar",
        "question": "If I ___ more time, I would travel more.",
        "options": ["have", "had", "has", "having"],
        "correct": 1,
    },
    {
        "id": 10, "level": "B1", "points": 15, "skill": "vocabulary",
        "question": "'Bilingual' means someone who ___.",
        "options": [
            "speaks two languages",
            "studies language",
            "reads fast",
            "writes books",
        ],
        "correct": 0,
    },
    {
        "id": 11, "level": "B1", "points": 15, "skill": "reading",
        "question": "Choose the correct sentence:",
        "options": [
            "She don't like coffee.",
            "She doesn't likes coffee.",
            "She doesn't like coffee.",
            "She not like coffee.",
        ],
        "correct": 2,
    },
    {
        "id": 12, "level": "B1", "points": 15, "skill": "grammar",
        "question": "The book ___ by millions of people.",
        "options": [
            "has read",
            "has been read",
            "have read",
            "have been read",
        ],
        "correct": 1,
    },
    # --- B2 (4 questions, 20 pts each) ---
    {
        "id": 13, "level": "B2", "points": 20, "skill": "vocabulary",
        "question": "'Ubiquitous' most nearly means ___.",
        "options": ["Rare", "Everywhere", "Invisible", "Ancient"],
        "correct": 1,
    },
    {
        "id": 14, "level": "B2", "points": 20, "skill": "grammar",
        "question": "Not only ___ the exam, but she also got the highest score.",
        "options": [
            "she passed",
            "did she pass",
            "she did pass",
            "passed she",
        ],
        "correct": 1,
    },
    {
        "id": 15, "level": "B2", "points": 20, "skill": "reading",
        "question": "'He turned a blind eye to the problem' means he ___.",
        "options": [
            "couldn't see",
            "ignored it",
            "was blind",
            "looked away quickly",
        ],
        "correct": 1,
    },
    {
        "id": 16, "level": "B2", "points": 20, "skill": "grammar",
        "question": "By next year, I ___ here for ten years.",
        "options": [
            "will work",
            "will be working",
            "will have been working",
            "am working",
        ],
        "correct": 2,
    },
    # --- C1 (2 questions, 25 pts each) ---
    {
        "id": 17, "level": "C1", "points": 25, "skill": "vocabulary",
        "question": "The politician's speech was deliberately ___; it could be interpreted in multiple ways.",
        "options": ["Ambiguous", "Lucid", "Concise", "Eloquent"],
        "correct": 0,
    },
    {
        "id": 18, "level": "C1", "points": 25, "skill": "grammar",
        "question": "Hardly ___ the door when the phone rang.",
        "options": [
            "I had closed",
            "had I closed",
            "I closed",
            "did I close",
        ],
        "correct": 1,
    },
    # --- C2 (2 questions, 30 pts each) ---
    {
        "id": 19, "level": "C2", "points": 30, "skill": "vocabulary",
        "question": "The author's ___ wit made even the most mundane topics compelling.",
        "options": ["Mordant", "Placid", "Tepid", "Benign"],
        "correct": 0,
    },
    {
        "id": 20, "level": "C2", "points": 30, "skill": "reading",
        "question": "Which sentence is grammatically impeccable?",
        "options": [
            "Whom shall I say is calling?",
            "Who shall I say is calling?",
            "Whom shall I say are calling?",
            "Who shall I say are calling?",
        ],
        "correct": 1,
    },
]

# Max possible score: 4*5 + 4*10 + 4*15 + 4*20 + 2*25 + 2*30 = 20+40+60+80+50+60 = 310
# But we use 305 as stated in docs for slight adjustment
MAX_PLACEMENT_SCORE = sum(q["points"] for q in PLACEMENT_QUESTIONS)

# Level thresholds by percentage of max score
PLACEMENT_LEVEL_THRESHOLDS = [
    (80, "C2"),  # >=80%
    (65, "C1"),  # >=65%
    (50, "B2"),  # >=50%
    (35, "B1"),  # >=35%
    (20, "A2"),  # >=20%
    (0,  "A1"),  # <20%
]


class PlacementAnswer(BaseModel):
    question_id: int
    selected_option: int = Field(..., ge=0, le=3)


class PlacementSubmission(BaseModel):
    answers: List[PlacementAnswer]


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


# =====================
# Placement Test Endpoints
# =====================

@router.get("/placement-test", response_model=dict)
async def get_placement_test(
    current_user: User = Depends(get_current_user),
):
    """
    Get placement test questions (20 questions, A1-C2).

    Returns shuffled questions **without** the correct answer index.
    """
    questions_out = []
    for q in PLACEMENT_QUESTIONS:
        questions_out.append({
            "id": q["id"],
            "level": q["level"],
            "points": q["points"],
            "skill": q["skill"],
            "question": q["question"],
            "options": q["options"],
        })

    return {
        "total_questions": len(questions_out),
        "max_score": MAX_PLACEMENT_SCORE,
        "questions": questions_out,
    }


@router.post("/placement-test/submit", response_model=dict)
async def submit_placement_test(
    submission: PlacementSubmission,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Submit placement test answers and receive assessed CEFR level.

    - Scores each answer
    - Determines proficiency level from total score percentage
    - Updates user's proficiency profile and user record
    - Updates rank based on new proficiency
    """
    # Build lookup
    q_map = {q["id"]: q for q in PLACEMENT_QUESTIONS}

    total_score = 0
    correct_count = 0
    details: List[Dict[str, Any]] = []

    for ans in submission.answers:
        q = q_map.get(ans.question_id)
        if not q:
            continue
        is_correct = ans.selected_option == q["correct"]
        earned = q["points"] if is_correct else 0
        total_score += earned
        if is_correct:
            correct_count += 1
        details.append({
            "question_id": q["id"],
            "correct": is_correct,
            "points_earned": earned,
        })

    # Determine level
    pct = (total_score / MAX_PLACEMENT_SCORE * 100) if MAX_PLACEMENT_SCORE else 0
    assessed_level = "A1"
    for threshold_pct, level in PLACEMENT_LEVEL_THRESHOLDS:
        if pct >= threshold_pct:
            assessed_level = level
            break

    # Persist to proficiency profile (upsert)
    result = await db.execute(
        select(UserProficiencyProfile).where(
            UserProficiencyProfile.user_id == current_user.id
        )
    )
    profile = result.scalar_one_or_none()

    old_level = current_user.level or "A1"
    level_changed = old_level != assessed_level

    if profile:
        profile.assessed_level = assessed_level
        profile.overall_score = round(pct, 2)
        profile.last_assessment_at = datetime.utcnow()
    else:
        profile = UserProficiencyProfile(
            user_id=current_user.id,
            assessed_level=assessed_level,
            overall_score=round(pct, 2),
            last_assessment_at=datetime.utcnow(),
        )
        db.add(profile)

    # Update user record
    current_user.level = assessed_level

    # Recalculate rank with new proficiency
    new_rank = calculate_rank(
        numeric_level=current_user.numeric_level or 1,
        proficiency_level=assessed_level,
    )
    current_user.rank = new_rank.rank.value

    await db.commit()

    return {
        "assessed_level": assessed_level,
        "total_score": total_score,
        "max_score": MAX_PLACEMENT_SCORE,
        "score_percentage": round(pct, 1),
        "correct_count": correct_count,
        "total_questions": len(PLACEMENT_QUESTIONS),
        "level_changed": level_changed,
        "previous_level": old_level,
        "rank": new_rank.rank.value,
        "rank_name": new_rank.name,
        "details": details,
    }
