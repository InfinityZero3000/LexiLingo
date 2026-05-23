"""
Knowledge Graph Query Tool

Uses Gemini to explore English language concept relationships,
serving as a lightweight alternative to KuzuDB for the MCP server.
"""

import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Query knowledge graph for concept relationships.

    Args:
        concept: Concept to query (e.g., 'present perfect')
        relation_type: Type of relations ('prerequisite', 'related', 'all')
        depth: Depth of graph traversal

    Returns:
        concept: Queried concept
        prerequisites: Required prior knowledge
        related_concepts: Related concepts
        advanced_from: What this leads to
        examples: Example sentences
        common_errors: Typical mistakes
    """
    concept = args.get("concept", "")
    relation_type = args.get("relation_type", "all")
    depth = args.get("depth", 2)

    if not concept:
        return {"error": "concept is required"}

    logger.info(
        f"Knowledge graph query: concept='{concept}', "
        f"relation={relation_type}, depth={depth}"
    )

    try:
        # Try ai-service KG endpoint first (if available)
        result = await _try_ai_service_kg(concept, relation_type, depth)
        if result:
            return result

        # Fall back to Gemini-based concept expansion
        from handlers.gemini import GeminiHandler

        gemini = GeminiHandler()
        analysis = await gemini.expand_concepts(concept, relation_type, depth)

        return {
            "concept": concept,
            "relation_type": relation_type,
            "depth": depth,
            "data": analysis,
            "method": "gemini",
        }

    except Exception as e:
        logger.error(f"Knowledge graph query error: {e}", exc_info=True)
        return {
            "error": str(e),
            "concept": concept,
        }


async def _try_ai_service_kg(
    concept: str, relation_type: str, depth: int
) -> Dict[str, Any] | None:
    """Try to use ai-service's knowledge graph if available"""
    try:
        from utils.api_client import check_ai_service_health

        if not await check_ai_service_health():
            return None

        # ai-service doesn't currently expose a direct KG endpoint
        # in its mounted routes, so we return None to fall back to Gemini.
        # In the future, when /api/v1/kg/ routes are mounted, we can
        # proxy here.
        return None

    except Exception:
        return None
