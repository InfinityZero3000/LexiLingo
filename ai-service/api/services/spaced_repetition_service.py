"""
Spaced Repetition Service

Implements SM-2 algorithm for optimal concept review scheduling.
Tracks user mastery and calculates next review dates.
"""

import logging
from datetime import datetime, timedelta
from enum import IntEnum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from api.core.database import get_database

logger = logging.getLogger(__name__)


# ============================================================
# SM-2 ALGORITHM CONSTANTS
# ============================================================


class Quality(IntEnum):
    """Response quality rating for SM-2 algorithm."""
    BLACKOUT = 0      # Complete failure
    INCORRECT = 1     # Incorrect but remembered after hint
    HARD = 2          # Correct but with difficulty
    GOOD = 3          # Correct with some hesitation
    EASY = 4          # Correct, easy recall
    PERFECT = 5       # Perfect, instant recall


# Initial easiness factor
INITIAL_EF = 2.5
MIN_EF = 1.3


# ============================================================
# MODELS
# ============================================================


class ConceptMastery(BaseModel):
    """User's mastery of a specific concept."""
    user_id: str
    concept_id: str
    easiness_factor: float = Field(default=INITIAL_EF, ge=MIN_EF)
    interval_days: int = 1
    repetitions: int = 0
    last_review: Optional[datetime] = None
    next_review: datetime = Field(default_factory=datetime.utcnow)
    last_quality: int = 0
    total_reviews: int = 0
    correct_count: int = 0


class ReviewItem(BaseModel):
    """Item due for review."""
    concept_id: str
    title: str
    category: str
    difficulty: int = 1
    overdue_days: int = 0
    priority: float = 0.0


class ReviewResult(BaseModel):
    """Result after reviewing a concept."""
    concept_id: str
    quality: Quality
    new_interval: int
    next_review: datetime
    mastery_change: float


# ============================================================
# SPACED REPETITION SERVICE
# ============================================================


