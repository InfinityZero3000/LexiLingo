"""
Tests for Phase 2 Topic Features:
1. Topic Catalog Service (Caching)
2. Topic Context Preloader (Context Bundling)
3. Cache Warming Endpoint
4. Chat Session Injection (Cache Hit Path)
"""

import pytest
import json
import uuid
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime

from api.services.topic_catalog_service import TopicCatalogService
from api.services.topic_preloader import TopicContextPreloader
from api.models.story_schemas import Story, LocalizedTitle, DifficultyLevel, ContextDescription, RolePersona, ConversationFlow

class TestTopicFeatures:
    
    @pytest.fixture
    def sample_story(self):
        return Story(
            story_id="test_story_1",
            title=LocalizedTitle(en="Test Story", vi="Câu chuyện thử nghiệm"),
            difficulty_level=DifficultyLevel.B1,
            category="test",
            context_description=ContextDescription(setting="Lab", scenario="Testing code", objectives=["Verify cache"]),
            role_persona=RolePersona(name="Tester", role="QA", personality="Rigorous", speaking_style="Formal", background="Codebase"),
            vocabulary_list=[],
            grammar_points=[],
            conversation_flow=ConversationFlow(opening_prompt="Hello, ready to test?"),
            is_published=True
        )

    @pytest.mark.asyncio
    async def test_topic_catalog_service_caching(self, mock_mongodb, mock_redis, sample_story):
        """Task 2.1: Verify TopicCatalogService uses Redis cache."""
        service = TopicCatalogService(mock_mongodb, mock_redis)
        
        # 1. Test cache miss
        mock_redis.get.return_value = None
        # Mock motor find() chain: collection.find().skip().limit()
        mock_cursor = MagicMock()
        mock_cursor.skip.return_value = mock_cursor
        mock_cursor.limit.return_value = mock_cursor
        mock_cursor.to_list = AsyncMock(return_value=[{"story_id": "test_story_1", "title": {"en": "Test", "vi": "Thử"}, "difficulty_level": "B1", "category": "test", "estimated_minutes": 15, "tags": []}])
        
        mock_mongodb["stories"].count_documents = AsyncMock(return_value=1)
        mock_mongodb["stories"].find = MagicMock(return_value=mock_cursor)
        
        topics = await service.get_topics()
        assert len(topics) == 1
        assert topics[0].story_id == "test_story_1"
        assert mock_redis.set.called
        
        # 2. Test cache hit
        mock_redis.get.return_value = json.dumps([topics[0].model_dump()])
        cached_topics = await service.get_topics()
        assert len(cached_topics) == 1
        assert cached_topics[0].story_id == "test_story_1"
        # Ensure it didn't call MongoDB count_documents again (skip find check due to MagicMock)
        assert mock_mongodb["stories"].count_documents.call_count == 1

    @pytest.mark.asyncio
    async def test_topic_preloader_bundle(self, mock_mongodb, mock_redis, sample_story):
        """Task 2.2 & 2.3: Verify preloader builds correct bundle and warms Redis."""
        preloader = TopicContextPreloader(mock_mongodb, mock_redis)
        
        # Mock get_story_by_id
        mock_mongodb["stories"].find_one = AsyncMock(return_value=sample_story.model_dump())
        
        bundle = await preloader.warm_cache("test_story_1", "user_1")
        
        assert bundle["topic_id"] == "test_story_1"
        assert "prime_prompt" in bundle
        assert "Tester" in bundle["prime_prompt"]
        
        # Verify Redis warming
        cache_key = f"chat:context:test_story_1"
        assert mock_redis.set.called
        args, kwargs = mock_redis.set.call_args
        assert args[0] == cache_key
        assert "prime_prompt" in args[1]

    @pytest.mark.asyncio
    async def test_start_session_cache_injection(self, mock_mongodb, mock_redis, sample_story):
        """Task 2.4: Verify start_topic_session injects context from GraphCache."""
        from api.routes.topic_chat import start_topic_session
        from api.models.story_schemas import StartTopicSessionRequest
        
        request = StartTopicSessionRequest(user_id="user_1", story_id="test_story_1")
        
        # Mock Cache HIT
        bundle = {
            "prime_prompt": "ENRICHED SYSTEM PROMPT",
            "title": "Cached Story"
        }
        mock_redis.get.return_value = json.dumps(bundle)
        
        # Stable mock for collections
        mock_sessions_col = AsyncMock()
        mock_messages_col = AsyncMock()
        mock_stories_col = AsyncMock()
        
        def get_collection(name):
            if name == "chat_sessions": return mock_sessions_col
            if name == "chat_messages": return mock_messages_col
            if name == "stories": return mock_stories_col
            return AsyncMock()
            
        mock_mongodb.__getitem__.side_effect = get_collection
        
        # Route needs story details for response
        mock_stories_col.find_one.return_value = sample_story.model_dump()
        
        with patch("api.routes.topic_chat.uuid.uuid4", return_value="mock-uuid"):
            response = await start_topic_session(request, mock_mongodb, mock_redis)
            
            # Verify session was created with CACHED prompt
            assert mock_sessions_col.insert_one.called
            session_doc = mock_sessions_col.insert_one.call_args[0][0]
            assert session_doc["system_prompt"] == "ENRICHED SYSTEM PROMPT"
            assert session_doc["session_id"] == "mock-uuid"
            
            # Verify cache was checked
            mock_redis.get.assert_called_with("chat:context:test_story_1")

    @pytest.mark.asyncio
    async def test_warm_endpoint(self, mock_mongodb, mock_redis, sample_story):
        """Task 2.3: Verify the /stories/warm endpoint correctly triggers preloading."""
        from api.routes.topic_chat import warm_topic_cache
        from api.models.story_schemas import WarmTopicCacheRequest
        
        request = WarmTopicCacheRequest(story_id="test_story_1", user_id="user_1")
        
        # Mock preloader dependency
        mock_preloader = AsyncMock()
        mock_preloader.warm_cache.return_value = {
            "title": "Test Story",
            "prime_prompt": "..."
        }
        
        response = await warm_topic_cache(request, mock_preloader)
        
        assert response.success is True
        assert response.topic_id == "test_story_1"
        assert "Test Story" in response.message
        assert mock_preloader.warm_cache.called
