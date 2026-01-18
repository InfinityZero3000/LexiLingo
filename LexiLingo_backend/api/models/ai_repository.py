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
    
    Enhanced for ML training pipeline:
    - Comprehensive interaction logging
    - Feedback collection
    - Training example curation
    - Error pattern analysis
    """
    
    def __init__(self, db: AsyncIOMotorDatabase):
        """Initialize repository with database."""
        self.db = db
        self.interactions = db["ai_interactions"]
        self.feedback = db["user_feedback"]
        self.training_queue = db["training_queue"]
        self.user_progress = db["user_progress"]
        self.error_patterns = db["error_patterns"]
        self.model_metrics = db["model_metrics"]
    
    async def log_interaction(
        self,
        request: LogInteractionRequest
    ) -> str:
        """
        Log AI interaction to database with enhanced metadata for training.
        
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
                "user_feedback": request.user_feedback,
                # Enhanced metadata for training
                "quality_indicators": {
                    "has_grammar_errors": len(request.analysis.grammar_errors) > 0,
                    "error_count": len(request.analysis.grammar_errors),
                    "fluency_score": request.analysis.fluency_score,
                    "vocabulary_level": request.analysis.vocabulary_level,
                    "has_pronunciation": request.analysis.pronunciation_errors is not None
                },
                "training_eligible": True,  # Can be used for training
                "training_validated": False,  # Needs validation
                "indexed_at": datetime.utcnow()
            }
            
            result = await self.interactions.insert_one(document)
            logger.info(f"Logged interaction: {result.inserted_id}")
            
            # Auto-add high-quality examples to training queue
            await self._auto_queue_training_example(str(result.inserted_id), document)
            
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
            cursor = self.interactions.find(
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
            cursor = self.interactions.find(
                {"session_id": session_id}
            ).sort("timestamp", 1)
            
            interactions = await cursor.to_list(length=None)
            
            for interaction in interactions:
                interaction["_id"] = str(interaction["_id"])
            
            return interactions
            
        except Exception as e:
            logger.error(f"Failed to get session interactions: {e}")
            return []
    
    # ============================================================
    # Feedback Collection
    # ============================================================
    
    async def submit_feedback(
        self,
        interaction_id: str,
        user_id: str,
        rating: int,
        helpful: bool,
        accurate: bool,
        feedback_text: Optional[str] = None,
        reported_issues: List[str] = []
    ) -> str:
        """
        Submit user feedback on AI response.
        
        This is CRITICAL for training data curation.
        """
        try:
            feedback_doc = {
                "interaction_id": interaction_id,
                "user_id": user_id,
                "rating": rating,
                "helpful": helpful,
                "accurate": accurate,
                "feedback_text": feedback_text,
                "reported_issues": reported_issues,
                "timestamp": datetime.utcnow()
            }
            
            result = await self.feedback.insert_one(feedback_doc)
            
            # Update interaction with feedback reference
            await self.interactions.update_one(
                {"_id": ObjectId(interaction_id)},
                {
                    "$set": {
                        "user_feedback": feedback_doc,
                        "quality_score": self._calculate_quality_score(rating, helpful, accurate)
                    }
                }
            )
            
            # If low rating, flag for review
            if rating <= 2 or not accurate:
                await self._flag_for_review(interaction_id, reported_issues)
            
            logger.info(f"Feedback submitted: {result.inserted_id}")
            return str(result.inserted_id)
            
        except Exception as e:
            logger.error(f"Failed to submit feedback: {e}")
            raise
    
    # ============================================================
    # Training Queue Management
    # ============================================================
    
    async def add_to_training_queue(
        self,
        interaction_id: str,
        task_types: List[str],
        quality_score: float = 1.0,
        notes: Optional[str] = None
    ) -> str:
        """
        Add interaction to training queue for LoRA fine-tuning.
        
        This curates high-quality examples for model improvement.
        """
        try:
            # Get interaction data
            interaction = await self.interactions.find_one({"_id": ObjectId(interaction_id)})
            if not interaction:
                raise ValueError(f"Interaction {interaction_id} not found")
            
            # Create training example for each task type
            example_doc = {
                "source_interaction_id": interaction_id,
                "user_id": interaction["user_id"],
                "user_input": interaction["user_input"]["text"],
                "expected_output": interaction["analysis"],
                "task_types": task_types,
                "difficulty_level": interaction["analysis"]["vocabulary_level"],
                "quality_score": quality_score,
                "validated": False,
                "validated_by": None,
                "notes": notes,
                "created_at": datetime.utcnow(),
                "used_in_training": False
            }
            
            result = await self.training_queue.insert_one(example_doc)
            
            # Mark interaction as queued for training
            await self.interactions.update_one(
                {"_id": ObjectId(interaction_id)},
                {"$set": {"in_training_queue": True}}
            )
            
            logger.info(f"Added to training queue: {result.inserted_id}")
            return str(result.inserted_id)
            
        except Exception as e:
            logger.error(f"Failed to add to training queue: {e}")
            raise
    
    async def get_training_queue(
        self,
        task_type: Optional[str] = None,
        validated_only: bool = False,
        min_quality_score: float = 0.7,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Get training examples from queue."""
        try:
            query = {
                "quality_score": {"$gte": min_quality_score},
                "used_in_training": False
            }
            
            if task_type:
                query["task_types"] = task_type
            
            if validated_only:
                query["validated"] = True
            
            cursor = self.training_queue.find(query).sort("quality_score", -1).limit(limit)
            examples = await cursor.to_list(length=limit)
            
            for example in examples:
                example["_id"] = str(example["_id"])
            
            return examples
            
        except Exception as e:
            logger.error(f"Failed to get training queue: {e}")
            return []
    
    async def validate_training_example(
        self,
        example_id: str,
        validated_by: str,
        approved: bool,
        notes: Optional[str] = None
    ) -> bool:
        """Validate a training example (human-in-the-loop)."""
        try:
            update = {
                "$set": {
                    "validated": approved,
                    "validated_by": validated_by,
                    "validation_notes": notes,
                    "validated_at": datetime.utcnow()
                }
            }
            
            result = await self.training_queue.update_one(
                {"_id": ObjectId(example_id)},
                update
            )
            
            return result.modified_count > 0
            
        except Exception as e:
            logger.error(f"Failed to validate training example: {e}")
            return False
    
    # ============================================================
    # User Progress Tracking
    # ============================================================
    
    async def save_progress_snapshot(
        self,
        user_id: str,
        level: str,
        fluency_score_avg: float,
        grammar_accuracy: float,
        vocabulary_count: int,
        pronunciation_score_avg: Optional[float] = None,
        total_interactions: int = 0,
        study_streak_days: int = 0,
        common_errors: List[Dict[str, Any]] = []
    ) -> str:
        """Save user progress snapshot for tracking improvement."""
        try:
            snapshot = {
                "user_id": user_id,
                "snapshot_date": datetime.utcnow(),
                "level": level,
                "fluency_score_avg": fluency_score_avg,
                "grammar_accuracy": grammar_accuracy,
                "vocabulary_count": vocabulary_count,
                "pronunciation_score_avg": pronunciation_score_avg,
                "total_interactions": total_interactions,
                "study_streak_days": study_streak_days,
                "common_errors": common_errors,
                "improvement_trend": await self._calculate_trend(user_id)
            }
            
            result = await self.user_progress.insert_one(snapshot)
            logger.info(f"Progress snapshot saved: {result.inserted_id}")
            return str(result.inserted_id)
            
        except Exception as e:
            logger.error(f"Failed to save progress snapshot: {e}")
            raise
    
    async def get_user_progress_history(
        self,
        user_id: str,
        days: int = 30
    ) -> List[Dict[str, Any]]:
        """Get user progress history."""
        try:
            cutoff_date = datetime.utcnow() - timedelta(days=days)
            
            cursor = self.user_progress.find({
                "user_id": user_id,
                "snapshot_date": {"$gte": cutoff_date}
            }).sort("snapshot_date", 1)
            
            snapshots = await cursor.to_list(length=None)
            
            for snapshot in snapshots:
                snapshot["_id"] = str(snapshot["_id"])
            
            return snapshots
            
        except Exception as e:
            logger.error(f"Failed to get progress history: {e}")
            return []
    
    # ============================================================
    # Error Pattern Analysis
    # ============================================================
    
    async def update_feedback(
        self,
        interaction_id: str,
        feedback: Dict[str, Any]
    ) -> bool:
        """Update interaction with user feedback."""
        try:
            result = await self.interactions.update_one(
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
            
            results = await self.interactions.aggregate(pipeline).to_list(None)
            return results
            
        except Exception as e:
            logger.error(f"Failed to get error stats: {e}")
            return []
    
    async def detect_error_patterns(
        self,
        min_frequency: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Detect common error patterns across all users.
        
        This helps identify systematic issues for model improvement.
        """
        try:
            cutoff_date = datetime.utcnow() - timedelta(days=7)  # Last week
            
            pipeline = [
                {
                    "$match": {
                        "timestamp": {"$gte": cutoff_date},
                        "quality_indicators.has_grammar_errors": True
                    }
                },
                {
                    "$unwind": "$analysis.grammar_errors"
                },
                {
                    "$group": {
                        "_id": {
                            "type": "$analysis.grammar_errors.type",
                            "level": "$analysis.vocabulary_level"
                        },
                        "count": {"$sum": 1},
                        "users": {"$addToSet": "$user_id"},
                        "examples": {
                            "$push": {
                                "error": "$analysis.grammar_errors.error",
                                "correction": "$analysis.grammar_errors.correction"
                            }
                        }
                    }
                },
                {
                    "$match": {
                        "count": {"$gte": min_frequency}
                    }
                },
                {
                    "$sort": {"count": -1}
                },
                {
                    "$limit": 50
                }
            ]
            
            patterns = await self.interactions.aggregate(pipeline).to_list(None)
            
            # Save detected patterns
            for pattern in patterns:
                await self.error_patterns.update_one(
                    {
                        "error_type": pattern["_id"]["type"],
                        "level": pattern["_id"]["level"]
                    },
                    {
                        "$set": {
                            "frequency": pattern["count"],
                            "affected_users": pattern["users"],
                            "example_errors": [e["error"] for e in pattern["examples"][:10]],
                            "detected_at": datetime.utcnow()
                        }
                    },
                    upsert=True
                )
            
            return patterns
            
        except Exception as e:
            logger.error(f"Failed to detect error patterns: {e}")
            return []
    
    # ============================================================
    # Analytics & Metrics
    # ============================================================
    
    async def get_analytics(
        self,
        user_id: Optional[str] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        metric: str = "fluency"
    ) -> Dict[str, Any]:
        """Get analytics data."""
        try:
            query = {}
            
            if user_id:
                query["user_id"] = user_id
            
            if start_date:
                query["timestamp"] = {"$gte": start_date}
            
            if end_date:
                query.setdefault("timestamp", {})["$lte"] = end_date
            
            # Get aggregated metrics
            if metric == "fluency":
                pipeline = [
                    {"$match": query},
                    {
                        "$group": {
                            "_id": {
                                "$dateToString": {
                                    "format": "%Y-%m-%d",
                                    "date": "$timestamp"
                                }
                            },
                            "avg_score": {"$avg": "$analysis.fluency_score"},
                            "count": {"$sum": 1}
                        }
                    },
                    {"$sort": {"_id": 1}}
                ]
            elif metric == "grammar":
                pipeline = [
                    {"$match": query},
                    {
                        "$group": {
                            "_id": {
                                "$dateToString": {
                                    "format": "%Y-%m-%d",
                                    "date": "$timestamp"
                                }
                            },
                            "total_errors": {"$sum": "$quality_indicators.error_count"},
                            "count": {"$sum": 1}
                        }
                    },
                    {"$sort": {"_id": 1}}
                ]
            else:
                pipeline = [
                    {"$match": query},
                    {"$count": "total"}
                ]
            
            results = await self.interactions.aggregate(pipeline).to_list(None)
            
            # Calculate summary
            summary = self._calculate_summary(results, metric)
            
            return {
                "metric": metric,
                "data": results,
                "summary": summary
            }
            
        except Exception as e:
            logger.error(f"Failed to get analytics: {e}")
            return {"metric": metric, "data": [], "summary": {}}
    
    # ============================================================
    # Helper Methods
    # ============================================================
    
    async def _auto_queue_training_example(
        self,
        interaction_id: str,
        interaction: Dict[str, Any]
    ):
        """Auto-queue high-quality examples for training."""
        try:
            # Criteria for auto-queuing:
            # 1. Has grammar errors (good for grammar task)
            # 2. High fluency score (good for fluency task)
            # 3. Complex vocabulary (good for vocabulary task)
            
            task_types = []
            quality_score = 0.5  # Base score
            
            analysis = interaction["analysis"]
            
            # Grammar task
            if 0 < len(analysis.get("grammar_errors", [])) <= 3:
                task_types.append("grammar")
                quality_score += 0.2
            
            # Fluency task
            if analysis.get("fluency_score", 0) >= 0.7:
                task_types.append("fluency")
                quality_score += 0.2
            
            # Vocabulary task
            level = analysis.get("vocabulary_level", "B1")
            if level in ["B2", "C1"]:
                task_types.append("vocabulary")
                quality_score += 0.1
            
            # Auto-queue if quality score is high enough
            if quality_score >= 0.8 and task_types:
                await self.add_to_training_queue(
                    interaction_id=interaction_id,
                    task_types=task_types,
                    quality_score=quality_score,
                    notes="Auto-queued based on quality indicators"
                )
                
        except Exception as e:
            logger.warning(f"Failed to auto-queue training example: {e}")
    
    def _calculate_quality_score(
        self,
        rating: int,
        helpful: bool,
        accurate: bool
    ) -> float:
        """Calculate quality score from user feedback."""
        score = rating / 5.0  # Normalize to 0-1
        
        if helpful:
            score += 0.1
        
        if accurate:
            score += 0.2
        
        return min(score, 1.0)
    
    async def _flag_for_review(
        self,
        interaction_id: str,
        reported_issues: List[str]
    ):
        """Flag interaction for human review."""
        try:
            await self.interactions.update_one(
                {"_id": ObjectId(interaction_id)},
                {
                    "$set": {
                        "flagged_for_review": True,
                        "reported_issues": reported_issues,
                        "training_eligible": False
                    }
                }
            )
        except Exception as e:
            logger.warning(f"Failed to flag for review: {e}")
    
    async def _calculate_trend(self, user_id: str) -> str:
        """Calculate improvement trend."""
        try:
            # Get last 3 snapshots
            cursor = self.user_progress.find({
                "user_id": user_id
            }).sort("snapshot_date", -1).limit(3)
            
            snapshots = await cursor.to_list(length=3)
            
            if len(snapshots) < 2:
                return "stable"
            
            # Compare fluency scores
            recent = snapshots[0]["fluency_score_avg"]
            older = snapshots[-1]["fluency_score_avg"]
            
            diff = recent - older
            
            if diff > 0.1:
                return "improving"
            elif diff < -0.1:
                return "declining"
            else:
                return "stable"
                
        except Exception as e:
            logger.warning(f"Failed to calculate trend: {e}")
            return "stable"
    
    def _calculate_summary(
        self,
        results: List[Dict[str, Any]],
        metric: str
    ) -> Dict[str, Any]:
        """Calculate summary statistics."""
        if not results:
            return {}
        
        if metric == "fluency":
            avg_scores = [r["avg_score"] for r in results]
            return {
                "overall_avg": sum(avg_scores) / len(avg_scores),
                "min": min(avg_scores),
                "max": max(avg_scores),
                "total_interactions": sum(r["count"] for r in results)
            }
        elif metric == "grammar":
            return {
                "total_errors": sum(r["total_errors"] for r in results),
                "total_interactions": sum(r["count"] for r in results),
                "avg_errors_per_interaction": sum(r["total_errors"] for r in results) / sum(r["count"] for r in results)
            }
        else:
            return {}
