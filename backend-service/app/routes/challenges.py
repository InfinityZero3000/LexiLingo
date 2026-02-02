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
from app.models.gamification import ChallengeRewardClaim
from app.schemas.response import ApiResponse
from app.crud.gamification import WalletCRUD


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
    gems_reward: int = 0  # Optional gems reward
    is_completed: bool
    is_claimed: bool = False  # Whether reward has been claimed
    expires_at: str


class DailyChallengesListResponse(BaseModel):
    date: str
    challenges: List[DailyChallengeResponse]
    total_completed: int
    total_challenges: int
    total_claimed: int
    bonus_xp: int  # Bonus for completing all challenges
    bonus_claimed: bool = False


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
    
    # Get claimed challenges for today
    today_start = datetime.combine(today, datetime.min.time())
    claims_result = await db.execute(
        select(ChallengeRewardClaim.challenge_id).where(
            and_(
                ChallengeRewardClaim.user_id == current_user.id,
                ChallengeRewardClaim.claim_date >= today_start
            )
        )
    )
    claimed_ids = set(c for c in claims_result.scalars().all())
    
    # Calculate progress for each challenge
    challenge_responses = []
    total_completed = 0
    total_claimed = 0
    
    for challenge in challenges:
        current = await calculate_challenge_progress(db, current_user.id, challenge, today)
        is_completed = current >= challenge["target"]
        is_claimed = challenge["id"] in claimed_ids
        
        if is_completed:
            total_completed += 1
        if is_claimed:
            total_claimed += 1
        
        challenge_responses.append(DailyChallengeResponse(
            id=challenge["id"],
            title=challenge["title"],
            description=challenge["description"],
            icon=challenge["icon"],
            category=challenge["category"],
            target=challenge["target"],
            current=min(current, challenge["target"]),  # Cap at target
            xp_reward=challenge["xp_reward"],
            gems_reward=challenge.get("gems_reward", 0),
            is_completed=is_completed,
            is_claimed=is_claimed,
            expires_at=(datetime.combine(today + timedelta(days=1), datetime.min.time())).isoformat(),
        ))
    
    # Bonus XP for completing all challenges
    all_completed = total_completed == len(challenges)
    bonus_xp = 50 if all_completed else 0
    bonus_claimed = "daily_bonus" in claimed_ids
    
    return ApiResponse(
        success=True,
        message="Daily challenges retrieved",
        data=DailyChallengesListResponse(
            date=today.isoformat(),
            challenges=challenge_responses,
            total_completed=total_completed,
            total_challenges=len(challenges),
            total_claimed=total_claimed,
            bonus_xp=bonus_xp,
            bonus_claimed=bonus_claimed,
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
    
    Rewards XP and gems (if any) to the user.
    """
    from app.services.item_effects_service import ItemEffectsService
    
    today = date.today()
    today_start = datetime.combine(today, datetime.min.time())
    challenges = get_challenges_for_user(current_user.id, today)
    
    # Find the challenge
    challenge = next((c for c in challenges if c["id"] == challenge_id), None)
    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Challenge '{challenge_id}' not found"
        )
    
    # Check if already claimed
    existing_claim = await db.execute(
        select(ChallengeRewardClaim).where(
            and_(
                ChallengeRewardClaim.user_id == current_user.id,
                ChallengeRewardClaim.challenge_id == challenge_id,
                ChallengeRewardClaim.claim_date >= today_start
            )
        )
    )
    if existing_claim.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Reward already claimed today"
        )
    
    # Check progress
    current = await calculate_challenge_progress(db, current_user.id, challenge, today)
    if current < challenge["target"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Challenge not completed. Progress: {current}/{challenge['target']}"
        )
    
    xp_reward = challenge["xp_reward"]
    gems_reward = challenge.get("gems_reward", 0)
    
    # Apply XP boost if active
    effects_service = ItemEffectsService(db)
    multiplier = await effects_service.get_xp_multiplier(current_user.id)
    boosted_xp = int(xp_reward * multiplier)
    
    # Award XP
    current_user.total_xp = (current_user.total_xp or 0) + boosted_xp
    
    # Award gems if any
    if gems_reward > 0:
        await WalletCRUD.add_gems(
            db,
            current_user.id,
            gems_reward,
            source="daily_challenge",
            description=f"Challenge completed: {challenge['title']}"
        )
    
    # Create claim record
    claim = ChallengeRewardClaim(
        user_id=current_user.id,
        challenge_id=challenge_id,
        claim_date=today_start,
        xp_reward=boosted_xp,
        gems_reward=gems_reward,
    )
    db.add(claim)
    await db.commit()
    
    message = f"Challenge completed! +{boosted_xp} XP"
    if multiplier > 1.0:
        message = f"Challenge completed! +{boosted_xp} XP ({xp_reward} × {multiplier}x boost)"
    if gems_reward > 0:
        message += f" +{gems_reward} gems"
    
    return ApiResponse(
        success=True,
        message=message,
        data={
            "challenge_id": challenge_id,
            "xp_reward": boosted_xp,
            "xp_base": xp_reward,
            "xp_multiplier": multiplier,
            "gems_reward": gems_reward,
            "claimed_at": datetime.utcnow().isoformat(),
        }
    )


@router.post("/daily/bonus/claim", response_model=ApiResponse[dict])
async def claim_daily_bonus(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Claim bonus reward for completing all daily challenges.
    
    Requirements:
    - All challenges must be completed
    - Bonus can only be claimed once per day
    """
    from app.services.item_effects_service import ItemEffectsService
    
    today = date.today()
    today_start = datetime.combine(today, datetime.min.time())
    challenges = get_challenges_for_user(current_user.id, today)
    
    # Check if bonus already claimed
    existing_claim = await db.execute(
        select(ChallengeRewardClaim).where(
            and_(
                ChallengeRewardClaim.user_id == current_user.id,
                ChallengeRewardClaim.challenge_id == "daily_bonus",
                ChallengeRewardClaim.claim_date >= today_start
            )
        )
    )
    if existing_claim.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Bonus already claimed today"
        )
    
    # Check all challenges completed
    total_completed = 0
    for challenge in challenges:
        current = await calculate_challenge_progress(db, current_user.id, challenge, today)
        if current >= challenge["target"]:
            total_completed += 1
    
    if total_completed < len(challenges):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Complete all challenges first. Progress: {total_completed}/{len(challenges)}"
        )
    
    bonus_xp = 50
    bonus_gems = 10
    
    # Apply XP boost
    effects_service = ItemEffectsService(db)
    multiplier = await effects_service.get_xp_multiplier(current_user.id)
    boosted_xp = int(bonus_xp * multiplier)
    
    # Award XP
    current_user.total_xp = (current_user.total_xp or 0) + boosted_xp
    
    # Award gems
    await WalletCRUD.add_gems(
        db,
        current_user.id,
        bonus_gems,
        source="daily_bonus",
        description="All daily challenges completed!"
    )
    
    # Create claim record
    claim = ChallengeRewardClaim(
        user_id=current_user.id,
        challenge_id="daily_bonus",
        claim_date=today_start,
        xp_reward=boosted_xp,
        gems_reward=bonus_gems,
    )
    db.add(claim)
    await db.commit()
    
    return ApiResponse(
        success=True,
        message=f"Daily bonus claimed! +{boosted_xp} XP +{bonus_gems} gems",
        data={
            "xp_reward": boosted_xp,
            "gems_reward": bonus_gems,
            "claimed_at": datetime.utcnow().isoformat(),
        }
    )
