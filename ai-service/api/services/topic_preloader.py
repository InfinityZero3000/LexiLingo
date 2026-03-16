import json
import logging
from typing import Dict, Any, Optional, List
import redis.asyncio as redis
from fastapi import Depends

from api.services.story_service import StoryService
from api.services.topic_prompt_builder import TopicPromptBuilder
from api.services.document_intelligence import get_doc_intel_service, DocumentIntelligenceService
from api.core.redis_client import get_redis
from api.core.database import get_database
from motor.motor_asyncio import AsyncIOMotorDatabase

logger = logging.getLogger(__name__)

class TopicContextPreloader:
    """Service for preloading topic context and warming PCC cache with dynamic data support."""
    
    PRELOAD_KEY_PREFIX = "chat:context:"
    
    def __init__(self, db: AsyncIOMotorDatabase, redis_client: redis.Redis, doc_service: DocumentIntelligenceService):
        self.story_service = StoryService(db)
        self.redis = redis_client
        self.doc_service = doc_service
        
    async def _collect_dynamic_context(self, story: Any) -> str:
        """Collect real-time information for dynamic topics using web search/scraping."""
        tags = getattr(story, 'tags', [])
        if "real_time" not in tags and "weather" not in tags and "news" not in tags:
            return ""
            
        logger.info(f"Triggering dynamic collection for topic: {story.story_id}")
        
        # Build a specific query based on tags
        query = f"current {story.title.en} today"
        if "weather" in tags:
            query = "current weather forecast and temperature today"
            
        try:
            # Use L2 retrieval (Web Search fallback)
            external_data = await self.doc_service.query_l2(query, top_k=2)
            
            if not external_data:
                return ""
                
            context_str = "\n--- REAL-TIME CONTEXT (FRESHLY COLLECTED) ---\n"
            for i, entry in enumerate(external_data):
                context_str += f"Source {i+1}: {entry['content']}\n"
            context_str += "--------------------------------------------\n"
            
            return context_str
        except Exception as e:
            logger.error(f"Dynamic collection failed: {e}")
            return ""

    async def warm_cache(self, topic_id: str, user_id: str) -> Dict[str, Any]:
        """
        Preload topic context and build the context bundle.
        Now supports Dynamic Collection for real-time topics.
        """
        logger.info(f"Warming cache for topic: {topic_id}, user: {user_id}")
        
        # 1. Load topic data
        story = await self.story_service.get_story_by_id(topic_id)
        if not story:
            raise ValueError(f"Topic {topic_id} not found")
            
        # 2. Collect Dynamic Data if applicable
        dynamic_context = await self._collect_dynamic_context(story)
        
        # 3. Build master prompt with dynamic injection
        master_prompt = TopicPromptBuilder.build_master_prompt(story)
        if dynamic_context:
            master_prompt = f"{dynamic_context}\n\n{master_prompt}"
            logger.info(f"Injected {len(dynamic_context)} chars of real-time data into prime prompt.")
            
        # 4. Build context bundle
        bundle = {
            "topic_id": topic_id,
            "title": story.title.en,
            "difficulty": story.difficulty_level.value,
            "vocabulary": [v.model_dump() for v in story.vocabulary_list[:50]],
            "grammar_rules": [g.model_dump() for g in story.grammar_points],
            "user_weak_points": [], 
            "suggested_focus": [obj for obj in story.context_description.objectives],
            "suggested_prompts": story.suggested_prompts or [],
            "prime_prompt": master_prompt,
            "has_dynamic_data": bool(dynamic_context)
        }
        
        # 5. Store in Redis
        cache_key = f"{self.PRELOAD_KEY_PREFIX}{topic_id}"
        await self.redis.set(cache_key, json.dumps(bundle), ex=3600) # 1 hour
        
        return bundle

async def get_topic_preloader(
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client: redis.Redis = Depends(get_redis),
    doc_service: DocumentIntelligenceService = Depends(get_doc_intel_service)
) -> TopicContextPreloader:
    return TopicContextPreloader(db, redis_client, doc_service)
