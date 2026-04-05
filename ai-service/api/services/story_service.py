"""
Story Service

CRUD operations for stories/topics in MongoDB.
"""

import json
import logging
from pathlib import Path
from typing import List, Optional
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime

from api.models.story_schemas import (
    Story,
    StoryListItem,
    DifficultyLevel,
    LocalizedTitle,
)


logger = logging.getLogger(__name__)
_SAMPLE_STORIES_PATH = Path(__file__).resolve().parents[2] / "data" / "sample_stories.json"


class StoryService:
    """Service for managing stories in MongoDB"""

    _sample_stories_cache: Optional[List[Story]] = None
    
    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.collection = db["stories"]

    def _normalize_doc(self, doc: dict) -> dict:
        normalized = dict(doc)
        normalized.pop("_id", None)

        if isinstance(normalized.get("title"), dict):
            normalized["title"] = LocalizedTitle(**normalized["title"])

        return normalized

    def _to_list_item(self, story: Story) -> StoryListItem:
        return StoryListItem(
            story_id=story.story_id,
            title=story.title,
            difficulty_level=story.difficulty_level,
            category=story.category,
            estimated_minutes=story.estimated_minutes,
            cover_image_url=story.cover_image_url,
            suggested_prompts=story.suggested_prompts,
            tags=story.tags,
        )

    def _load_sample_stories(self) -> List[Story]:
        """Load bundled sample stories as fallback when DB has no data."""
        if StoryService._sample_stories_cache is not None:
            return StoryService._sample_stories_cache

        loaded: List[Story] = []

        try:
            if not _SAMPLE_STORIES_PATH.exists():
                logger.warning("Sample stories file not found at %s", _SAMPLE_STORIES_PATH)
                StoryService._sample_stories_cache = []
                return []

            with _SAMPLE_STORIES_PATH.open("r", encoding="utf-8") as f:
                payload = json.load(f)

            raw_stories = payload.get("stories", payload) if isinstance(payload, dict) else payload

            if isinstance(raw_stories, list):
                for raw in raw_stories:
                    if not isinstance(raw, dict):
                        continue
                    try:
                        story = Story(**self._normalize_doc(raw))
                        if story.is_published:
                            loaded.append(story)
                    except Exception as parse_err:
                        logger.warning("Skipping invalid sample story: %s", parse_err)

            logger.info("Loaded %d sample stories as fallback", len(loaded))
        except Exception as e:
            logger.warning("Failed to load sample stories fallback: %s", e)

        StoryService._sample_stories_cache = loaded
        return loaded
    
    async def get_story_by_id(self, story_id: str) -> Optional[Story]:
        """
        Get a single story by its unique story_id.
        
        Args:
            story_id: Unique story identifier
            
        Returns:
            Story object if found, None otherwise
        """
        try:
            doc = await self.collection.find_one({
                "story_id": story_id,
                "is_published": True
            })

            if doc:
                return Story(**self._normalize_doc(doc))
        except Exception as e:
            logger.warning("MongoDB get_story_by_id failed, using fallback: %s", e)

        for story in self._load_sample_stories():
            if story.story_id == story_id:
                return story

        return None
    
    async def list_stories(
        self,
        category: Optional[str] = None,
        difficulty_level: Optional[DifficultyLevel] = None,
        limit: int = 20,
        skip: int = 0
    ) -> tuple[List[StoryListItem], int]:
        """
        List available stories with optional filters.
        
        Args:
            category: Filter by category
            difficulty_level: Filter by CEFR level
            limit: Maximum stories to return
            skip: Number of stories to skip (pagination)
            
        Returns:
            Tuple of (list of stories, total count)
        """
        query = {"is_published": True}

        if category:
            query["category"] = category
        if difficulty_level:
            query["difficulty_level"] = difficulty_level.value

        try:
            # Get total count
            total = await self.collection.count_documents(query)

            # Get stories with projection for list view
            cursor = self.collection.find(
                query,
                projection={
                    "story_id": 1,
                    "title": 1,
                    "difficulty_level": 1,
                    "category": 1,
                    "estimated_minutes": 1,
                    "cover_image_url": 1,
                    "suggested_prompts": 1,
                    "tags": 1
                }
            ).skip(skip).limit(limit)

            docs = await cursor.to_list(length=limit)

            stories = [StoryListItem(**self._normalize_doc(doc)) for doc in docs]

            if stories or total > 0:
                return stories, total
        except Exception as e:
            logger.warning("MongoDB list_stories failed, using fallback: %s", e)

        fallback_stories = self._load_sample_stories()

        if category:
            fallback_stories = [s for s in fallback_stories if s.category == category]
        if difficulty_level:
            fallback_stories = [s for s in fallback_stories if s.difficulty_level == difficulty_level]

        total = len(fallback_stories)
        paged = fallback_stories[skip: skip + limit]
        return [self._to_list_item(s) for s in paged], total
    
    async def get_categories(self) -> List[str]:
        """Get all unique story categories."""
        try:
            categories = await self.collection.distinct("category", {"is_published": True})
            if categories:
                return categories
        except Exception as e:
            logger.warning("MongoDB get_categories failed, using fallback: %s", e)

        return sorted({story.category for story in self._load_sample_stories()})
    
    async def create_story(self, story: Story) -> str:
        """
        Create a new story.
        
        Args:
            story: Story object to create
            
        Returns:
            The story_id of the created story
        """
        doc = story.model_dump()
        doc["created_at"] = datetime.utcnow()
        doc["updated_at"] = datetime.utcnow()
        
        # Convert nested models to dicts
        if hasattr(doc.get("title"), "model_dump"):
            doc["title"] = doc["title"].model_dump()
        
        await self.collection.insert_one(doc)
        return story.story_id
    
    async def update_story(self, story_id: str, updates: dict) -> bool:
        """
        Update an existing story.
        
        Args:
            story_id: Story to update
            updates: Dictionary of fields to update
            
        Returns:
            True if story was updated, False otherwise
        """
        updates["updated_at"] = datetime.utcnow()
        
        result = await self.collection.update_one(
            {"story_id": story_id},
            {"$set": updates}
        )
        
        return result.modified_count > 0
    
    async def delete_story(self, story_id: str) -> bool:
        """
        Delete a story (soft delete by setting is_published=False).
        
        Args:
            story_id: Story to delete
            
        Returns:
            True if story was deleted, False otherwise
        """
        result = await self.collection.update_one(
            {"story_id": story_id},
            {"$set": {"is_published": False, "updated_at": datetime.utcnow()}}
        )
        
        return result.modified_count > 0
