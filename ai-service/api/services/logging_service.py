"""
Logging Service

Centralized service for logging AI interactions to MongoDB.
Follows the schema defined in docs/MONGODB_SCHEMA.md.
"""

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from api.core.database import get_database

logger = logging.getLogger(__name__)


# ============================================================
# PYDANTIC MODELS (matching MONGODB_SCHEMA.md)
# ============================================================


class GrammarError(BaseModel):
    """Grammar error detected in user input."""
    type: str = Field(..., description="Error type: verb_tense, article, etc.")
    error: str = Field(..., description="The incorrect text")
    correction: str = Field(..., description="The correct text")
    explanation: str = Field(default="", description="Why it's wrong")
    severity: str = Field(default="moderate", description="minor/moderate/critical")


class PronunciationError(BaseModel):
    """Pronunciation error from audio analysis."""
    phoneme: str = Field(..., description="IPA phoneme like /θ/")
    expected: str = Field(..., description="Expected phoneme")
    actual: str = Field(..., description="What user said")
    position: int = Field(default=0, description="Word position")
    word: str = Field(default="", description="Word containing error")


class VocabularySuggestion(BaseModel):
    """Vocabulary suggestion for improvement."""
    word: str
    usage: str
    level: str = Field(default="B1", description="CEFR level")


class UserInput(BaseModel):
    """User input data."""
    text: str
    audio_features: Optional[Dict[str, Any]] = None
    context: List[str] = Field(default_factory=list)


class ProcessingTime(BaseModel):
    """Processing time breakdown in milliseconds."""
    stt: int = 0
    qwen: int = 0
    hubert: int = 0
    llama3: int = 0
    total: int = 0


class AnalysisResult(BaseModel):
    """AI analysis results."""
    fluency_score: float = 0.0
    vocabulary_level: str = "B1"
    grammar_errors: List[GrammarError] = Field(default_factory=list)
    pronunciation_errors: Optional[List[PronunciationError]] = None
    vocabulary_suggestions: List[VocabularySuggestion] = Field(default_factory=list)
    tutor_response: str = ""
    tutor_response_vi: Optional[str] = None


class UserFeedback(BaseModel):
    """User feedback for learning loop."""
    helpful: Optional[bool] = None
    correction: Optional[str] = None
    rating: Optional[int] = None
    submitted_at: Optional[datetime] = None


class AIInteraction(BaseModel):
    """Full AI interaction log document."""
    session_id: str
    user_id: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    user_input: UserInput
    models_used: List[str] = Field(default_factory=list)
    processing_time_ms: ProcessingTime = Field(default_factory=ProcessingTime)
    analysis: AnalysisResult = Field(default_factory=AnalysisResult)
    user_feedback: Optional[UserFeedback] = None

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }


class ModelMetric(BaseModel):
    """Model performance metric document."""
    date: datetime = Field(default_factory=datetime.utcnow)
    model_name: str
    avg_latency_ms: float = 0.0
    p95_latency_ms: float = 0.0
    p99_latency_ms: float = 0.0
    requests_count: int = 0
    error_rate: float = 0.0
    cache_hit_rate: float = 0.0
    avg_confidence: float = 0.0
    gpu_percent: float = 0.0
    ram_gb: float = 0.0
    cpu_percent: float = 0.0


# ============================================================
# LOGGING SERVICE
# ============================================================


