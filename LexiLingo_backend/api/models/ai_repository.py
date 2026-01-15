"""
MongoDB Repository for AI interactions

Following Repository pattern from Clean Architecture
Similar to Flutter's DataSource implementations
"""

import logging
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any
from motor.motor_asyncio import AsyncIOMotorDatabase
from bson import ObjectId

from api.models.schemas import LogInteractionRequest, AIAnalysis, UserInput

logger = logging.getLogger(__name__)


class AIRepository:
    """
    Repository for AI interaction data.
    
    Similar to Flutter's ChatLocalDataSource / ChatFirestoreDataSource
    """
    
    def __init__(self, db: AsyncIOMotorDatabase):
        """Initialize repository with database."""
        self.db = db
        self.collection = db["ai_interactions"]
    
    async def log_interaction(
        self,
        request: LogInteractionRequest
    ) -> str:
        """
        Log AI interaction to database.
        
        Args:
            request: Interaction data
        
        Returns:
            Document ID
        """
        try:
            document = {
                "session_id": request.session_id,
                "user_id": request.user_id,
                "timestamp": datetime.utcnow(),
                "user_input": {
                    "text": request.user_input.text,
                    "audio_features": request.user_input.audio_features,
                    "context": request.user_input.context
                },
                "models_used": request.models_used,
                "processing_time_ms": request.processing_time_ms,
                "analysis": request.analysis.model_dump(),
                "user_feedback": request.user_feedback
            }
            
            result = await self.collection.insert_one(document)
            logger.info(f"Logged interaction: {result.inserted_id}")
            
            return str(result.inserted_id)
            
        except Exception as e:
            logger.error(f"Failed to log interaction: {e}")
            raise
    
    async def get_user_interactions(
        self,
        user_id: str,
        limit: int = 100,
        skip: int = 0
    ) -> List[Dict[str, Any]]:
        """
        Get user's interaction history.
        
        Similar to Flutter's getChatHistory()
        """
        try:
            cursor = self.collection.find(
                {"user_id": user_id}
            ).sort("timestamp", -1).skip(skip).limit(limit)
            
            interactions = await cursor.to_list(length=limit)
            
            # Convert ObjectId to string
            for interaction in interactions:
                interaction["_id"] = str(interaction["_id"])
            
            return interactions
            
        except Exception as e:
            logger.error(f"Failed to get user interactions: {e}")
            return []
    
    async def get_session_interactions(
        self,
        session_id: str
    ) -> List[Dict[str, Any]]:
        """Get all interactions in a session."""
        try:
            cursor = self.collection.find(
                {"session_id": session_id}
            ).sort("timestamp", 1)
            
            interactions = await cursor.to_list(length=None)
            
            for interaction in interactions:
                interaction["_id"] = str(interaction["_id"])
            
            return interactions
            
        except Exception as e:
            logger.error(f"Failed to get session interactions: {e}")
            return []
    
    async def update_feedback(
        self,
        interaction_id: str,
        feedback: Dict[str, Any]
    ) -> bool:
        """Update interaction with user feedback."""
        try:
            result = await self.collection.update_one(
                {"_id": ObjectId(interaction_id)},
                {"$set": {"user_feedback": feedback}}
            )
            
            return result.modified_count > 0
            
        except Exception as e:
            logger.error(f"Failed to update feedback: {e}")
            return False
    
    async def get_user_error_stats(
        self,
        user_id: str,
        days: int = 30
    ) -> List[Dict[str, Any]]:
        """
        Get aggregated error statistics for user.
        
        Similar to analytics queries in Flutter app.
        """
        try:
            cutoff_date = datetime.utcnow() - timedelta(days=days)
            
            pipeline = [
                {
                    "$match": {
                        "user_id": user_id,
                        "timestamp": {"$gte": cutoff_date}
                    }
                },
                {
                    "$unwind": "$analysis.grammar_errors"
                },
                {
                    "$group": {
                        "_id": "$analysis.grammar_errors.type",
                        "count": {"$sum": 1},
                        "examples": {"$push": "$analysis.grammar_errors.error"}
                    }
                },
                {
                    "$sort": {"count": -1}
                }
            ]
            
            results = await self.collection.aggregate(pipeline).to_list(None)
            return results
            
        except Exception as e:
            logger.error(f"Failed to get error stats: {e}")
            return []
