"""
AI interaction routes

Endpoints for logging AI interactions and analytics
"""

import logging
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from bson import ObjectId
from datetime import datetime, timezone
from motor.motor_asyncio import AsyncIOMotorDatabase
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field

from api.core.database import get_database
from api.core.auth import AuthenticatedUser, enforce_user_scope, get_current_user
from api.core.quota_guard import default_token_cost_for_endpoint, enforce_user_quota
from api.models.schemas import (
    LogInteractionRequest,
    LogInteractionResponse
)
from api.models.schemas import MAX_CHAT_MESSAGE_CHARS
from api.models.ai_repository import AIRepository
from api.services.trace_cag import get_trace_cag
from api.routes.admin import verify_admin_api_key
from api.core.groq_key_pool import get_configured_key_count, get_groq_key_pool
from api.services.ai_monitoring import chat_report, llm_key_report, spool_report

logger = logging.getLogger(__name__)
router = APIRouter()


# ============================================================
# REQUEST/RESPONSE SCHEMAS
# ============================================================

class AnalyzeRequest(BaseModel):
    """Request for AI analysis via Orchestrator."""
    text: str = Field(..., max_length=MAX_CHAT_MESSAGE_CHARS, description="User input text to analyze")
    user_id: Optional[str] = Field(None, description="User ID for tracking")
    session_id: str = Field(..., description="Conversation session ID")
    input_type: str = Field("text", description="Input type: 'text' or 'voice'")
    learner_profile: Optional[Dict[str, Any]] = Field(None, description="User's learning profile")


# ============================================================
# TRACECAG ENDPOINTS (LangGraph-based)
# ============================================================