class LoggingService:
    """
    Centralized logging service for AI interactions.

    Writes to MongoDB collections:
    - ai_interactions: Full interaction logs
    - model_metrics: Performance tracking
    - learning_patterns: Aggregated user patterns
    """

    COLLECTION_INTERACTIONS = "ai_interactions"
    COLLECTION_METRICS = "model_metrics"
    COLLECTION_PATTERNS = "learning_patterns"
    COLLECTION_TRAINING = "training_queue"

    def __init__(self):
        self._db = None

    async def _get_db(self):
        """Get database connection (lazy init)."""
        if self._db is None:
            self._db = await get_database()
        return self._db

    async def log_interaction(
        self,
        session_id: str,
        user_id: str,
        user_input: str,
        context: List[str],
        models_used: List[str],
        processing_time_ms: Dict[str, int],
        analysis: Dict[str, Any],
        audio_features: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        Log an AI interaction to MongoDB.

        Args:
            session_id: Conversation session ID
            user_id: User identifier
            user_input: User's text input
            context: Last conversation turns
            models_used: List of models used
            processing_time_ms: Latency breakdown
            analysis: AI analysis results
            audio_features: Optional HuBERT features

        Returns:
            Inserted document ID as string
        """
        try:
            db = await self._get_db()

            # Build document
            interaction = AIInteraction(
                session_id=session_id,
                user_id=user_id,
                user_input=UserInput(
                    text=user_input,
                    audio_features=audio_features,
                    context=context[-5:] if context else [],
                ),
                models_used=models_used,
                processing_time_ms=ProcessingTime(**processing_time_ms),
                analysis=AnalysisResult(
                    fluency_score=analysis.get("fluency_score", 0.0),
                    vocabulary_level=analysis.get("vocabulary_level", "B1"),
                    grammar_errors=[
                        GrammarError(**err)
                        for err in analysis.get("grammar_errors", [])
                    ],
                    pronunciation_errors=[
                        PronunciationError(**err)
                        for err in analysis.get("pronunciation_errors", [])
                    ] if analysis.get("pronunciation_errors") else None,
                    vocabulary_suggestions=[
                        VocabularySuggestion(**sug)
                        for sug in analysis.get("vocabulary_suggestions", [])
                    ],
                    tutor_response=analysis.get("tutor_response", ""),
                    tutor_response_vi=analysis.get("tutor_response_vi"),
                ),
            )

            # Insert to MongoDB
            result = await db[self.COLLECTION_INTERACTIONS].insert_one(
                interaction.model_dump(by_alias=True)
            )

            logger.info(f"Logged interaction {result.inserted_id} for user {user_id}")
            return str(result.inserted_id)

        except Exception as e:
            logger.error(f"Failed to log interaction: {e}")
            # Don't raise - logging failure shouldn't break the main flow
            return ""

    async def log_feedback(
        self,
        interaction_id: str,
        helpful: Optional[bool] = None,
        correction: Optional[str] = None,
        rating: Optional[int] = None,
    ) -> bool:
        """
        Update an interaction with user feedback.

        Args:
            interaction_id: The interaction document ID
            helpful: Was the response helpful?
            correction: User's correction if AI was wrong
            rating: 1-5 star rating

        Returns:
            True if update successful
        """
        try:
            from bson import ObjectId

            db = await self._get_db()

            feedback = UserFeedback(
                helpful=helpful,
                correction=correction,
                rating=rating,
                submitted_at=datetime.utcnow(),
            )

            result = await db[self.COLLECTION_INTERACTIONS].update_one(
                {"_id": ObjectId(interaction_id)},
                {"$set": {"user_feedback": feedback.model_dump()}},
            )

            if result.modified_count > 0:
                logger.info(f"Updated feedback for interaction {interaction_id}")
                return True

            logger.warning(f"Interaction {interaction_id} not found for feedback")
            return False

        except Exception as e:
            logger.error(f"Failed to log feedback: {e}")
            return False

    async def log_model_metric(
        self,
        model_name: str,
        latency_ms: float,
        success: bool = True,
        cache_hit: bool = False,
        confidence: float = 1.0,
    ) -> None:
        """
        Log a model performance metric.

        This is called on every model invocation to track performance.
        Metrics are aggregated daily by a background job.

        Args:
            model_name: Name of the model
            latency_ms: Response latency in milliseconds
            success: Whether the request succeeded
            cache_hit: Whether response was cached
            confidence: Model confidence score
        """
        try:
            db = await self._get_db()

            # Use today's date as aggregation key
            today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

            # Upsert daily aggregation
            await db[self.COLLECTION_METRICS].update_one(
                {"date": today, "model_name": model_name},
                {
                    "$inc": {
                        "metrics.requests_count": 1,
                        "metrics.total_latency_ms": latency_ms,
                        "metrics.error_count": 0 if success else 1,
                        "metrics.cache_hits": 1 if cache_hit else 0,
                        "metrics.total_confidence": confidence,
                    },
                    "$push": {
                        "latencies": {
                            "$each": [latency_ms],
                            "$slice": -1000,  # Keep last 1000 for percentile calc
                        }
                    },
                    "$setOnInsert": {
                        "date": today,
                        "model_name": model_name,
                    },
                },
                upsert=True,
            )

        except Exception as e:
            logger.error(f"Failed to log model metric: {e}")

    async def get_user_interactions(
        self,
        user_id: str,
        limit: int = 50,
        skip: int = 0,
    ) -> List[Dict[str, Any]]:
        """
        Get user's recent interactions.

        Args:
            user_id: User identifier
            limit: Max number of results
            skip: Number to skip (for pagination)

        Returns:
            List of interaction documents
        """
        try:
            db = await self._get_db()

            cursor = (
                db[self.COLLECTION_INTERACTIONS]
                .find({"user_id": user_id})
                .sort("timestamp", -1)
                .skip(skip)
                .limit(limit)
            )

            interactions = []
            async for doc in cursor:
                doc["_id"] = str(doc["_id"])
                interactions.append(doc)

            return interactions

        except Exception as e:
            logger.error(f"Failed to get user interactions: {e}")
            return []

    async def get_user_error_patterns(
        self,
        user_id: str,
        days: int = 30,
    ) -> Dict[str, Any]:
        """
        Aggregate user's error patterns over time.

        Args:
            user_id: User identifier
            days: Number of days to analyze

        Returns:
            Aggregated error patterns with counts and trends
        """
        try:
            db = await self._get_db()

            from datetime import timedelta

            cutoff = datetime.utcnow() - timedelta(days=days)

            pipeline = [
                {
                    "$match": {
                        "user_id": user_id,
                        "timestamp": {"$gte": cutoff},
                    }
                },
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

            cursor = db[self.COLLECTION_INTERACTIONS].aggregate(pipeline)
            errors = []
            async for doc in cursor:
                errors.append({
                    "type": doc["_id"],
                    "frequency": doc["count"],
                    "examples": doc["examples"][:5],  # Top 5 examples
                })

            return {
                "user_id": user_id,
                "period_days": days,
                "common_errors": errors,
                "analyzed_at": datetime.utcnow().isoformat(),
            }

        except Exception as e:
            logger.error(f"Failed to get error patterns: {e}")
            return {"user_id": user_id, "common_errors": [], "error": str(e)}


# ============================================================
# SINGLETON INSTANCE
# ============================================================

_logging_service: Optional[LoggingService] = None


def get_logging_service() -> LoggingService:
    """Get or create the LoggingService singleton."""
    global _logging_service
    if _logging_service is None:
        _logging_service = LoggingService()
    return _logging_service
