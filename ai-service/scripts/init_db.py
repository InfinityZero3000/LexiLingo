"""
MongoDB Database Initialization Script

Creates collections, indexes, and initial data for LexiLingo
Run this after MongoDB connection is established
"""

import asyncio
import logging
from datetime import datetime
from motor.motor_asyncio import AsyncIOMotorClient

from api.core.config import settings

logger = logging.getLogger(__name__)


async def init_database():
    """
    Initialize MongoDB database with collections and indexes.
    
    This ensures optimal query performance for training pipeline.
    """
    try:
        # Connect to MongoDB
        client = AsyncIOMotorClient(settings.MONGODB_URI)
        db = client[settings.MONGODB_DATABASE]
        
        logger.info("Initializing MongoDB collections and indexes...")
        
        # ============================================================
        # AI Interactions Collection
        # ============================================================
        interactions = db["ai_interactions"]
        
        # Indexes for common queries
        await interactions.create_index("user_id")
        await interactions.create_index("session_id")
        await interactions.create_index("timestamp")
        await interactions.create_index([("timestamp", -1)])  # Descending
        await interactions.create_index("training_eligible")
        await interactions.create_index("quality_score")
        await interactions.create_index([
            ("user_id", 1),
            ("timestamp", -1)
        ])
        
        # TTL index for auto-cleanup (90 days retention)
        await interactions.create_index(
            "indexed_at",
            expireAfterSeconds=90 * 24 * 60 * 60  # 90 days
        )
        
        logger.info("✓ ai_interactions collection indexed")
        
        # ============================================================
        # User Feedback Collection
        # ============================================================
        feedback = db["user_feedback"]
        
        await feedback.create_index("interaction_id")
        await feedback.create_index("user_id")
        await feedback.create_index("timestamp")
        await feedback.create_index([("rating", -1)])
        await feedback.create_index([
            ("user_id", 1),
            ("timestamp", -1)
        ])
        
        logger.info("✓ user_feedback collection indexed")
        
        # ============================================================
        # Training Queue Collection
        # ============================================================
        training_queue = db["training_queue"]
        
        await training_queue.create_index("source_interaction_id")
        await training_queue.create_index("user_id")
        await training_queue.create_index("task_types")
        await training_queue.create_index("quality_score")
        await training_queue.create_index("validated")
        await training_queue.create_index("used_in_training")
        await training_queue.create_index([
            ("quality_score", -1),
            ("validated", 1)
        ])
        await training_queue.create_index([
            ("task_types", 1),
            ("quality_score", -1)
        ])
        
        logger.info("✓ training_queue collection indexed")
        
        # ============================================================
        # User Progress Collection
        # ============================================================
        user_progress = db["user_progress"]
        
        await user_progress.create_index("user_id")
        await user_progress.create_index("snapshot_date")
        await user_progress.create_index([
            ("user_id", 1),
            ("snapshot_date", -1)
        ])
        await user_progress.create_index("level")
        
        logger.info("✓ user_progress collection indexed")
        
        # ============================================================
        # Error Patterns Collection
        # ============================================================
        error_patterns = db["error_patterns"]
        
        await error_patterns.create_index("error_type")
        await error_patterns.create_index("level")
        await error_patterns.create_index("frequency")
        await error_patterns.create_index([
            ("error_type", 1),
            ("level", 1)
        ], unique=True)
        
        logger.info("✓ error_patterns collection indexed")
        
        # ============================================================
        # Model Metrics Collection
        # ============================================================
        model_metrics = db["model_metrics"]
        
        await model_metrics.create_index("model_name")
        await model_metrics.create_index("version")
        await model_metrics.create_index("timestamp")
        await model_metrics.create_index([
            ("model_name", 1),
            ("timestamp", -1)
        ])
        
        logger.info("✓ model_metrics collection indexed")
        
        # ============================================================
        # Chat Sessions Collection
        # ============================================================
        chat_sessions = db["chat_sessions"]
        
        await chat_sessions.create_index("session_id", unique=True)
        await chat_sessions.create_index("user_id")
        await chat_sessions.create_index("created_at")
        await chat_sessions.create_index([
            ("user_id", 1),
            ("last_activity", -1)
        ])
        
        logger.info("✓ chat_sessions collection indexed")
        
        # ============================================================
        # Chat Messages Collection
        # ============================================================
        chat_messages = db["chat_messages"]
        
        await chat_messages.create_index("session_id")
        await chat_messages.create_index("user_id")
        await chat_messages.create_index("timestamp")
        await chat_messages.create_index([
            ("session_id", 1),
            ("timestamp", 1)
        ])
        
        # TTL index (30 days retention)
        await chat_messages.create_index(
            "timestamp",
            expireAfterSeconds=30 * 24 * 60 * 60
        )
        
        logger.info("✓ chat_messages collection indexed")
        
        # ============================================================
        # Summary
        # ============================================================
        collections = await db.list_collection_names()
        logger.info(f"\n{'='*60}")
        logger.info(f"MongoDB Database Initialization Complete!")
        logger.info(f"Database: {settings.MONGODB_DATABASE}")
        logger.info(f"Collections created: {len(collections)}")
        logger.info(f"Collections: {', '.join(collections)}")
        logger.info(f"{'='*60}\n")
        
        # Close connection
        client.close()
        
        return True
        
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        return False


async def create_sample_data():
    """
    Create sample data for testing (optional).
    """
    try:
        client = AsyncIOMotorClient(settings.MONGODB_URI)
        db = client[settings.MONGODB_DATABASE]
        
        logger.info("Creating sample data...")
        
        # Sample interaction
        sample_interaction = {
            "session_id": "sample_session_1",
            "user_id": "sample_user_1",
            "timestamp": datetime.utcnow(),
            "user_input": {
                "text": "I go to school yesterday",
                "audio_features": None,
                "context": []
            },
            "models_used": ["qwen-unified"],
            "processing_time_ms": {"qwen": 120},
            "analysis": {
                "fluency_score": 0.75,
                "vocabulary_level": "A2",
                "grammar_errors": [
                    {
                        "type": "verb_tense",
                        "error": "go",
                        "correction": "went",
                        "explanation": "Use past tense 'went' for past actions",
                        "severity": "critical"
                    }
                ],
                "pronunciation_errors": None,
                "vocabulary_suggestions": [],
                "tutor_response": "Good try! Remember to use past tense 'went' instead of 'go' when talking about yesterday.",
                "tutor_response_vi": None
            },
            "user_feedback": None,
            "quality_indicators": {
                "has_grammar_errors": True,
                "error_count": 1,
                "fluency_score": 0.75,
                "vocabulary_level": "A2",
                "has_pronunciation": False
            },
            "training_eligible": True,
            "training_validated": False,
            "indexed_at": datetime.utcnow()
        }
        
        await db["ai_interactions"].insert_one(sample_interaction)
        logger.info("✓ Sample interaction created")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Failed to create sample data: {e}")


if __name__ == "__main__":
    # Run initialization
    asyncio.run(init_database())
    
    # Optionally create sample data
    # asyncio.run(create_sample_data())
