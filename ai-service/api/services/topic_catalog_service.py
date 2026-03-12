"""
Topic Catalog Service (FeatureDev Phase 2.1)
Exposes topic list with metadata and handles GraphCache storage in Redis.
"""

import json
import logging
from typing import List, Optional
from motor.motor_asyncio import AsyncIOMotorDatabase
import redis.asyncio as redis
from fastapi import Depends

from api.models.story_schemas import Story, StoryListItem
from api.services.story_service import StoryService
from api.core.redis_client import get_redis
from api.core.database import get_database

logger = logging.getLogger(__name__)

class TopicCatalogService:
    """Service for fetching and caching topic catalog."""
    
    CACHE_KEY = "topics:catalog"
    CACHE_TTL = 3600  # 1 hour
    
    def __init__(self, db: AsyncIOMotorDatabase, redis_client: redis.Redis):
        self.story_service = StoryService(db)
        self.redis = redis_client
        
    async def get_topics(self, bypass_cache: bool = False) -> List[StoryListItem]:
        """Fetch all available topics, checking cache first."""
        if not bypass_cache:
            try:
                cached = await self.redis.get(self.CACHE_KEY)
                if cached:
                    data = json.loads(cached)
                    return [StoryListItem(**item) for item in data]
            except Exception as e:
                logger.warning(f"Failed to fetch cached topics: {e}")
        
        # Cache miss or bypass
        stories, _ = await self.story_service.list_stories(limit=100)
        
        # Save to cache
        try:
            # Pydantic v2 uses model_dump()
            data_to_cache = []
            for s in stories:
                if hasattr(s, "model_dump"):
                    data_to_cache.append(s.model_dump())
                else:
                    data_to_cache.append(dict(s))
                    
            await self.redis.set(
                self.CACHE_KEY,
                json.dumps(data_to_cache),
                ex=self.CACHE_TTL
            )
        except Exception as e:
            logger.warning(f"Failed to cache topics: {e}")
            
        return stories
        
    async def get_topic_by_id(self, topic_id: str) -> Optional[Story]:
        """Get full story details by ID."""
        return await self.story_service.get_story_by_id(topic_id)

async def get_topic_catalog_service(
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client: redis.Redis = Depends(get_redis)
) -> TopicCatalogService:
    """Dependency injection helper for TopicCatalogService."""
    return TopicCatalogService(db, redis_client)
