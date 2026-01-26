"""
Training & Learning endpoints

Endpoints for AI training data management and user learning patterns
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from motor.motor_asyncio import AsyncIOMotorDatabase
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta

from api.core.database import get_database
from api.models.schemas import (
    SubmitFeedbackRequest,
    SubmitFeedbackResponse,
    AddToTrainingQueueRequest,
    AddToTrainingQueueResponse,
    UserProgressSnapshot,
    ErrorPattern,
    AnalyticsQuery,
    AnalyticsResponse,
    ExportDataRequest,
    ExportDataResponse,
    ErrorResponse
)
from api.models.ai_repository import AIRepository

router = APIRouter()


# ============================================================
# Feedback Collection
# ============================================================

@router.post(
    "/feedback",
    response_model=SubmitFeedbackResponse,
    summary="Submit user feedback",
    description="Submit feedback on AI response quality. Critical for training data curation."
)
async def submit_feedback(
    request: SubmitFeedbackRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Submit user feedback on AI response.
    
    This is CRITICAL for:
    - Training data quality assessment
    - Model improvement
    - Identifying systematic errors
    """
    try:
        repo = AIRepository(db)
        feedback_id = await repo.submit_feedback(
            interaction_id=request.interaction_id,
            user_id=request.user_id,
            rating=request.rating,
            helpful=request.helpful,
            accurate=request.accurate,
            feedback_text=request.feedback_text,
            reported_issues=request.reported_issues
        )
        
        return SubmitFeedbackResponse(
            success=True,
            message="Feedback submitted successfully. Thank you for helping improve our AI!"
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to submit feedback: {str(e)}"
        )


