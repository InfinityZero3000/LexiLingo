"""
Assessment Service

Automatic user level assessment based on performance data.
Implements CEFR level inference algorithm.
"""

import logging
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel, Field

from api.core.database import get_database

logger = logging.getLogger(__name__)


# ============================================================
# CEFR LEVELS
# ============================================================


class CEFRLevel(str, Enum):
    """Common European Framework of Reference levels."""
    A1 = "A1"  # Beginner
    A2 = "A2"  # Elementary
    B1 = "B1"  # Intermediate
    B2 = "B2"  # Upper Intermediate
    C1 = "C1"  # Advanced
    C2 = "C2"  # Mastery


# CEFR thresholds (weighted score -> level)
CEFR_THRESHOLDS = {
    0.0: CEFRLevel.A1,
    0.20: CEFRLevel.A2,
    0.40: CEFRLevel.B1,
    0.60: CEFRLevel.B2,
    0.80: CEFRLevel.C1,
    0.95: CEFRLevel.C2,
}


# ============================================================
# MODELS
# ============================================================


class AssessmentMetrics(BaseModel):
    """Raw metrics used for level calculation."""
    grammar_accuracy: float = Field(0.0, ge=0.0, le=1.0)
    vocabulary_complexity: float = Field(0.0, ge=0.0, le=1.0)
    fluency_score: float = Field(0.0, ge=0.0, le=1.0)
    consistency_score: float = Field(0.0, ge=0.0, le=1.0)
    interaction_count: int = 0
    error_trend: str = "stable"  # improving, stable, declining


class LevelAssessment(BaseModel):
    """Complete level assessment result."""
    user_id: str
    current_level: CEFRLevel = CEFRLevel.B1
    previous_level: Optional[CEFRLevel] = None
    confidence: float = Field(0.0, ge=0.0, le=1.0)
    progress_to_next: float = Field(0.0, ge=0.0, le=1.0)
    metrics: AssessmentMetrics = Field(default_factory=AssessmentMetrics)
    strengths: List[str] = Field(default_factory=list)
    areas_to_improve: List[str] = Field(default_factory=list)
    recommendations: List[str] = Field(default_factory=list)
    assessed_at: datetime = Field(default_factory=datetime.utcnow)
    next_assessment: Optional[datetime] = None


class LevelHistory(BaseModel):
    """User level change history."""
    user_id: str
    level: CEFRLevel
    changed_at: datetime
    reason: str = ""
    confidence: float = 0.0


# ============================================================
# ASSESSMENT SERVICE
# ============================================================


