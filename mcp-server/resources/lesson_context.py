"""Lesson Context Resource"""

import json
import logging
from urllib.parse import quote

from resources.common import freshness, source, upstream_error
from utils.api_client import call_backend_service

logger = logging.getLogger(__name__)


def _without_answers(value):
    if isinstance(value, dict):
        return {
            key: _without_answers(item)
            for key, item in value.items()
            if key not in {"correct_answer", "is_correct"}
        }
    if isinstance(value, list):
        return [_without_answers(item) for item in value]
    return value


async def get(lesson_id: str) -> str:
    """
    Get lesson context by lesson ID
    
    Returns JSON with:
    - lesson_id
    - title
    - vocabulary
    - grammar_points
    - objectives
    """
    logger.info(f"Fetching lesson context: lesson_id={lesson_id}")
    safe_lesson_id = quote(lesson_id, safe="")

    try:
        response = await call_backend_service(
            "GET", f"/api/v1/learning/lessons/{safe_lesson_id}/context"
        )
        data = _without_answers(response.get("data") or {})
        lesson = {
            "lesson_id": lesson_id,
            "title": data.get("title"),
            "level": data.get("level"),
            "vocabulary": data.get("vocabulary", []),
            "grammar_points": data.get("grammar_points", []),
            "objectives": data.get("objectives", []),
            "content": data.get("content", {}),
            "source": source("backend-service", "postgresql", "lessons"),
            "freshness": freshness(),
            "error": None,
        }
        return json.dumps(lesson, ensure_ascii=False)

    except Exception as e:
        logger.error(f"Error fetching lesson context: {e}")
        return json.dumps(
            {
                "lesson_id": lesson_id,
                "title": None,
                "level": None,
                "vocabulary": [],
                "grammar_points": [],
                "objectives": [],
                "content": {},
                "source": source("backend-service", "postgresql", "lessons"),
                "freshness": freshness("unavailable"),
                "error": upstream_error(e),
            },
            ensure_ascii=False,
        )
