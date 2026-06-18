"""Learner Profile Resource - Provides user profile and progress"""

import json
import logging

from resources.common import freshness, source, upstream_error
from utils.api_client import call_backend_service

logger = logging.getLogger(__name__)


async def get(user_id: str) -> str:
    """
    Get learner profile by user ID
    
    Returns JSON with:
    - user_id
    - level (CEFR)
    - weak_areas
    - preferences
    - progress
    """
    logger.info(f"Fetching learner profile: user_id={user_id}")
    
    try:
        user = await call_backend_service("GET", "/api/v1/users/me")
        if str(user.get("id")) != user_id:
            from utils.api_client import UpstreamServiceError

            raise UpstreamServiceError("backend-service", 403, False)
        stats_response = await call_backend_service("GET", "/api/v1/users/me/stats")
        stats = stats_response.get("data") or {}
        profile = {
            "user_id": user_id,
            "level": user.get("level") or user.get("cefr_level") or "A1",
            "weak_areas": [],
            "preferences": {
                "voice": None,
                "explanation_language": user.get("native_language"),
                "target_language": user.get("target_language"),
                "difficulty": None,
            },
            "progress": {
                "lessons_completed": stats.get("lessons_completed", 0),
                "total_study_time": stats.get("total_study_time", 0),
                "streak_days": stats.get("current_streak", 0),
            },
            "source": source("backend-service", "postgresql", "users"),
            "freshness": freshness(),
            "error": None,
        }
        return json.dumps(profile, ensure_ascii=False)

    except Exception as e:
        logger.error(f"Error fetching learner profile: {e}")
        return json.dumps(
            {
                "user_id": user_id,
                "level": None,
                "weak_areas": [],
                "preferences": {},
                "progress": {},
                "source": source("backend-service", "postgresql", "users"),
                "freshness": freshness("unavailable"),
                "error": upstream_error(e),
            },
            ensure_ascii=False,
        )