class SpacedRepetitionService:
    """
    Spaced repetition implementation using SM-2 algorithm.

    The SM-2 algorithm calculates optimal review intervals:
    - EF (easiness factor) adjusts based on response quality
    - Interval increases exponentially for well-remembered items
    - Failed items reset to short intervals
    """

    COLLECTION = "spaced_repetition"

    def __init__(self):
        self._db = None

    async def _get_db(self):
        """Get database connection."""
        if self._db is None:
            self._db = await get_database()
        return self._db

    async def get_due_concepts(
        self,
        user_id: str,
        limit: int = 10,
    ) -> List[ReviewItem]:
        """
        Get concepts due for review.

        Args:
            user_id: User to get reviews for
            limit: Maximum number of items

        Returns:
            List of concepts ready for review, sorted by priority
        """
        try:
            db = await self._get_db()
            now = datetime.utcnow()

            cursor = db[self.COLLECTION].find({
                "user_id": user_id,
                "next_review": {"$lte": now},
            }).sort("next_review", 1).limit(limit)

            items = []
            async for doc in cursor:
                overdue = (now - doc["next_review"]).days
                priority = overdue + (1 / max(doc.get("easiness_factor", 2.5), 1))

                items.append(ReviewItem(
                    concept_id=doc["concept_id"],
                    title=doc.get("title", doc["concept_id"]),
                    category=doc.get("category", "general"),
                    difficulty=doc.get("difficulty", 1),
                    overdue_days=max(0, overdue),
                    priority=priority,
                ))

            # Sort by priority (higher = more urgent)
            items.sort(key=lambda x: x.priority, reverse=True)
            return items

        except Exception as e:
            logger.error(f"Failed to get due concepts: {e}")
            return []

    async def record_review(
        self,
        user_id: str,
        concept_id: str,
        quality: Quality,
    ) -> ReviewResult:
        """
        Record a review and update mastery using SM-2.

        Args:
            user_id: User who reviewed
            concept_id: Concept reviewed
            quality: Response quality (0-5)

        Returns:
            Updated review result with next interval
        """
        try:
            db = await self._get_db()

            # Get or create mastery record
            mastery = await self._get_or_create_mastery(user_id, concept_id)

            # Apply SM-2 algorithm
            new_ef, new_interval, repetitions = self._calculate_sm2(
                quality=quality,
                ef=mastery.easiness_factor,
                interval=mastery.interval_days,
                repetitions=mastery.repetitions,
            )

            # Calculate next review date
            next_review = datetime.utcnow() + timedelta(days=new_interval)

            # Calculate mastery change
            old_mastery = self._calculate_mastery_score(mastery)
            
            # Update record
            mastery.easiness_factor = new_ef
            mastery.interval_days = new_interval
            mastery.repetitions = repetitions
            mastery.last_review = datetime.utcnow()
            mastery.next_review = next_review
            mastery.last_quality = quality
            mastery.total_reviews += 1
            if quality >= Quality.GOOD:
                mastery.correct_count += 1

            new_mastery = self._calculate_mastery_score(mastery)

            # Save to database
            await db[self.COLLECTION].update_one(
                {"user_id": user_id, "concept_id": concept_id},
                {"$set": mastery.model_dump()},
                upsert=True,
            )

            return ReviewResult(
                concept_id=concept_id,
                quality=quality,
                new_interval=new_interval,
                next_review=next_review,
                mastery_change=new_mastery - old_mastery,
            )

        except Exception as e:
            logger.error(f"Failed to record review: {e}")
            return ReviewResult(
                concept_id=concept_id,
                quality=quality,
                new_interval=1,
                next_review=datetime.utcnow() + timedelta(days=1),
                mastery_change=0.0,
            )

    def _calculate_sm2(
        self,
        quality: Quality,
        ef: float,
        interval: int,
        repetitions: int,
    ) -> tuple[float, int, int]:
        """
        Apply SM-2 algorithm.

        Returns:
            (new_ef, new_interval, new_repetitions)
        """
        # Update easiness factor
        new_ef = ef + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
        new_ef = max(MIN_EF, new_ef)

        if quality < Quality.GOOD:
            # Failed - reset
            new_interval = 1
            new_reps = 0
        else:
            # Success - increase interval
            new_reps = repetitions + 1
            if new_reps == 1:
                new_interval = 1
            elif new_reps == 2:
                new_interval = 6
            else:
                new_interval = int(interval * new_ef)

        return new_ef, new_interval, new_reps

    def _calculate_mastery_score(self, mastery: ConceptMastery) -> float:
        """Calculate overall mastery score (0-1)."""
        if mastery.total_reviews == 0:
            return 0.0

        accuracy = mastery.correct_count / mastery.total_reviews
        ef_factor = (mastery.easiness_factor - MIN_EF) / (INITIAL_EF + 1 - MIN_EF)
        interval_factor = min(1.0, mastery.interval_days / 30)

        return (accuracy * 0.5 + ef_factor * 0.3 + interval_factor * 0.2)

    async def _get_or_create_mastery(
        self,
        user_id: str,
        concept_id: str,
    ) -> ConceptMastery:
        """Get existing mastery record or create new one."""
        try:
            db = await self._get_db()

            doc = await db[self.COLLECTION].find_one({
                "user_id": user_id,
                "concept_id": concept_id,
            })

            if doc:
                doc.pop("_id", None)
                return ConceptMastery(**doc)

            return ConceptMastery(
                user_id=user_id,
                concept_id=concept_id,
            )

        except Exception:
            return ConceptMastery(user_id=user_id, concept_id=concept_id)

    async def get_user_mastery_summary(
        self,
        user_id: str,
    ) -> Dict[str, Any]:
        """Get summary of user's concept mastery."""
        try:
            db = await self._get_db()

            pipeline = [
                {"$match": {"user_id": user_id}},
                {
                    "$group": {
                        "_id": None,
                        "total_concepts": {"$sum": 1},
                        "avg_ef": {"$avg": "$easiness_factor"},
                        "total_reviews": {"$sum": "$total_reviews"},
                        "total_correct": {"$sum": "$correct_count"},
                    }
                },
            ]

            cursor = db[self.COLLECTION].aggregate(pipeline)
            result = None
            async for doc in cursor:
                result = doc

            if not result:
                return {"total_concepts": 0, "accuracy": 0.0}

            return {
                "total_concepts": result["total_concepts"],
                "avg_easiness": result["avg_ef"],
                "total_reviews": result["total_reviews"],
                "accuracy": (
                    result["total_correct"] / result["total_reviews"]
                    if result["total_reviews"] > 0 else 0.0
                ),
            }

        except Exception as e:
            logger.error(f"Failed to get mastery summary: {e}")
            return {"total_concepts": 0, "accuracy": 0.0}

    async def seed_concepts_for_user(
        self,
        user_id: str,
        concept_ids: List[str],
    ):
        """Initialize mastery records for new concepts."""
        try:
            db = await self._get_db()

            for concept_id in concept_ids:
                await db[self.COLLECTION].update_one(
                    {"user_id": user_id, "concept_id": concept_id},
                    {
                        "$setOnInsert": ConceptMastery(
                            user_id=user_id,
                            concept_id=concept_id,
                        ).model_dump()
                    },
                    upsert=True,
                )

        except Exception as e:
            logger.error(f"Failed to seed concepts: {e}")


# ============================================================
# SINGLETON
# ============================================================

_service: Optional[SpacedRepetitionService] = None


def get_spaced_repetition_service() -> SpacedRepetitionService:
    """Get or create SpacedRepetitionService singleton."""
    global _service
    if _service is None:
        _service = SpacedRepetitionService()
    return _service
