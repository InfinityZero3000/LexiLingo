"""Conversation History Resource"""

import json
import logging

logger = logging.getLogger(__name__)


async def get(session_id: str) -> str:
    """
    Get conversation history by session ID
    
    Returns JSON with:
    - session_id
    - messages: [{role, content, timestamp}]
    - context_embedding
    """
    logger.info(f"Fetching conversation history: session_id={session_id}")
    
    try:
        # TODO: Fetch from Redis/MongoDB
        # For now, return mock data
        history = {
            "session_id": session_id,
            "messages": [
                {
                    "role": "user",
                    "content": "Hello! Can you explain present perfect?",
                    "timestamp": "2026-01-31T10:30:00Z",
                },
                {
                    "role": "assistant",
                    "content": "Of course! Present perfect is used for...",
                    "timestamp": "2026-01-31T10:30:05Z",
                },
            ],
            "context_summary": "User is learning present perfect tense at B1 level",
        }
        
        return json.dumps(history, ensure_ascii=False)
    
    except Exception as e:
        logger.error(f"Error fetching conversation history: {e}")
        return json.dumps({"error": str(e), "session_id": session_id})
