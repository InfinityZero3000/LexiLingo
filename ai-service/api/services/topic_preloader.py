import asyncio
import json
import logging
from typing import Callable, Dict, Any, Optional
import redis.asyncio as redis
from fastapi import Depends

from api.services.story_service import StoryService
from api.services.topic_prompt_builder import TopicPromptBuilder
from api.core.redis_client import get_redis
from api.core.database import get_database
from motor.motor_asyncio import AsyncIOMotorDatabase

logger = logging.getLogger(__name__)


from api.services.trace_cag.env_helpers import _env_float

TOPIC_KG_WARM_TIMEOUT_SEC = _env_float("TOPIC_KG_WARM_TIMEOUT_SEC", 8.0)


class TopicContextBundle(dict):
    """Dict-compatible bundle with Pydantic-style dumping for older callers."""

    def model_dump(self, *args: Any, **kwargs: Any) -> Dict[str, Any]:
        return dict(self)


class TopicContextPreloader:
    """Service for preloading topic context and warming PCC cache with dynamic data support."""
    
    PRELOAD_KEY_PREFIX = "chat:context:"
    
    def __init__(
        self,
        db: AsyncIOMotorDatabase,
        redis_client: redis.Redis,
        doc_service: Optional[Any] = None,
        doc_service_provider: Optional[Callable[[], Optional[Any]]] = None,
    ):
        self.story_service = StoryService(db)
        self.redis = redis_client
        self.doc_service = doc_service
        self.doc_service_provider = doc_service_provider

    def _get_doc_service(self) -> Optional[Any]:
        """Create the dynamic context service only for topics that need it."""
        if self.doc_service is not None:
            return self.doc_service
        if self.doc_service_provider is None:
            return None

        try:
            self.doc_service = self.doc_service_provider()
            return self.doc_service
        except Exception as exc:
            logger.warning("Dynamic context service unavailable: %s", exc)
            return None
        
    async def _collect_dynamic_context(self, story: Any) -> str:
        """Collect real-time information for dynamic topics using web search/scraping."""
        tags = getattr(story, 'tags', [])
        if "real_time" not in tags and "weather" not in tags and "news" not in tags:
            return ""

        doc_service = self._get_doc_service()
        if doc_service is None:
            logger.info("Dynamic context skipped: document intelligence service unavailable")
            return ""
            
        logger.info(f"Triggering dynamic collection for topic: {story.story_id}")
        
        # Build a specific query based on tags
        query = f"current {story.title.en} today"
        if "weather" in tags:
            query = "current weather forecast and temperature today"
            
        try:
            # Use L2 retrieval (Web Search fallback)
            external_data = await doc_service.query_l2(query, top_k=2)
            
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
        # vocabulary_list and grammar_points are List[Dict] — already plain dicts
        _context_desc = story.context_description
        _objectives = (
            _context_desc.get("objectives") if isinstance(_context_desc, dict)
            else getattr(_context_desc, "objectives", [])
        ) or []
        bundle = {
            "topic_id": topic_id,
            "title": story.title.en,
            "difficulty": story.difficulty_level.value,
            "vocabulary": list(story.vocabulary_list[:50]),
            "grammar_rules": list(story.grammar_points),
            "user_weak_points": [],
            "suggested_focus": list(_objectives),
            "suggested_prompts": story.suggested_prompts or [],
            "prime_prompt": master_prompt,
            "has_dynamic_data": bool(dynamic_context),
            "kg_seed_concepts": [],
            "kg_topic_fingerprint": "",
            "cache_metadata": {
                "context_cache_warmed": False,
                "kg_cache_warmed": False,
                "kg_seed_count": 0,
                "kg_node_count": 0,
                "kg_path_count": 0,
            },
        }

        # 5. Pre-compute topic KG subgraph. This is best effort: chat can still
        # start with the plain topic prompt if KG/Kuzu is unavailable.
        try:
            from api.services.subgraph_hot_cache import warm_subgraph

            subgraph = await asyncio.wait_for(
                warm_subgraph(
                    story_id=topic_id,
                    story_vocab=story.vocabulary_list,
                    story_grammar=story.grammar_points,
                    story_level=story.difficulty_level.value,
                    redis_client=self.redis,
                ),
                timeout=TOPIC_KG_WARM_TIMEOUT_SEC,
            )
            kg_seeds = list(subgraph.get("seed_concepts") or [])
            bundle["kg_seed_concepts"] = kg_seeds
            bundle["kg_topic_fingerprint"] = subgraph.get("topic_fingerprint", "")
            bundle["cache_metadata"].update(
                {
                    "kg_cache_warmed": bool(
                        kg_seeds or subgraph.get("nodes") or subgraph.get("paths")
                    ),
                    "kg_seed_count": len(kg_seeds),
                    "kg_node_count": len(subgraph.get("nodes") or []),
                    "kg_path_count": len(subgraph.get("paths") or []),
                }
            )
        except Exception as exc:
            logger.warning("KG subgraph warm skipped for topic %s: %s", topic_id, exc)

        # 6. Store prompt/context bundle in Redis. Storage failures should not
        # make the warm endpoint a hard 500 because this endpoint is a preload
        # optimization, not the source of truth for topic data.
        cache_key = f"{self.PRELOAD_KEY_PREFIX}{topic_id}"
        try:
            bundle["cache_metadata"]["context_cache_warmed"] = True
            await self.redis.set(cache_key, json.dumps(bundle, default=str), ex=3600) # 1 hour
        except Exception as exc:
            bundle["cache_metadata"]["context_cache_warmed"] = False
            logger.warning("Context cache store failed for topic %s: %s", topic_id, exc)
        
        return TopicContextBundle(bundle)

async def get_topic_preloader(
    db: AsyncIOMotorDatabase = Depends(get_database),
    redis_client: redis.Redis = Depends(get_redis),
) -> TopicContextPreloader:
    def _load_doc_service() -> Optional[Any]:
        from api.services.document_intelligence import get_doc_intel_service

        return get_doc_intel_service()

    return TopicContextPreloader(db, redis_client, doc_service_provider=_load_doc_service)
