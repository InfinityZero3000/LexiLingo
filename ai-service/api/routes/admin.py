"""
Admin configuration routes for AI Service

Endpoints for super admin to configure AI service settings including Gemini API key.
"""

from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import APIKeyHeader
from pydantic import BaseModel
from typing import Optional
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging
import os
import hmac
import re
from datetime import datetime, timezone

from api.core.database import get_database
from api.core.redis_client import get_redis
from api.models.story_schemas import (
    AdminStoryCreateRequest,
    ContextDescription,
    ConversationFlow,
    LocalizedTitle,
    RolePersona,
    Story,
    StoryListItem,
)

logger = logging.getLogger(__name__)
router = APIRouter()

# Admin API key authentication
_admin_api_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)


async def verify_admin_api_key(
    api_key: Optional[str] = Depends(_admin_api_key_header),
) -> str:
    """Verify the admin API key from X-Admin-Key header."""
    expected = os.getenv("AI_ADMIN_API_KEY", "")
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="Admin API key not configured on server",
        )
    if not api_key or not hmac.compare_digest(api_key, expected):
        raise HTTPException(status_code=403, detail="Invalid admin API key")
    return api_key


class AiConfig(BaseModel):
    """AI Service configuration model."""
    model_name: str = "gemini-1.5-flash"
    gemini_model: Optional[str] = None          # alias from frontend
    temperature: float = 0.7
    max_tokens: int = 2048
    top_p: float = 0.9
    top_k: int = 40
    gemini_api_key: Optional[str] = None
    use_mongodb: bool = True
    enable_voice: bool = True
    enable_grammar: bool = True
    enable_topic: bool = True
    chat_memory_turns: int = 10

    def effective_model_name(self) -> str:
        """Return the authoritative model name (prefer gemini_model if set)."""
        return self.gemini_model or self.model_name


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


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return slug or "topic"


def _story_to_list_item(story: Story) -> StoryListItem:
    return StoryListItem(
        story_id=story.story_id,
        title=story.title,
        difficulty_level=story.difficulty_level,
        category=story.category,
        estimated_minutes=story.estimated_minutes,
        icon_key=story.icon_key,
        cover_image_url=story.cover_image_url,
        suggested_prompts=story.suggested_prompts,
        tags=story.tags,
    )


