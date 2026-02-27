"""
Exercise Generation Tool

Uses Gemini to generate English learning exercises
(MCQ, fill-in-the-blank, translation, reorder).
"""

import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate exercises based on concept and difficulty.

    Args:
        concept: Grammar/vocab concept
        difficulty: 'easy', 'medium', 'hard'
        exercise_type: 'mcq', 'fill_blank', 'translation', 'reorder'
        count: Number of exercises to generate

    Returns:
        exercises: List of exercise objects
        concept: The concept covered
        difficulty: Difficulty level
    """
    concept = args.get("concept", "")
    difficulty = args.get("difficulty", "medium")
    exercise_type = args.get("exercise_type", "mcq")
    count = args.get("count", 1)

    if not concept:
        return {"error": "concept is required"}
    if not difficulty:
        return {"error": "difficulty is required"}
    if not exercise_type:
        return {"error": "exercise_type is required"}

    logger.info(
        f"Exercise generation: concept='{concept}', "
        f"difficulty={difficulty}, type={exercise_type}, count={count}"
    )

    try:
        from handlers.gemini import GeminiHandler

        gemini = GeminiHandler()
        result = await gemini.generate_exercise(
            concept=concept,
            difficulty=difficulty,
            exercise_type=exercise_type,
            count=count,
        )

        return {
            "exercises": result.get("exercises", []),
            "concept": concept,
            "difficulty": difficulty,
            "exercise_type": exercise_type,
            "method": "gemini",
        }

    except Exception as e:
        logger.error(f"Exercise generation error: {e}", exc_info=True)
        return {
            "error": str(e),
            "concept": concept,
            "difficulty": difficulty,
        }
