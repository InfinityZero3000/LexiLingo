"""
Topic Context Preloader (FeatureDev Phase 2.2 & 2.3)
Preloads topic data and warms PCC cache.
"""

import json
import logging
from typing import Dict, Any, Optional
import redis.asyncio as redis
from fastapi import Depends

from api.services.story_service import StoryService
from api.services.topic_prompt_builder import TopicPromptBuilder
from api.core.redis_client import get_redis
from api.core.database import get_database
from motor.motor_asyncio import AsyncIOMotorDatabase

logger = logging.getLogger(__name__)

class TopicContextPreloader:
    """Service for preloading topic context and warming cache."""
    
    PRELOAD_KEY_PREFIX = "chat:context:"
    
    def __init__(self, db: AsyncIOMotorDatabase, redis_client: redis.Redis):
        self.story_service = StoryService(db)
        self.redis = redis_client
        
    async def warm_cache(self, topic_id: str, user_id: str) -> Dict[str, Any]:
        """
        Preload topic context and build the context bundle.
        
        Steps:
        1. Load Story from MongoDB
        2. Build System Prompt (Prime Prompt)
        3. Bundle vocabulary, grammar, and metadata
        4. Cache in Redis for instant retrieval during session start
        """
        logger.info(f"Warming cache for topic: {topic_id}, user: {user_id}")
        
        # 1. Load topic data
        story = await self.story_service.get_story_by_id(topic_id)
        if not story:
            raise ValueError(f"Topic {topic_id} not found")
            
        # 2. Build context bundle
        # Use model_dump() for Pydantic v2
        bundle = {
            "topic_id": topic_id,
            "title": story.title.en,
            "difficulty": story.difficulty_level.value,
            "vocabulary": [v.model_dump() for v in story.vocabulary_list[:50]],
            "grammar_rules": [g.model_dump() for g in story.grammar_points],
            "user_weak_points": [], # Placeholder for future progress integration
            "suggested_focus": [obj for obj in story.context_description.objectives],
            "prime_prompt": TopicPromptBuilder.build_master_prompt(story)
        }
        
        # 3. Store in Redis
        cache_key = f"{self.PRELOAD_KEY_PREFIX}{topic_id}"
        await self.redis.set(cache_key, json.dumps(bundle), ex=3600) # 1 hour
        
        # 4. Optional: "Warming" the LLM could involve a pre-flight call
        # but for now we focus on data preloading.
        
        return bundle

async def get_topic_preloader(
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client: redis.Redis = Depends(get_redis)
) -> TopicContextPreloader:
    return TopicContextPreloader(db, redis_client)
