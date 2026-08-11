"""
Ollama Test Router
Testing endpoints for Ollama service
"""

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel
from typing import Optional
import logging

from api.routes.admin import verify_admin_api_key
from api.services.ollama_service import get_ollama_service
from api.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()


class ChatRequest(BaseModel):
    """Chat request model."""
    message: str
    system: Optional[str] = "You are a helpful English learning AI tutor."
    temperature: float = 0.7
    max_tokens: Optional[int] = None


class AnalyzeRequest(BaseModel):
    """Text analysis request."""
    text: str
    task: str = "grammar"  # grammar, fluency, vocabulary, dialogue
    language: str = "en"


async def _require_ollama_enabled_admin(admin_key: str | None) -> None:
    if not settings.USE_OLLAMA:
        raise HTTPException(
            status_code=503,
            detail="Ollama service is disabled. Set USE_OLLAMA=true"
        )
    await verify_admin_api_key(admin_key)


@router.get("/ollama/health")
async def ollama_health(
    admin_key: str | None = Header(default=None, alias="X-Admin-Key"),
):
    """
    Check Ollama service health.
    
    Returns:
        Service status and available models
    """
    await _require_ollama_enabled_admin(admin_key)
    
    try:
        ollama = get_ollama_service()
        is_healthy = await ollama.health_check()
        
        if not is_healthy:
            raise HTTPException(
                status_code=503,
                detail="Ollama server is not responding"
            )
        
        models = await ollama.list_models()
        
        return {
            "status": "healthy",
            "base_url": settings.OLLAMA_BASE_URL,
            "current_model": settings.OLLAMA_MODEL,
            "available_models": models,
            "model_loaded": settings.OLLAMA_MODEL in models
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Ollama health check failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/ollama/chat")
async def ollama_chat(
    request: ChatRequest,
    admin_key: str | None = Header(default=None, alias="X-Admin-Key"),
):
    """
    Chat with Ollama (Qwen model).
    
    Args:
        request: Chat request with message and parameters
        
    Returns:
        AI response
    """
    await _require_ollama_enabled_admin(admin_key)
    
    try:
        ollama = get_ollama_service()
        
        # Use generate endpoint for simple chat
        response = await ollama.generate(
            prompt=request.message,
            system=request.system,
            temperature=request.temperature,
            max_tokens=request.max_tokens,
        )
        
        return {
            "response": response,
            "model": settings.OLLAMA_MODEL,
            "message": request.message
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Ollama chat failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/ollama/analyze")
async def ollama_analyze(
    request: AnalyzeRequest,
    admin_key: str | None = Header(default=None, alias="X-Admin-Key"),
):
    """
    Analyze text using Ollama.
    
    Args:
        request: Text analysis request
        
    Returns:
        Analysis results (grammar, fluency, vocabulary, etc.)
    """
    await _require_ollama_enabled_admin(admin_key)
    
    try:
        ollama = get_ollama_service()
        
        result = await ollama.analyze_text(
            text=request.text,
            task=request.task,
            language=request.language,
        )
        
        return {
            "task": request.task,
            "text": request.text,
            "result": result,
            "model": settings.OLLAMA_MODEL
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Text analysis failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/ollama/models")
async def list_ollama_models(
    admin_key: str | None = Header(default=None, alias="X-Admin-Key"),
):
    """
    List all available Ollama models.
    
    Returns:
        List of model names
    """
    await _require_ollama_enabled_admin(admin_key)
    
    try:
        ollama = get_ollama_service()
        models = await ollama.list_models()
        
        return {
            "models": models,
            "current": settings.OLLAMA_MODEL,
            "count": len(models)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to list models: {e}")
        raise HTTPException(status_code=500, detail=str(e))
