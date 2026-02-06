"""
Learning Patterns Repository

Manages user learning patterns with Redis-MongoDB synchronization.
Redis provides fast read access, MongoDB provides persistence and aggregation.
"""

import logging
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from api.core.database import get_database
from api.core.redis_client import get_learner_cache

logger = logging.getLogger(__name__)


# ============================================================
# MODELS
# ============================================================


class ErrorPattern(BaseModel):
    """User error pattern aggregate."""
    type: str
    frequency: int
    examples: List[str] = Field(default_factory=list)
    trend: str = "stable"  # increasing, stable, decreasing
    last_seen: Optional[datetime] = None


class ImprovementRate(BaseModel):
    """Improvement rates across skill areas."""
    grammar: float = 0.0
    pronunciation: float = 0.0
    vocabulary: float = 0.0
    fluency: float = 0.0


class LearningPattern(BaseModel):
    """Complete learning pattern for a user."""
    user_id: str
    analyzed_at: datetime = Field(default_factory=datetime.utcnow)
    common_errors: List[ErrorPattern] = Field(default_factory=list)
    improvement_rate: ImprovementRate = Field(default_factory=ImprovementRate)
    strengths: List[str] = Field(default_factory=list)
    weaknesses: List[str] = Field(default_factory=list)
    recommended_focus: List[str] = Field(default_factory=list)
    estimated_level: str = "B1"
    next_level_progress: float = 0.0  # 0-100%
    stats: Dict[str, Any] = Field(default_factory=dict)


# ============================================================
# REPOSITORY
# ============================================================


