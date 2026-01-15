"""
AI interaction routes

Endpoints for logging AI interactions and analytics
"""

from fastapi import APIRouter, Depends, HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
from typing import List, Dict, Any

from api.core.database import get_database
from api.models.schemas import (
    LogInteractionRequest,
    LogInteractionResponse,
    UserLearningPattern,
    ErrorResponse
)
from api.models.ai_repository import AIRepository

router = APIRouter()


@router.post(
    "/interactions",
    response_model=LogInteractionResponse,
    summary="Log AI interaction"
)
async def log_interaction(
    request: LogInteractionRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Log an AI interaction to database.
    
    Called by Flutter app after each AI analysis.
    """
    try:
        repo = AIRepository(db)
        interaction_id = await repo.log_interaction(request)
        
        return LogInteractionResponse(
            interaction_id=interaction_id,
            message="Interaction logged successfully"
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to log interaction: {str(e)}"
        )


@router.get(
    "/interactions/user/{user_id}",
    response_model=List[Dict[str, Any]],
    summary="Get user interactions"
)
async def get_user_interactions(
    user_id: str,
    limit: int = 100,
    skip: int = 0,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get user's interaction history.
    
    Useful for Flutter app to show user progress.
    """
    try:
        repo = AIRepository(db)
        interactions = await repo.get_user_interactions(user_id, limit, skip)
        
        return interactions
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get interactions: {str(e)}"
        )


@router.get(
    "/interactions/session/{session_id}",
    response_model=List[Dict[str, Any]],
    summary="Get session interactions"
)
async def get_session_interactions(
    session_id: str,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get all interactions in a chat session."""
    try:
        repo = AIRepository(db)
        interactions = await repo.get_session_interactions(session_id)
        
        return interactions
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get session interactions: {str(e)}"
        )


@router.post(
    "/interactions/{interaction_id}/feedback",
    summary="Update interaction feedback"
)
async def update_feedback(
    interaction_id: str,
    feedback: Dict[str, Any],
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Update interaction with user feedback.
    
    Called when user rates AI response or provides corrections.
    """
    try:
        repo = AIRepository(db)
        success = await repo.update_feedback(interaction_id, feedback)
        
        if not success:
            raise HTTPException(
                status_code=404,
                detail="Interaction not found"
            )
        
        return {"message": "Feedback updated successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to update feedback: {str(e)}"
        )


@router.get(
    "/analytics/user/{user_id}/errors",
    response_model=List[Dict[str, Any]],
    summary="Get user error statistics"
)
async def get_user_error_stats(
    user_id: str,
    days: int = 30,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get aggregated error statistics for user.
    
    Useful for showing learning progress in Flutter app.
    """
    try:
        repo = AIRepository(db)
        stats = await repo.get_user_error_stats(user_id, days)
        
        return stats
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get error stats: {str(e)}"
        )
