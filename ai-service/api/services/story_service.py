"""
Story Service

CRUD operations for stories/topics in MongoDB.
"""

from typing import List, Optional
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime

from api.models.story_schemas import (
    Story,
    StoryListItem,
    DifficultyLevel,
    LocalizedTitle,
)


class StoryService:
    """Service for managing stories in MongoDB"""
    
    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.collection = db["stories"]
    
    async def get_story_by_id(self, story_id: str) -> Optional[Story]:
        """
        Get a single story by its unique story_id.
        
        Args:
            story_id: Unique story identifier
            
        Returns:
            Story object if found, None otherwise
        """
        doc = await self.collection.find_one({
            "story_id": story_id,
            "is_published": True
        })
        
        if not doc:
            return None
        
        # Remove MongoDB _id field
        doc.pop("_id", None)
        
        # Handle nested title conversion
        if isinstance(doc.get("title"), dict):
            doc["title"] = LocalizedTitle(**doc["title"])
        
        return Story(**doc)
    
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
                "tags": 1
            }
        ).skip(skip).limit(limit)
        
        docs = await cursor.to_list(length=limit)
        
        stories = []
        for doc in docs:
            doc.pop("_id", None)
            if isinstance(doc.get("title"), dict):
                doc["title"] = LocalizedTitle(**doc["title"])
            stories.append(StoryListItem(**doc))
        
        return stories, total
    
    async def get_categories(self) -> List[str]:
        """Get all unique story categories."""
        return await self.collection.distinct("category", {"is_published": True})
    
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
