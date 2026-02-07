"""
Admin configuration routes for AI Service

Endpoints for super admin to configure AI service settings including Gemini API key.
"""

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging
import os

from api.core.database import get_database

logger = logging.getLogger(__name__)
router = APIRouter()


class AiConfig(BaseModel):
    """AI Service configuration model."""
    model_name: str = "gemini-1.5-flash"
    temperature: float = 0.7
    max_tokens: int = 2048
    gemini_api_key: Optional[str] = None


def mask_api_key(api_key: Optional[str]) -> Optional[str]:
    """
    Mask API key for secure display.
    Shows first 4 and last 3 characters, e.g., 'AIza***...***xyz'
    
    Args:
        api_key: The API key to mask
        
    Returns:
        Masked API key or None if input is None/empty
    """
    if not api_key or not isinstance(api_key, str) or len(api_key) < 8:
        return None
    
    return f"{api_key[:4]}***...***{api_key[-3:]}"


async def get_stored_api_key(db: AsyncIOMotorDatabase) -> Optional[str]:
    """
    Get stored Gemini API key from database.
    
    Args:
        db: MongoDB database instance
        
    Returns:
        API key string or None if not found
    """
    config = await db.admin_config.find_one({"_id": "ai_config"})
    if config and config.get("gemini_api_key"):
        return config["gemini_api_key"]
    return None


def get_active_api_key(stored_key: Optional[str]) -> Optional[str]:
    """
    Get active API key following this priority:
    1. Stored key from database (if exists)
    2. Environment variable GEMINI_API_KEY
    
    Args:
        stored_key: API key from database
        
    Returns:
        Active API key or None
    """
    if stored_key:
        return stored_key
    return os.getenv("GEMINI_API_KEY")


@router.get("/config", response_model=AiConfig)
async def get_admin_config(db: AsyncIOMotorDatabase = Depends(get_database)):
    """
    Get current AI service configuration.
    
    Returns configuration with masked API key for security.
    If no API key is stored in database, indicates using environment variable.
    """
    try:
        # Try to get config from database
        config = await db.admin_config.find_one({"_id": "ai_config"})
        
        if not config:
            # Return default config with environment variable indication
            env_key = os.getenv("GEMINI_API_KEY")
            return AiConfig(
                model_name="gemini-1.5-flash",
                temperature=0.7,
                max_tokens=2048,
                gemini_api_key=mask_api_key(env_key) if env_key else None
            )
        
        # Return stored config with masked API key
        stored_key = config.get("gemini_api_key")
        if not stored_key:
            # If stored config exists but no key, check env var
            env_key = os.getenv("GEMINI_API_KEY")
            stored_key = env_key
        
        return AiConfig(
            model_name=config.get("model_name", "gemini-1.5-flash"),
            temperature=config.get("temperature", 0.7),
            max_tokens=config.get("max_tokens", 2048),
            gemini_api_key=mask_api_key(stored_key)
        )
    except Exception as e:
        logger.error(f"Error fetching admin config: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch configuration")


@router.put("/config")
async def update_admin_config(
    config: AiConfig,
    db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Update AI service configuration.
    
    Super admin only. Stores configuration in database.
    If gemini_api_key is empty or None, system will fallback to environment variable.
    """
    try:
        # Validate API key format if provided
        if config.gemini_api_key:
            if not config.gemini_api_key.startswith("AIza"):
                raise HTTPException(
                    status_code=400,
                    detail="Invalid API key format. Gemini API keys start with 'AIza'"
                )
        
        # Prepare config document
        config_doc = {
            "_id": "ai_config",
            "model_name": config.model_name,
            "temperature": config.temperature,
            "max_tokens": config.max_tokens,
            "gemini_api_key": config.gemini_api_key,  # Can be None
        }
        
        # Upsert (update or insert) configuration
        await db.admin_config.update_one(
            {"_id": "ai_config"},
            {
                "$set": config_doc,
                "$currentDate": {"updated_at": True}
            },
            upsert=True
        )
        
        logger.info(f"Admin config updated: model={config.model_name}, has_api_key={bool(config.gemini_api_key)}")
        
        return {
            "success": True,
            "message": "Configuration updated successfully",
            "config": {
                "model_name": config.model_name,
                "temperature": config.temperature,
                "max_tokens": config.max_tokens,
                "gemini_api_key": mask_api_key(config.gemini_api_key) if config.gemini_api_key else None
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating admin config: {e}")
        raise HTTPException(status_code=500, detail="Failed to update configuration")