def _build_admin_story(payload: AdminStoryCreateRequest) -> Story:
    title_en = payload.title.en.strip()
    title_vi = payload.title.vi.strip() or title_en
    story_id = payload.story_id or f"story_{_slugify(title_en)}"
    category = payload.category.strip().lower() or "daily_life"
    icon_key = (payload.icon_key or category).strip().lower() or category
    opening_prompt = (
        payload.opening_prompt
        or (payload.conversation_flow.opening_prompt if payload.conversation_flow else None)
        or f"Let's practice: {title_en}. What would you like to say first?"
    )

    tags = list(dict.fromkeys([*payload.tags, category, payload.difficulty_level.value, "admin_topic"]))

    return Story(
        story_id=story_id,
        title=LocalizedTitle(en=title_en, vi=title_vi),
        difficulty_level=payload.difficulty_level,
        category=category,
        estimated_minutes=payload.estimated_minutes,
        icon_key=icon_key,
        suggested_prompts=payload.suggested_prompts,
        tags=tags,
        is_published=payload.is_published,
        context_description=payload.context_description
        or ContextDescription(
            setting=title_en,
            scenario=f"Practice a real conversation about {title_en}.",
            objectives=["Start the conversation", "Ask relevant questions", "Respond naturally"],
        ),
        role_persona=payload.role_persona
        or RolePersona(
            name="Lexi",
            role="Conversation partner",
            personality="Helpful and encouraging",
            speaking_style="Natural, clear, and supportive",
            background=f"Lexi helps learners practice {title_en}.",
        ),
        conversation_flow=payload.conversation_flow
        or ConversationFlow(
            opening_prompt=opening_prompt,
            checkpoints=["Clarify the situation", "Practice key phrases", "Wrap up politely"],
        ),
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


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
async def get_admin_config(
    _key: str = Depends(verify_admin_api_key),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
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
                gemini_model="gemini-1.5-flash",
                gemini_api_key=mask_api_key(env_key) if env_key else None
            )
        
        # Return stored config with masked API key
        stored_key = config.get("gemini_api_key")
        if not stored_key:
            env_key = os.getenv("GEMINI_API_KEY")
            stored_key = env_key

        effective_model = config.get("gemini_model") or config.get("model_name", "gemini-1.5-flash")
        return AiConfig(
            model_name=effective_model,
            gemini_model=effective_model,
            temperature=config.get("temperature", 0.7),
            max_tokens=config.get("max_tokens", 2048),
            top_p=config.get("top_p", 0.9),
            top_k=config.get("top_k", 40),
            gemini_api_key=mask_api_key(stored_key),
            use_mongodb=config.get("use_mongodb", True),
            enable_voice=config.get("enable_voice", True),
            enable_grammar=config.get("enable_grammar", True),
            enable_topic=config.get("enable_topic", True),
            chat_memory_turns=config.get("chat_memory_turns", 10),
        )
    except Exception as e:
        logger.error(f"Error fetching admin config: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch configuration")


@router.put("/config")
async def update_admin_config(
    config: AiConfig,
    _key: str = Depends(verify_admin_api_key),
    db: AsyncIOMotorDatabase = Depends(get_database),
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
            "model_name": config.effective_model_name(),
            "gemini_model": config.effective_model_name(),
            "temperature": config.temperature,
            "max_tokens": config.max_tokens,
            "top_p": config.top_p,
            "top_k": config.top_k,
            "gemini_api_key": config.gemini_api_key,
            "use_mongodb": config.use_mongodb,
            "enable_voice": config.enable_voice,
            "enable_grammar": config.enable_grammar,
            "enable_topic": config.enable_topic,
            "chat_memory_turns": config.chat_memory_turns,
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
                "model_name": config.effective_model_name(),
                "gemini_model": config.effective_model_name(),
                "temperature": config.temperature,
                "max_tokens": config.max_tokens,
                "top_p": config.top_p,
                "top_k": config.top_k,
                "gemini_api_key": mask_api_key(config.gemini_api_key) if config.gemini_api_key else None,
                "use_mongodb": config.use_mongodb,
                "enable_voice": config.enable_voice,
                "enable_grammar": config.enable_grammar,
                "enable_topic": config.enable_topic,
                "chat_memory_turns": config.chat_memory_turns,
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating admin config: {e}")
        raise HTTPException(status_code=500, detail="Failed to update configuration")


@router.get("/topics")
async def list_admin_topics(
    limit: int = 100,
    _key: str = Depends(verify_admin_api_key),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """List topic chat stories for admin management."""
    cursor = (
        db["stories"]
        .find({"is_published": True})
        .sort("updated_at", -1)
        .limit(max(1, min(limit, 500)))
    )
    docs = await cursor.to_list(length=max(1, min(limit, 500)))
    stories = []
    for doc in docs:
        doc.pop("_id", None)
        try:
            stories.append(StoryListItem(**doc).model_dump(mode="json"))
        except Exception as exc:
            logger.warning("Skipping invalid admin topic list item: %s", exc)
    return {"success": True, "data": {"topics": stories, "total": len(stories)}}


@router.post("/topics")
async def create_admin_topic(
    payload: AdminStoryCreateRequest,
    _key: str = Depends(verify_admin_api_key),
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client=Depends(get_redis),
):
    """Create or update a topic chat story from the admin console."""
    story = _build_admin_story(payload)
    doc = story.model_dump(mode="json")
    await db["stories"].update_one(
        {"story_id": story.story_id},
        {"$set": {**doc, "updated_at": datetime.now(timezone.utc)}},
        upsert=True,
    )

    try:
        await redis_client.delete("topics:catalog:v2")
        await redis_client.delete("topics:catalog")
    except Exception as exc:
        logger.warning("Failed to invalidate topic catalog cache: %s", exc)

    return {
        "success": True,
        "message": "Topic saved",
        "data": _story_to_list_item(story).model_dump(mode="json"),
    }
