"""Lesson Context Resource"""

import json
import logging

logger = logging.getLogger(__name__)


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
    
    try:
        # TODO: Fetch from PostgreSQL
        # For now, return mock data
        lesson = {
            "lesson_id": lesson_id,
            "title": "Present Perfect - Introduction",
            "level": "B1",
            "vocabulary": [
                {"word": "experience", "definition": "knowledge from doing something"},
                {"word": "just", "definition": "a short time ago"},
                {"word": "already", "definition": "before now"},
                {"word": "yet", "definition": "until now (in questions/negatives)"},
            ],
            "grammar_points": [
                {
                    "point": "Present Perfect Form",
                    "rule": "have/has + past participle",
                    "examples": ["I have visited Paris", "She has eaten lunch"],
                },
                {
                    "point": "Present Perfect vs Simple Past",
                    "rule": "Present perfect: unspecified time, connection to now",
                    "examples": ["I have been to Japan (sometime in my life)"],
                },
            ],
            "objectives": [
                "Understand present perfect structure",
                "Use present perfect for life experiences",
                "Differentiate present perfect from simple past",
            ],
        }
        
        return json.dumps(lesson, ensure_ascii=False)
    
    except Exception as e:
        logger.error(f"Error fetching lesson context: {e}")
        return json.dumps({"error": str(e), "lesson_id": lesson_id})
