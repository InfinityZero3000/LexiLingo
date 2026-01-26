"""
User routes

Endpoints for user data and learning patterns
"""

from fastapi import APIRouter, Depends, HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase

from api.core.database import get_database
from api.models.schemas import UserLearningPattern, UserStats

router = APIRouter()


@router.get(
    "/{user_id}/learning-pattern",
    response_model=UserLearningPattern,
    summary="Get user learning pattern"
)
async def get_learning_pattern(
    user_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get latest learning pattern analysis for user.
    
    Used by Flutter app to show personalized recommendations.
    """
    try:
        pattern = await db["learning_patterns"].find_one(
            {"user_id": user_id},
            sort=[("analyzed_at", -1)]
        )
        
        if not pattern:
            raise HTTPException(
                status_code=404,
                detail="No learning pattern found for user"
            )
        
        # Convert ObjectId to string
        pattern["_id"] = str(pattern["_id"])
        
        return UserLearningPattern(**pattern)
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get learning pattern: {str(e)}"
        )


@router.get(
    "/{user_id}/stats",
    response_model=UserStats,
    summary="Get user statistics"
)
async def get_user_stats(
    user_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get user statistics from latest learning pattern.
    
    Used for dashboard and progress tracking in Flutter app.
    """
    try:
        pattern = await db["learning_patterns"].find_one(
            {"user_id": user_id},
            sort=[("analyzed_at", -1)]
        )
        
        if not pattern or "stats" not in pattern:
            # Return default stats if none found
            return UserStats(
                total_interactions=0,
                avg_fluency_score=0.0,
                common_errors=[],
                improvement_rate={},
                study_streak_days=0
            )
        
        return UserStats(**pattern["stats"])
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get user stats: {str(e)}"
        )