@router.post(
    "/trace-cag/analyze",
    summary="Analyze input with TraceCAG Pipeline",
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
async def analyze_with_trace_cag(
    request: AnalyzeRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Main endpoint for TraceCAG-powered text analysis.
    """
    user_id = enforce_user_scope(current_user, request.user_id)
    request = request.model_copy(update={"user_id": user_id})
    await enforce_user_quota(
        current_user.user_id,
        "ai.analyze",
        token_cost=default_token_cost_for_endpoint("ai.analyze", text=request.text),
        fail_closed=True,
    )
    try:
        pipeline = await get_trace_cag()
        return await pipeline.analyze(
            user_input=request.text,
            session_id=request.session_id,
            user_id=request.user_id,
            input_type=request.input_type,
            learner_profile=request.learner_profile,
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"TraceCAG analysis failed: {str(e)}"
        )


@router.get(
    "/trace-cag/health",
    summary="Health check for TraceCAG",
    description="Check if TraceCAG pipeline is healthy and ready"
)
async def trace_cag_health():
    """Health check endpoint for TraceCAG."""
    try:
        await get_trace_cag()  # raises if the pipeline cannot initialize

        return {
            "status": "healthy",
            "pipeline": "TraceCAG",
            "nodes": [
                "input_node", "kg_expand_node", "diagnose_node",
                "retrieve_node", "generate_node", "tts_node"
            ],
            "backend": "LangGraph StateGraph",
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"TraceCAG unhealthy: {str(e)}"
        )


@router.post(
    "/warmup",
    summary="Trigger AI model warmup",
    description="Warm up chat/STT/TTS models in the background.",
)
@router.get(
    "/warmup",
    summary="Trigger AI model warmup",
    description="Warm up chat/STT/TTS models in the background.",
)
async def warmup_models(background_tasks: BackgroundTasks):
    """Gateway-compatible warmup endpoint under /api/v1/ai/warmup."""

    async def _do_warmup() -> None:
        try:
            from api.services.model_gateway import get_model_gateway

            gateway = get_model_gateway()
            await gateway.preload_models()
        except Exception:
            # Warmup failures are non-fatal and should not break user requests.
            return

    background_tasks.add_task(_do_warmup)
    return {"status": "warming_up", "message": "Model preload started in background"}


# ============================================================
# MONITORING & TELEMETRY ENDPOINTS (NEW)
# ===========================================================

async def _redis_or_none() -> Any:
    try:
        from api.core.redis_client import RedisClient

        return await RedisClient.get_instance()
    except Exception:
        return None


@router.get(
    "/monitoring/chat",
    summary="Lexi chat turn metrics over a time window",
)
async def get_chat_monitoring(
    _key: str = Depends(verify_admin_api_key),
    window: Literal["1h", "24h", "7d"] = Query("24h"),
    db: AsyncIOMotorDatabase = Depends(get_database),
) -> Dict[str, Any]:
    try:
        return await chat_report(db, await _redis_or_none(), window)
    except Exception as exc:
        logger.error("chat monitoring failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="Turn metrics are unavailable")


@router.get(
    "/monitoring/observation-spool",
    summary="Learner observation queue state",
)
async def get_observation_spool_monitoring(
    _key: str = Depends(verify_admin_api_key),
    db: AsyncIOMotorDatabase = Depends(get_database),
) -> Dict[str, Any]:
    from api.services.telemetry import get_telemetry

    try:
        return await spool_report(db, dict(get_telemetry().counters))
    except Exception as exc:
        logger.error("observation spool monitoring failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="Queue state is unavailable")


@router.get(
    "/monitoring/llm-keys",
    summary="Groq key pool state by key index",
)
async def get_llm_key_monitoring(
    _key: str = Depends(verify_admin_api_key),
) -> Dict[str, Any]:
    try:
        configured = get_configured_key_count()
    except ValueError:
        configured = 0
    try:
        return await llm_key_report(get_groq_key_pool(), configured)
    except Exception as exc:
        logger.error("llm key monitoring failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="Key pool state is unavailable")


@router.get(
    "/monitoring/dashboard",
    summary="Performance monitoring dashboard",
    description="Comprehensive performance metrics and system statistics"
)
async def get_monitoring_dashboard(
    _key: str = Depends(verify_admin_api_key),
):
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
        await get_trace_cag()  # raises if the pipeline cannot initialize

        return {
            "telemetry": telemetry.get_dashboard_data(),
            "system": perf_monitor.get_system_stats(),
            "health": perf_monitor.check_resource_health(),
            "trace_cag": {"status": "active", "backend": "LangGraph"},
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
async def get_metric_stats(
    metric_name: str,
    _key: str = Depends(verify_admin_api_key),
):
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
async def get_system_stats(
    _key: str = Depends(verify_admin_api_key),
):
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
async def check_system_health(
    _key: str = Depends(verify_admin_api_key),
):
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
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Log an AI interaction to database.
    
    Called by Flutter app after each AI analysis.
    """
    try:
        auth_user_id = enforce_user_scope(current_user, request.user_id)
        request = request.model_copy(update={"user_id": auth_user_id})
        repo = AIRepository(db)
        interaction_id = await repo.log_interaction(request)
        
        return LogInteractionResponse(
            interaction_id=interaction_id,
            message="Interaction logged successfully"
        )

    except HTTPException:
        raise
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
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Get user's interaction history.
    
    Useful for Flutter app to show user progress.
    """
    try:
        enforce_user_scope(current_user, user_id)
        repo = AIRepository(db)
        interactions = await repo.get_user_interactions(user_id, limit, skip)
        
        return interactions

    except HTTPException:
        raise
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
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get all interactions in a chat session."""
    try:
        repo = AIRepository(db)
        cursor = repo.collection.find(
            {"session_id": session_id, "user_id": current_user.user_id}
        ).sort("created_at", 1)
        docs = await cursor.to_list(length=1000)
        interactions = [repo._normalize_doc(doc) for doc in docs]
        
        return interactions

    except HTTPException:
        raise
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
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Update interaction with user feedback.
    
    Called when user rates AI response or provides corrections.
    """
    try:
        repo = AIRepository(db)
        update_doc = {
            "$set": {
                "feedback": feedback,
                "feedback_updated_at": datetime.now(timezone.utc),
            }
        }
        result = await repo.collection.update_one(
            {"interaction_id": interaction_id, "user_id": current_user.user_id},
            update_doc,
        )
        success = result.matched_count > 0
        if not success and ObjectId.is_valid(interaction_id):
            result = await repo.collection.update_one(
                {"_id": ObjectId(interaction_id), "user_id": current_user.user_id},
                update_doc,
            )
            success = result.matched_count > 0
        
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
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Get aggregated error statistics for user.
    
    Useful for showing learning progress in Flutter app.
    """
    try:
        enforce_user_scope(current_user, user_id)
        repo = AIRepository(db)
        stats = await repo.get_user_error_stats(user_id, days)
        
        return stats

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get error stats: {str(e)}"
        )
