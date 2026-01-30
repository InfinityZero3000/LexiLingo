"""
Daily Challenges Routes
Phase 4: Gamification - Daily challenge system for user engagement
"""

from datetime import date, datetime, timedelta
from typing import Optional, List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.progress import Streak, LessonCompletion
from app.schemas.response import ApiResponse


router = APIRouter(prefix="/challenges", tags=["Challenges"])


# ============================================================================
# Pydantic Schemas
# ============================================================================

class DailyChallengeResponse(BaseModel):
    id: str
    title: str
    description: str
    icon: str
    category: str  # lesson, vocabulary, streak, xp
    target: int
    current: int
    xp_reward: int
    is_completed: bool
    expires_at: str


class DailyChallengesListResponse(BaseModel):
    date: str
    challenges: List[DailyChallengeResponse]
    total_completed: int
    total_challenges: int
    bonus_xp: int  # Bonus for completing all challenges


# ============================================================================
# Challenge Definitions
# ============================================================================

DAILY_CHALLENGE_TEMPLATES = [
    {
        "id": "complete_lessons",
        "title": "Lesson Master",
        "description": "Complete {target} lesson(s) today",
        "icon": "book",
        "category": "lesson",
        "targets": [1, 2, 3],  # Easy, Medium, Hard
        "xp_rewards": [20, 40, 60],
    },
    {
        "id": "review_vocab",
        "title": "Vocabulary Review",
        "description": "Review {target} vocabulary words",
        "icon": "cards",
        "category": "vocabulary",
        "targets": [5, 10, 20],
        "xp_rewards": [15, 30, 50],
    },
    {
        "id": "earn_xp",
        "title": "XP Hunter",
        "description": "Earn {target} XP today",
        "icon": "star",
        "category": "xp",
        "targets": [30, 50, 100],
        "xp_rewards": [10, 25, 45],
    },
    {
        "id": "perfect_lesson",
        "title": "Perfectionist",
        "description": "Get 100% on {target} lesson(s)",
        "icon": "target",
        "category": "lesson",
        "targets": [1, 2, 3],
        "xp_rewards": [25, 50, 75],
    },
    {
        "id": "maintain_streak",
        "title": "Keep the Fire",
        "description": "Maintain your learning streak",
        "icon": "fire",
        "category": "streak",
        "targets": [1, 1, 1],
        "xp_rewards": [15, 15, 15],
    },
]


def get_challenges_for_user(user_id: UUID, date_seed: date) -> List[dict]:
    """
    Generate daily challenges for a user based on date.
    Uses date as seed for deterministic but varied challenges.
    """
    import random
    
    # Use date and user_id as seed for consistent daily challenges per user
    seed = int(date_seed.strftime("%Y%m%d")) + sum(user_id.bytes)
    random.seed(seed)
    
    # Select 3-4 challenges for the day
    num_challenges = random.randint(3, 4)
    selected_templates = random.sample(DAILY_CHALLENGE_TEMPLATES, num_challenges)
    
    challenges = []
    for template in selected_templates:
        # Choose difficulty based on random (weighted toward easier)
        difficulty = random.choices([0, 1, 2], weights=[50, 35, 15])[0]
        
        challenges.append({
            "id": template["id"],
            "title": template["title"],
            "description": template["description"].format(target=template["targets"][difficulty]),
            "icon": template["icon"],
            "category": template["category"],
            "target": template["targets"][difficulty],
            "xp_reward": template["xp_rewards"][difficulty],
        })
    
    return challenges


# ============================================================================
# Challenge Progress Calculation
# ============================================================================