class LearningPatternRepository:
    """
    Repository for user learning patterns.

    Provides:
    - Redis caching for fast reads
    - MongoDB persistence for durability
    - Automatic sync between Redis and MongoDB
    """

    COLLECTION = "learning_patterns"
    REDIS_KEY_PREFIX = "learner_pattern"
    REDIS_TTL_HOURS = 24

    def __init__(self):
        self._db = None

    async def _get_db(self):
        """Get MongoDB connection."""
        if self._db is None:
            self._db = await get_database()
        return self._db

    async def get_pattern(self, user_id: str) -> Optional[LearningPattern]:
        """
        Get user's learning pattern.

        Tries Redis first, falls back to MongoDB.
        """
        # Try Redis cache first
        try:
            cache = await get_learner_cache()
            cached = await cache.redis.get(f"{self.REDIS_KEY_PREFIX}:{user_id}")
            if cached:
                import json
                data = json.loads(cached)
                return LearningPattern(**data)
        except Exception as e:
            logger.warning(f"Redis cache read failed: {e}")

        # Fall back to MongoDB
        try:
            db = await self._get_db()
            doc = await db[self.COLLECTION].find_one(
                {"user_id": user_id},
                sort=[("analyzed_at", -1)]
            )
            if doc:
                doc.pop("_id", None)
                pattern = LearningPattern(**doc)
                # Cache in Redis for next time
                await self._cache_pattern(pattern)
                return pattern
        except Exception as e:
            logger.error(f"MongoDB read failed: {e}")

        return None

    async def save_pattern(self, pattern: LearningPattern) -> bool:
        """
        Save learning pattern to both Redis and MongoDB.

        Returns True if successful.
        """
        try:
            # Save to MongoDB
            db = await self._get_db()
            await db[self.COLLECTION].update_one(
                {"user_id": pattern.user_id},
                {"$set": pattern.model_dump()},
                upsert=True
            )

            # Cache in Redis
            await self._cache_pattern(pattern)

            logger.info(f"Saved learning pattern for user {pattern.user_id}")
            return True

        except Exception as e:
            logger.error(f"Failed to save learning pattern: {e}")
            return False

    async def _cache_pattern(self, pattern: LearningPattern):
        """Cache pattern in Redis."""
        try:
            import json
            cache = await get_learner_cache()
            key = f"{self.REDIS_KEY_PREFIX}:{pattern.user_id}"
            data = pattern.model_dump(mode="json")
            await cache.redis.set(
                key,
                json.dumps(data),
                ex=timedelta(hours=self.REDIS_TTL_HOURS)
            )
        except Exception as e:
            logger.warning(f"Redis cache write failed: {e}")

    async def update_after_interaction(
        self,
        user_id: str,
        grammar_errors: List[Dict[str, Any]],
        fluency_score: float,
        vocabulary_level: str,
    ):
        """
        Update pattern incrementally after each interaction.

        Lightweight update to Redis, periodic batch to MongoDB.
        """
        try:
            cache = await get_learner_cache()

            # Update error patterns in Redis
            for error in grammar_errors:
                error_type = error.get("type", "unknown")
                await cache.add_error(user_id, error_type)

            # Check if we should sync to MongoDB (every 10 interactions)
            interaction_key = f"learner:{user_id}:interaction_count"
            count = await cache.redis.incr(interaction_key)

            if count >= 10:
                # Reset counter
                await cache.redis.set(interaction_key, "0")
                # Trigger full pattern analysis
                await self.analyze_and_save(user_id)

        except Exception as e:
            logger.warning(f"Failed to update after interaction: {e}")

    async def analyze_and_save(self, user_id: str) -> Optional[LearningPattern]:
        """
        Analyze user interactions and generate learning pattern.

        Aggregates data from ai_interactions collection.
        """
        try:
            db = await self._get_db()

            # Get recent interactions (last 30 days)
            cutoff = datetime.utcnow() - timedelta(days=30)

            # Aggregate grammar errors
            error_pipeline = [
                {"$match": {"user_id": user_id, "timestamp": {"$gte": cutoff}}},
                {"$unwind": "$analysis.grammar_errors"},
                {
                    "$group": {
                        "_id": "$analysis.grammar_errors.type",
                        "count": {"$sum": 1},
                        "examples": {"$push": "$analysis.grammar_errors.error"},
                    }
                },
                {"$sort": {"count": -1}},
                {"$limit": 10},
            ]

            cursor = db["ai_interactions"].aggregate(error_pipeline)
            error_patterns = []
            async for doc in cursor:
                error_patterns.append(ErrorPattern(
                    type=doc["_id"],
                    frequency=doc["count"],
                    examples=doc["examples"][:5],
                ))

            # Get average scores
            stats_pipeline = [
                {"$match": {"user_id": user_id, "timestamp": {"$gte": cutoff}}},
                {
                    "$group": {
                        "_id": None,
                        "avg_fluency": {"$avg": "$analysis.fluency_score"},
                        "total_interactions": {"$sum": 1},
                        "levels": {"$push": "$analysis.vocabulary_level"},
                    }
                },
            ]

            stats_cursor = db["ai_interactions"].aggregate(stats_pipeline)
            stats = {}
            async for doc in stats_cursor:
                stats = {
                    "avg_fluency": doc.get("avg_fluency", 0.0),
                    "total_interactions": doc.get("total_interactions", 0),
                }

            # Determine strengths and weaknesses
            weaknesses = [ep.type for ep in error_patterns[:3]]
            strengths = []
            if stats.get("avg_fluency", 0) > 0.8:
                strengths.append("fluency")
            if len(error_patterns) == 0:
                strengths.append("grammar")

            # Create pattern
            pattern = LearningPattern(
                user_id=user_id,
                common_errors=error_patterns,
                strengths=strengths,
                weaknesses=weaknesses,
                recommended_focus=weaknesses[:2] if weaknesses else ["practice"],
                stats=stats,
            )

            # Save pattern
            await self.save_pattern(pattern)

            return pattern

        except Exception as e:
            logger.error(f"Failed to analyze patterns: {e}")
            return None

    async def update_user_level(
        self,
        user_id: str,
        new_level: str,
        progress: float = 0.0,
    ):
        """
        Update user's estimated level.

        Updates both Redis cache and MongoDB.
        """
        try:
            # Update Redis
            cache = await get_learner_cache()
            await cache.set_level(user_id, new_level)

            # Update MongoDB
            db = await self._get_db()
            await db[self.COLLECTION].update_one(
                {"user_id": user_id},
                {
                    "$set": {
                        "estimated_level": new_level,
                        "next_level_progress": progress,
                        "analyzed_at": datetime.utcnow(),
                    }
                },
                upsert=True,
            )

            logger.info(f"Updated level for user {user_id}: {new_level}")

        except Exception as e:
            logger.error(f"Failed to update user level: {e}")


# ============================================================
# SINGLETON
# ============================================================

_repository: Optional[LearningPatternRepository] = None


def get_learning_pattern_repository() -> LearningPatternRepository:
    """Get or create the LearningPatternRepository singleton."""
    global _repository
    if _repository is None:
        _repository = LearningPatternRepository()
    return _repository