class AssessmentService:
    """
    User level assessment service.

    Provides automatic CEFR level inference based on:
    - Grammar accuracy (40% weight)
    - Vocabulary complexity (30% weight)
    - Fluency score (30% weight)
    """

    COLLECTION_ASSESSMENTS = "user_assessments"
    COLLECTION_HISTORY = "level_history"

    # Weights for level calculation
    WEIGHT_GRAMMAR = 0.40
    WEIGHT_VOCABULARY = 0.30
    WEIGHT_FLUENCY = 0.30

    # Minimum interactions for confident assessment
    MIN_INTERACTIONS = 5

    def __init__(self):
        self._db = None

    async def _get_db(self):
        """Get database connection."""
        if self._db is None:
            self._db = await get_database()
        return self._db

    async def assess_user(
        self,
        user_id: str,
        days: int = 30,
        force: bool = False,
    ) -> LevelAssessment:
        """
        Assess user's English level based on recent interactions.

        Args:
            user_id: User to assess
            days: Number of days to analyze
            force: Force reassessment even if recent

        Returns:
            Complete level assessment
        """
        try:
            db = await self._get_db()

            # Check if recent assessment exists
            if not force:
                existing = await self._get_recent_assessment(user_id)
                if existing:
                    return existing

            # Get metrics from interactions
            metrics = await self._calculate_metrics(user_id, days)

            # Calculate weighted score
            weighted_score = self._calculate_weighted_score(metrics)

            # Determine CEFR level
            current_level = self._score_to_cefr(weighted_score)

            # Calculate confidence based on interaction count
            confidence = min(1.0, metrics.interaction_count / 20)

            # Get previous level
            previous = await self._get_previous_level(user_id)

            # Calculate progress to next level
            progress = self._calculate_progress(weighted_score, current_level)

            # Generate recommendations
            strengths, improvements, recommendations = self._generate_recommendations(
                metrics, current_level
            )

            # Create assessment
            assessment = LevelAssessment(
                user_id=user_id,
                current_level=current_level,
                previous_level=previous,
                confidence=confidence,
                progress_to_next=progress,
                metrics=metrics,
                strengths=strengths,
                areas_to_improve=improvements,
                recommendations=recommendations,
                next_assessment=datetime.utcnow() + timedelta(days=7),
            )

            # Save assessment
            await self._save_assessment(assessment)

            # Record level change if different
            if previous and previous != current_level:
                await self._record_level_change(
                    user_id, current_level, previous, confidence
                )

            return assessment

        except Exception as e:
            logger.error(f"Failed to assess user {user_id}: {e}")
            # Return default assessment
            return LevelAssessment(
                user_id=user_id,
                current_level=CEFRLevel.B1,
                confidence=0.0,
            )

    async def _calculate_metrics(
        self,
        user_id: str,
        days: int,
    ) -> AssessmentMetrics:
        """Calculate assessment metrics from interactions."""
        try:
            db = await self._get_db()
            cutoff = datetime.utcnow() - timedelta(days=days)

            # Aggregate interaction data
            pipeline = [
                {"$match": {"user_id": user_id, "timestamp": {"$gte": cutoff}}},
                {
                    "$group": {
                        "_id": None,
                        "total": {"$sum": 1},
                        "avg_fluency": {"$avg": "$analysis.fluency_score"},
                        "error_count": {
                            "$sum": {"$size": {"$ifNull": ["$analysis.grammar_errors", []]}}
                        },
                        "vocab_levels": {"$push": "$analysis.vocabulary_level"},
                    }
                },
            ]

            cursor = db["ai_interactions"].aggregate(pipeline)
            result = None
            async for doc in cursor:
                result = doc

            if not result or result["total"] == 0:
                return AssessmentMetrics()

            total = result["total"]

            # Grammar accuracy: 1 - (errors per interaction / max expected)
            error_rate = result["error_count"] / total
            grammar_accuracy = max(0.0, 1.0 - (error_rate / 5.0))  # Normalize

            # Vocabulary complexity from levels
            vocab_score = self._calculate_vocab_score(result.get("vocab_levels", []))

            # Fluency from average
            fluency = result.get("avg_fluency", 0.5) or 0.5

            # Error trend
            trend = await self._calculate_error_trend(user_id, days)

            return AssessmentMetrics(
                grammar_accuracy=grammar_accuracy,
                vocabulary_complexity=vocab_score,
                fluency_score=fluency,
                consistency_score=0.8,  # TODO: Calculate from session regularity
                interaction_count=total,
                error_trend=trend,
            )

        except Exception as e:
            logger.error(f"Failed to calculate metrics: {e}")
            return AssessmentMetrics()

    def _calculate_vocab_score(self, levels: List[str]) -> float:
        """Calculate vocabulary complexity score from level distribution."""
        if not levels:
            return 0.5

        level_scores = {
            "A1": 0.1, "A2": 0.25, "B1": 0.45,
            "B2": 0.65, "C1": 0.85, "C2": 1.0,
        }

        scores = [level_scores.get(lvl, 0.5) for lvl in levels]
        return sum(scores) / len(scores)

    async def _calculate_error_trend(self, user_id: str, days: int) -> str:
        """Calculate if errors are improving, stable, or declining."""
        try:
            db = await self._get_db()
            cutoff = datetime.utcnow() - timedelta(days=days)
            midpoint = datetime.utcnow() - timedelta(days=days // 2)

            # Compare first half vs second half error rates
            pipeline = [
                {"$match": {"user_id": user_id, "timestamp": {"$gte": cutoff}}},
                {
                    "$group": {
                        "_id": {"$cond": [{"$gte": ["$timestamp", midpoint]}, "recent", "old"]},
                        "avg_errors": {
                            "$avg": {"$size": {"$ifNull": ["$analysis.grammar_errors", []]}}
                        },
                    }
                },
            ]

            cursor = db["ai_interactions"].aggregate(pipeline)
            results = {}
            async for doc in cursor:
                results[doc["_id"]] = doc["avg_errors"]

            old_errors = results.get("old", 0)
            recent_errors = results.get("recent", 0)

            if old_errors == 0:
                return "stable"

            change = (old_errors - recent_errors) / old_errors

            if change > 0.15:
                return "improving"
            elif change < -0.15:
                return "declining"
            return "stable"

        except Exception:
            return "stable"

    def _calculate_weighted_score(self, metrics: AssessmentMetrics) -> float:
        """Calculate weighted score from metrics."""
        return (
            metrics.grammar_accuracy * self.WEIGHT_GRAMMAR +
            metrics.vocabulary_complexity * self.WEIGHT_VOCABULARY +
            metrics.fluency_score * self.WEIGHT_FLUENCY
        )

    def _score_to_cefr(self, score: float) -> CEFRLevel:
        """Convert weighted score to CEFR level."""
        level = CEFRLevel.A1
        for threshold, cefr in CEFR_THRESHOLDS.items():
            if score >= threshold:
                level = cefr
        return level

    def _calculate_progress(self, score: float, current: CEFRLevel) -> float:
        """Calculate progress to next level."""
        thresholds = list(CEFR_THRESHOLDS.keys())
        levels = list(CEFR_THRESHOLDS.values())

        current_idx = levels.index(current)
        if current_idx >= len(levels) - 1:
            return 1.0  # Already at max

        current_threshold = thresholds[current_idx]
        next_threshold = thresholds[current_idx + 1]

        if next_threshold == current_threshold:
            return 0.0

        progress = (score - current_threshold) / (next_threshold - current_threshold)
        return max(0.0, min(1.0, progress))

    def _generate_recommendations(
        self,
        metrics: AssessmentMetrics,
        level: CEFRLevel,
    ) -> Tuple[List[str], List[str], List[str]]:
        """Generate strengths, areas to improve, and recommendations."""
        strengths = []
        improvements = []
        recommendations = []

        # Analyze grammar
        if metrics.grammar_accuracy >= 0.85:
            strengths.append("Strong grammar skills")
        elif metrics.grammar_accuracy < 0.60:
            improvements.append("Grammar accuracy")
            recommendations.append("Focus on verb tenses and articles")

        # Analyze vocabulary
        if metrics.vocabulary_complexity >= 0.70:
            strengths.append("Rich vocabulary")
        elif metrics.vocabulary_complexity < 0.40:
            improvements.append("Vocabulary range")
            recommendations.append("Learn new words in context")

        # Analyze fluency
        if metrics.fluency_score >= 0.80:
            strengths.append("Good fluency")
        elif metrics.fluency_score < 0.50:
            improvements.append("Speaking fluency")
            recommendations.append("Practice speaking exercises")

        # Error trend
        if metrics.error_trend == "improving":
            strengths.append("Showing improvement")
        elif metrics.error_trend == "declining":
            recommendations.append("Review previous errors")

        # Level-specific recommendations
        if level in [CEFRLevel.A1, CEFRLevel.A2]:
            recommendations.append("Practice basic sentence structures")
        elif level in [CEFRLevel.B1, CEFRLevel.B2]:
            recommendations.append("Work on complex sentences and idioms")

        return strengths, improvements, recommendations

    async def _get_recent_assessment(self, user_id: str) -> Optional[LevelAssessment]:
        """Get assessment if done within last 24 hours."""
        try:
            db = await self._get_db()
            cutoff = datetime.utcnow() - timedelta(hours=24)

            doc = await db[self.COLLECTION_ASSESSMENTS].find_one(
                {"user_id": user_id, "assessed_at": {"$gte": cutoff}},
                sort=[("assessed_at", -1)],
            )

            if doc:
                doc.pop("_id", None)
                return LevelAssessment(**doc)
            return None

        except Exception:
            return None

    async def _get_previous_level(self, user_id: str) -> Optional[CEFRLevel]:
        """Get user's previous level."""
        try:
            db = await self._get_db()

            doc = await db[self.COLLECTION_HISTORY].find_one(
                {"user_id": user_id},
                sort=[("changed_at", -1)],
            )

            if doc:
                return CEFRLevel(doc["level"])
            return None

        except Exception:
            return None

    async def _save_assessment(self, assessment: LevelAssessment):
        """Save assessment to database."""
        try:
            db = await self._get_db()

            await db[self.COLLECTION_ASSESSMENTS].update_one(
                {"user_id": assessment.user_id},
                {"$set": assessment.model_dump(mode="json")},
                upsert=True,
            )

        except Exception as e:
            logger.error(f"Failed to save assessment: {e}")

    async def _record_level_change(
        self,
        user_id: str,
        new_level: CEFRLevel,
        old_level: CEFRLevel,
        confidence: float,
    ):
        """Record level change in history."""
        try:
            db = await self._get_db()

            direction = "promoted" if new_level > old_level else "adjusted"
            history = LevelHistory(
                user_id=user_id,
                level=new_level,
                changed_at=datetime.utcnow(),
                reason=f"{direction} from {old_level.value} to {new_level.value}",
                confidence=confidence,
            )

            await db[self.COLLECTION_HISTORY].insert_one(history.model_dump())
            logger.info(f"User {user_id} level changed: {old_level} → {new_level}")

        except Exception as e:
            logger.error(f"Failed to record level change: {e}")

    async def get_level_history(
        self,
        user_id: str,
        limit: int = 10,
    ) -> List[LevelHistory]:
        """Get user's level change history."""
        try:
            db = await self._get_db()

            cursor = (
                db[self.COLLECTION_HISTORY]
                .find({"user_id": user_id})
                .sort("changed_at", -1)
                .limit(limit)
            )

            history = []
            async for doc in cursor:
                doc.pop("_id", None)
                history.append(LevelHistory(**doc))

            return history

        except Exception as e:
            logger.error(f"Failed to get level history: {e}")
            return []


# ============================================================
# SINGLETON
# ============================================================

_service: Optional[AssessmentService] = None


def get_assessment_service() -> AssessmentService:
    """Get or create AssessmentService singleton."""
    global _service
    if _service is None:
        _service = AssessmentService()
    return _service