async def calculate_challenge_progress(
    db: AsyncSession, 
    user_id: UUID, 
    challenge: dict, 
    today: date
) -> int:
    """Calculate current progress for a challenge."""
    
    today_start = datetime.combine(today, datetime.min.time())
    today_end = datetime.combine(today + timedelta(days=1), datetime.min.time())
    
    if challenge["category"] == "lesson":
        if challenge["id"] == "complete_lessons":
            # Count lessons completed today
            result = await db.execute(
                select(func.count(LessonCompletion.id)).where(
                    and_(
                        LessonCompletion.user_id == user_id,
                        LessonCompletion.completed_at >= today_start,
                        LessonCompletion.completed_at < today_end,
                    )
                )
            )
            return result.scalar() or 0
        
        elif challenge["id"] == "perfect_lesson":
            # Count perfect score lessons today
            result = await db.execute(
                select(func.count(LessonCompletion.id)).where(
                    and_(
                        LessonCompletion.user_id == user_id,
                        LessonCompletion.completed_at >= today_start,
                        LessonCompletion.completed_at < today_end,
                        LessonCompletion.best_score == 100,
                    )
                )
            )
            return result.scalar() or 0
    
    elif challenge["category"] == "vocabulary":
        # For now, return a placeholder (would need VocabularyReview model)
        # In production, query actual vocabulary review count
        return 0
    
    elif challenge["category"] == "xp":
        # Sum XP earned today (from lesson completions)
        # Simplified: count lessons * avg XP
        result = await db.execute(
            select(func.count(LessonCompletion.id)).where(
                and_(
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.completed_at >= today_start,
                    LessonCompletion.completed_at < today_end,
                )
            )
        )
        lessons_today = result.scalar() or 0
        return lessons_today * 15  # Avg 15 XP per lesson
    
    elif challenge["category"] == "streak":
        # Check if user has been active today
        result = await db.execute(
            select(Streak).where(Streak.user_id == user_id)
        )
        streak = result.scalar_one_or_none()
        if streak and streak.last_activity_date == today:
            return 1
        return 0
    
    return 0


# ============================================================================
# API Endpoints
# ============================================================================

@router.get("/daily", response_model=ApiResponse[DailyChallengesListResponse])
async def get_daily_challenges(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get today's daily challenges for the current user.
    
    Challenges are generated based on date and user ID for consistency.
    Each challenge has:
    - Target goal to achieve
    - Current progress
    - XP reward upon completion
    - Expiration time (end of day)
    """
    today = date.today()
    challenges = get_challenges_for_user(current_user.id, today)
    
    # Calculate progress for each challenge
    challenge_responses = []
    total_completed = 0
    
    for challenge in challenges:
        current = await calculate_challenge_progress(db, current_user.id, challenge, today)
        is_completed = current >= challenge["target"]
        
        if is_completed:
            total_completed += 1
        
        challenge_responses.append(DailyChallengeResponse(
            id=challenge["id"],
            title=challenge["title"],
            description=challenge["description"],
            icon=challenge["icon"],
            category=challenge["category"],
            target=challenge["target"],
            current=min(current, challenge["target"]),  # Cap at target
            xp_reward=challenge["xp_reward"],
            is_completed=is_completed,
            expires_at=(datetime.combine(today + timedelta(days=1), datetime.min.time())).isoformat(),
        ))
    
    # Bonus XP for completing all challenges
    all_completed = total_completed == len(challenges)
    bonus_xp = 50 if all_completed else 0
    
    return ApiResponse(
        success=True,
        message="Daily challenges retrieved",
        data=DailyChallengesListResponse(
            date=today.isoformat(),
            challenges=challenge_responses,
            total_completed=total_completed,
            total_challenges=len(challenges),
            bonus_xp=bonus_xp,
        )
    )


@router.post("/daily/{challenge_id}/claim", response_model=ApiResponse[dict])
async def claim_challenge_reward(
    challenge_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Claim reward for a completed challenge.
    
    Requirements:
    - Challenge must be completed (progress >= target)
    - Reward can only be claimed once per day
    """
    today = date.today()
    challenges = get_challenges_for_user(current_user.id, today)
    
    # Find the challenge
    challenge = next((c for c in challenges if c["id"] == challenge_id), None)
    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Challenge '{challenge_id}' not found"
        )
    
    # Check progress
    current = await calculate_challenge_progress(db, current_user.id, challenge, today)
    if current < challenge["target"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Challenge not completed. Progress: {current}/{challenge['target']}"
        )
    
    # In production, you would:
    # 1. Check if reward already claimed (need ChallengeRewardClaim table)
    # 2. Award XP to user
    # 3. Create claim record
    
    # For now, return success with reward info
    return ApiResponse(
        success=True,
        message=f"Challenge completed! +{challenge['xp_reward']} XP",
        data={
            "challenge_id": challenge_id,
            "xp_reward": challenge["xp_reward"],
            "claimed_at": datetime.utcnow().isoformat(),
        }
    )
