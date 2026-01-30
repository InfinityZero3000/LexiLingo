"""
AI interaction routes

Endpoints for logging AI interactions and analytics
"""

from fastapi import APIRouter, Depends, HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field

from api.core.database import get_database
from api.models.schemas import (
    LogInteractionRequest,
    LogInteractionResponse,
    UserLearningPattern,
    ErrorResponse
)
from api.models.v3_schemas import TutorResponseV3
from api.models.ai_repository import AIRepository
from api.services.graph_cag import get_graph_cag, GraphCAGPipeline
from api.services.v3_pipeline import get_v3_pipeline

router = APIRouter()


# ============================================================
# REQUEST/RESPONSE SCHEMAS
# ============================================================

class AnalyzeRequest(BaseModel):
    """Request for AI analysis via Orchestrator."""
    text: str = Field(..., description="User input text to analyze")
    user_id: Optional[str] = Field(None, description="User ID for tracking")
    session_id: str = Field(..., description="Conversation session ID")
    input_type: str = Field("text", description="Input type: 'text' or 'voice'")
    learner_profile: Optional[Dict[str, Any]] = Field(None, description="User's learning profile")


# ============================================================
# GRAPHCAG ENDPOINTS (LangGraph-based)
# ============================================================

@router.post(
    "/graph-cag/analyze",
    summary="Analyze input with GraphCAG Pipeline",
    description="""
    LangGraph-based AI analysis with Knowledge Graph integration.
    
    **Architecture:**
    - LangGraph StateGraph orchestration
    - KuzuDB Knowledge Graph for concept expansion
    - Conditional routing based on confidence
    - Streaming support
    
    **Pipeline Nodes:**
    INPUT → KG_EXPAND → DIAGNOSE → RETRIEVE → GENERATE → TTS
    
    **Performance:**
    - Target latency: <350ms
    - KG concept expansion: <5ms
    """
)
async def analyze_with_graph_cag(request: AnalyzeRequest):
    """
    Main endpoint for GraphCAG-powered text analysis.
    """
    try:
        pipeline = await get_graph_cag()
        return await pipeline.analyze(
            user_input=request.text,
            session_id=request.session_id,
            user_id=request.user_id,
            input_type=request.input_type,
            learner_profile=request.learner_profile,
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"GraphCAG analysis failed: {str(e)}"
        )


@router.post(
    "/analyze",
    response_model=TutorResponseV3,
    summary="Analyze input with V3 Knowledge-Centric Pipeline",
    description="Legacy V3 pipeline - use /graph-cag/analyze for new integrations."
)
async def analyze_with_v3(request: AnalyzeRequest):
    """
    Legacy V3 pipeline endpoint.
    """
    try:
        pipeline = await get_v3_pipeline()
        return await pipeline.analyze(
            text=request.text,
            session_id=request.session_id,
            user_id=request.user_id,
            learner_profile=request.learner_profile,
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Analysis failed: {str(e)}"
        )


@router.get(
    "/graph-cag/health",
    summary="Health check for GraphCAG",
    description="Check if GraphCAG pipeline is healthy and ready"
)
async def graph_cag_health():
    """Health check endpoint for GraphCAG."""
    try:
        pipeline = await get_graph_cag()
        
        return {
            "status": "healthy",
            "pipeline": "GraphCAG",
            "nodes": [
                "input_node", "kg_expand_node", "diagnose_node",
                "retrieve_node", "generate_node", "tts_node"
            ],
            "backend": "LangGraph StateGraph",
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"GraphCAG unhealthy: {str(e)}"
        )


# ============================================================
# MONITORING & TELEMETRY ENDPOINTS (NEW)
# ===========================================================

@router.get(
    "/monitoring/dashboard",
    summary="Performance monitoring dashboard",
    description="Comprehensive performance metrics and system statistics"
)
async def get_monitoring_dashboard():
    """
    Get comprehensive monitoring data for dashboard.
    
    Includes:
    - Telemetry metrics (latency, cache hits, errors)
    - System stats (CPU, memory, disk)
    - Resource health checks
    - Orchestrator statistics
    - Performance target status
    """
    try:
        from api.services.telemetry import get_telemetry
        from api.services.performance_monitor import get_performance_monitor
        
        telemetry = get_telemetry()
        perf_monitor = get_performance_monitor()
        graph_cag = await get_graph_cag()
        
        return {
            "telemetry": telemetry.get_dashboard_data(),
            "system": perf_monitor.get_system_stats(),
            "health": perf_monitor.check_resource_health(),
            "graph_cag": {"status": "active", "backend": "LangGraph"},
            "performance_checks": telemetry.check_performance_targets(),
            "process": perf_monitor.get_process_stats()
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get monitoring data: {str(e)}"
        )


@router.get(
    "/monitoring/metrics/{metric_name}",
    summary="Get specific metric statistics"
)
async def get_metric_stats(metric_name: str):
    """Get detailed statistics for a specific metric."""
    try:
        from api.services.telemetry import get_telemetry
        
        telemetry = get_telemetry()
        stats = telemetry.get_statistics(metric_name)
        
        if not stats:
            raise HTTPException(
                status_code=404,
                detail=f"Metric '{metric_name}' not found"
            )
        
        return {
            "metric_name": metric_name,
            "statistics": stats,
            "recent_values": [
                {"value": m.value, "timestamp": m.timestamp.isoformat()}
                for m in telemetry.get_recent_metrics(metric_name, minutes=5)
            ]
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get metric stats: {str(e)}"
        )


@router.get(
    "/monitoring/system",
    summary="System resource statistics"
)
async def get_system_stats():
    """Get current system resource usage."""
    try:
        from api.services.performance_monitor import get_performance_monitor
        
        monitor = get_performance_monitor()
        
        return monitor.get_system_stats()
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get system stats: {str(e)}"
        )


@router.get(
    "/monitoring/health",
    summary="System health check"
)
async def check_system_health():
    """Check system resource health with warnings."""
    try:
        from api.services.performance_monitor import get_performance_monitor
        
        monitor = get_performance_monitor()
        
        health = monitor.check_resource_health()
        
        # Return 503 if critical warnings exist
        if not health["healthy"] and health["critical_count"] > 0:
            raise HTTPException(
                status_code=503,
                detail="System has critical resource warnings"
            )
        
        return health
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to check health: {str(e)}"
        )


# ============================================================
# LEGACY ENDPOINTS (for logging interactions)
# ============================================================

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