@router.get(
    "/feedback/stats",
    response_model=Dict[str, Any],
    summary="Get feedback statistics"
)
async def get_feedback_stats(
    user_id: Optional[str] = None,
    days: int = Query(default=30, ge=1, le=365),
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get aggregated feedback statistics."""
    try:
        repo = AIRepository(db)
        
        query = {}
        if user_id:
            query["user_id"] = user_id
        
        cutoff_date = datetime.utcnow() - timedelta(days=days)
        query["timestamp"] = {"$gte": cutoff_date}
        
        # Aggregate feedback stats
        pipeline = [
            {"$match": query},
            {
                "$group": {
                    "_id": None,
                    "avg_rating": {"$avg": "$rating"},
                    "total_feedbacks": {"$sum": 1},
                    "helpful_count": {
                        "$sum": {"$cond": [{"$eq": ["$helpful", True]}, 1, 0]}
                    },
                    "accurate_count": {
                        "$sum": {"$cond": [{"$eq": ["$accurate", True]}, 1, 0]}
                    }
                }
            }
        ]
        
        results = await repo.feedback.aggregate(pipeline).to_list(None)
        
        if not results:
            return {
                "avg_rating": 0.0,
                "total_feedbacks": 0,
                "helpful_percentage": 0.0,
                "accurate_percentage": 0.0
            }
        
        stats = results[0]
        return {
            "avg_rating": round(stats["avg_rating"], 2),
            "total_feedbacks": stats["total_feedbacks"],
            "helpful_percentage": round(stats["helpful_count"] / stats["total_feedbacks"] * 100, 1),
            "accurate_percentage": round(stats["accurate_count"] / stats["total_feedbacks"] * 100, 1)
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get feedback stats: {str(e)}"
        )


# ============================================================
# Training Queue Management
# ============================================================

@router.post(
    "/training-queue",
    response_model=AddToTrainingQueueResponse,
    summary="Add interaction to training queue"
)
async def add_to_training_queue(
    request: AddToTrainingQueueRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Add interaction to training queue for LoRA fine-tuning.
    
    Used to curate high-quality training examples.
    """
    try:
        repo = AIRepository(db)
        example_id = await repo.add_to_training_queue(
            interaction_id=request.interaction_id,
            task_types=request.task_types,
            quality_score=request.quality_score,
            notes=request.notes
        )
        
        return AddToTrainingQueueResponse(
            example_id=example_id,
            message="Successfully added to training queue"
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to add to training queue: {str(e)}"
        )


@router.get(
    "/training-queue",
    response_model=List[Dict[str, Any]],
    summary="Get training queue"
)
async def get_training_queue(
    task_type: Optional[str] = None,
    validated_only: bool = False,
    min_quality_score: float = Query(default=0.7, ge=0.0, le=1.0),
    limit: int = Query(default=100, ge=1, le=1000),
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get training examples from queue.
    
    Used by ML engineers to fetch training data.
    """
    try:
        repo = AIRepository(db)
        examples = await repo.get_training_queue(
            task_type=task_type,
            validated_only=validated_only,
            min_quality_score=min_quality_score,
            limit=limit
        )
        
        return examples
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get training queue: {str(e)}"
        )


@router.put(
    "/training-queue/{example_id}/validate",
    response_model=Dict[str, Any],
    summary="Validate training example"
)
async def validate_training_example(
    example_id: str,
    approved: bool,
    validated_by: str,
    notes: Optional[str] = None,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Validate training example (human-in-the-loop).
    
    ML engineers approve/reject examples before training.
    """
    try:
        repo = AIRepository(db)
        success = await repo.validate_training_example(
            example_id=example_id,
            validated_by=validated_by,
            approved=approved,
            notes=notes
        )
        
        if success:
            return {
                "success": True,
                "message": "Training example validated"
            }
        else:
            raise HTTPException(
                status_code=404,
                detail="Training example not found"
            )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to validate training example: {str(e)}"
        )


# ============================================================
# User Progress Tracking
# ============================================================

@router.post(
    "/progress/snapshot",
    response_model=Dict[str, Any],
    summary="Save user progress snapshot"
)
async def save_progress_snapshot(
    snapshot: UserProgressSnapshot,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Save user progress snapshot.
    
    Called periodically to track learning improvement.
    """
    try:
        repo = AIRepository(db)
        snapshot_id = await repo.save_progress_snapshot(
            user_id=snapshot.user_id,
            level=snapshot.level,
            fluency_score_avg=snapshot.fluency_score_avg,
            grammar_accuracy=snapshot.grammar_accuracy,
            vocabulary_count=snapshot.vocabulary_count,
            pronunciation_score_avg=snapshot.pronunciation_score_avg,
            total_interactions=snapshot.total_interactions,
            study_streak_days=snapshot.study_streak_days,
            common_errors=snapshot.common_errors
        )
        
        return {
            "snapshot_id": snapshot_id,
            "message": "Progress snapshot saved"
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to save progress snapshot: {str(e)}"
        )


@router.get(
    "/progress/history/{user_id}",
    response_model=List[Dict[str, Any]],
    summary="Get user progress history"
)
async def get_progress_history(
    user_id: str,
    days: int = Query(default=30, ge=1, le=365),
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get user progress history for visualization."""
    try:
        repo = AIRepository(db)
        history = await repo.get_user_progress_history(user_id, days)
        return history
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get progress history: {str(e)}"
        )


# ============================================================
# Error Pattern Analysis
# ============================================================

@router.get(
    "/error-patterns",
    response_model=List[Dict[str, Any]],
    summary="Get detected error patterns"
)
async def get_error_patterns(
    min_frequency: int = Query(default=5, ge=1),
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get detected error patterns across all users.
    
    Helps identify systematic issues for model improvement.
    """
    try:
        repo = AIRepository(db)
        patterns = await repo.detect_error_patterns(min_frequency=min_frequency)
        return patterns
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get error patterns: {str(e)}"
        )


@router.get(
    "/error-patterns/user/{user_id}",
    response_model=List[Dict[str, Any]],
    summary="Get user-specific error patterns"
)
async def get_user_error_patterns(
    user_id: str,
    days: int = Query(default=30, ge=1, le=365),
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get error patterns for specific user."""
    try:
        repo = AIRepository(db)
        patterns = await repo.get_user_error_stats(user_id, days)
        return patterns
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get user error patterns: {str(e)}"
        )


# ============================================================
# Analytics & Metrics
# ============================================================

@router.post(
    "/analytics",
    response_model=AnalyticsResponse,
    summary="Get analytics data"
)
async def get_analytics(
    query: AnalyticsQuery,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get analytics data for dashboards.
    
    Supports various metrics: fluency, grammar, vocabulary, engagement.
    """
    try:
        repo = AIRepository(db)
        result = await repo.get_analytics(
            user_id=query.user_id,
            start_date=query.start_date,
            end_date=query.end_date,
            metric=query.metric
        )
        
        return AnalyticsResponse(
            metric=result["metric"],
            data=result["data"],
            summary=result["summary"]
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get analytics: {str(e)}"
        )


# ============================================================
# Data Export for Training
# ============================================================

@router.post(
    "/export/training-data",
    response_model=Dict[str, Any],
    summary="Export training data"
)
async def export_training_data(
    request: ExportDataRequest,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Export training data for LoRA fine-tuning.
    
    Returns data in JSONL format suitable for training.
    """
    try:
        repo = AIRepository(db)
        
        # Get training examples
        examples = await repo.get_training_queue(
            task_type=request.task_types[0] if request.task_types else None,
            validated_only=request.validated_only,
            min_quality_score=request.min_quality_score,
            limit=10000  # Max export
        )
        
        # Format for training
        training_data = []
        for example in examples:
            training_data.append({
                "input": example["user_input"],
                "output": example["expected_output"],
                "task_types": example["task_types"],
                "difficulty_level": example["difficulty_level"],
                "quality_score": example["quality_score"]
            })
        
        # In production, save to file and return URL
        # For now, return inline
        return {
            "export_id": "temp_export",
            "data": training_data,
            "record_count": len(training_data),
            "format": request.format,
            "message": f"Exported {len(training_data)} training examples"
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to export training data: {str(e)}"
        )


# ============================================================
# Model Metrics Tracking
# ============================================================

@router.post(
    "/metrics/model-performance",
    response_model=Dict[str, Any],
    summary="Log model performance metrics"
)
async def log_model_performance(
    model_name: str,
    version: str,
    metrics: Dict[str, float],
    metadata: Optional[Dict[str, Any]] = None,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Log model performance metrics after training/evaluation.
    
    Used to track model improvement over time.
    """
    try:
        repo = AIRepository(db)
        
        metric_doc = {
            "model_name": model_name,
            "version": version,
            "metrics": metrics,
            "metadata": metadata or {},
            "timestamp": datetime.utcnow()
        }
        
        result = await repo.model_metrics.insert_one(metric_doc)
        
        return {
            "metric_id": str(result.inserted_id),
            "message": "Model metrics logged successfully"
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to log model metrics: {str(e)}"
        )


@router.get(
    "/metrics/model-performance/{model_name}",
    response_model=List[Dict[str, Any]],
    summary="Get model performance history"
)
async def get_model_performance_history(
    model_name: str,
    limit: int = Query(default=50, ge=1, le=100),
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """Get model performance history for tracking improvement."""
    try:
        repo = AIRepository(db)
        
        cursor = repo.model_metrics.find({
            "model_name": model_name
        }).sort("timestamp", -1).limit(limit)
        
        metrics = await cursor.to_list(length=limit)
        
        for metric in metrics:
            metric["_id"] = str(metric["_id"])
        
        return metrics
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get model performance history: {str(e)}"
        )
