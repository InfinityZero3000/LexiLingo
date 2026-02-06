"""
MCP Resources Definition

Defines resources that the MCP server exposes.
Resources provide read-only access to data.
"""

import logging
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


# ============================================================
# RESOURCE SCHEMAS
# ============================================================


class LearnerProfileResource(BaseModel):
    """Learner profile resource."""
    uri: str
    name: str
    description: str = "User learning profile with level and progress"
    mime_type: str = "application/json"


class ConceptResource(BaseModel):
    """Grammar/vocabulary concept resource."""
    uri: str
    name: str
    description: str = "Grammar or vocabulary concept"
    mime_type: str = "application/json"


# ============================================================
# RESOURCE DEFINITIONS
# ============================================================


RESOURCE_TEMPLATES = [
    {
        "uri_template": "learner://profile/{user_id}",
        "name": "Learner Profile",
        "description": "Get learner profile including level, errors, and progress",
        "mime_type": "application/json",
    },
    {
        "uri_template": "concepts://grammar/{level}",
        "name": "Grammar Concepts",
        "description": "Grammar concepts for a CEFR level",
        "mime_type": "application/json",
    },
    {
        "uri_template": "concepts://vocabulary/{category}",
        "name": "Vocabulary Concepts",
        "description": "Vocabulary concepts by category",
        "mime_type": "application/json",
    },
    {
        "uri_template": "mastery://user/{user_id}",
        "name": "User Mastery",
        "description": "User's concept mastery summary",
        "mime_type": "application/json",
    },
]


# ============================================================
# RESOURCE HANDLER
# ============================================================


class MCPResourceHandler:
    """Handler for MCP resource requests."""

    async def read_resource(self, uri: str) -> Dict[str, Any]:
        """
        Read a resource by URI.

        Args:
            uri: Resource URI (e.g., "learner://profile/user123")

        Returns:
            Resource contents
        """
        try:
            # Parse URI
            if uri.startswith("learner://profile/"):
                user_id = uri.replace("learner://profile/", "")
                return await self._read_learner_profile(user_id)

            elif uri.startswith("concepts://grammar/"):
                level = uri.replace("concepts://grammar/", "")
                return await self._read_grammar_concepts(level)

            elif uri.startswith("concepts://vocabulary/"):
                category = uri.replace("concepts://vocabulary/", "")
                return await self._read_vocabulary_concepts(category)

            elif uri.startswith("mastery://user/"):
                user_id = uri.replace("mastery://user/", "")
                return await self._read_user_mastery(user_id)

            else:
                return {"error": f"Unknown resource URI: {uri}"}

        except Exception as e:
            logger.error(f"Failed to read resource {uri}: {e}")
            return {"error": str(e)}

    async def list_resources(self) -> List[Dict[str, Any]]:
        """List available resource templates."""
        return RESOURCE_TEMPLATES

    async def _read_learner_profile(self, user_id: str) -> Dict[str, Any]:
        """Read learner profile resource."""
        from api.core.redis_client import get_learner_cache

        try:
            cache = await get_learner_cache()
            profile = await cache.get_profile(user_id)
            return {
                "uri": f"learner://profile/{user_id}",
                "contents": profile,
            }
        except Exception as e:
            return {"uri": f"learner://profile/{user_id}", "error": str(e)}

    async def _read_grammar_concepts(self, level: str) -> Dict[str, Any]:
        """Read grammar concepts for a level."""
        from api.services.kg_service_v3 import KnowledgeGraphServiceV3

        try:
            kg = KnowledgeGraphServiceV3()
            # Filter concepts by level from all concepts
            all_concepts = kg.get_concepts()
            concepts = [
                {"id": c.id, "title": c.title}
                for c in all_concepts
                if "grammar" in c.id.lower() or level.lower() in c.id.lower()
            ][:20]  # Limit results
            return {
                "uri": f"concepts://grammar/{level}",
                "contents": {
                    "level": level,
                    "concepts": concepts,
                    "count": len(concepts),
                },
            }
        except Exception as e:
            return {"uri": f"concepts://grammar/{level}", "error": str(e)}

    async def _read_vocabulary_concepts(self, category: str) -> Dict[str, Any]:
        """Read vocabulary concepts by category."""
        from api.services.kg_service_v3 import KnowledgeGraphServiceV3

        try:
            kg = KnowledgeGraphServiceV3()
            # Filter concepts by category from all concepts
            all_concepts = kg.get_concepts()
            concepts = [
                {"id": c.id, "title": c.title}
                for c in all_concepts
                if "vocab" in c.id.lower() or category.lower() in c.id.lower()
            ][:20]  # Limit results
            return {
                "uri": f"concepts://vocabulary/{category}",
                "contents": {
                    "category": category,
                    "concepts": concepts,
                    "count": len(concepts),
                },
            }
        except Exception as e:
            return {"uri": f"concepts://vocabulary/{category}", "error": str(e)}

    async def _read_user_mastery(self, user_id: str) -> Dict[str, Any]:
        """Read user mastery summary."""
        from api.services.spaced_repetition_service import get_spaced_repetition_service

        try:
            service = get_spaced_repetition_service()
            summary = await service.get_user_mastery_summary(user_id)
            return {
                "uri": f"mastery://user/{user_id}",
                "contents": summary,
            }
        except Exception as e:
            return {"uri": f"mastery://user/{user_id}", "error": str(e)}


# Singleton handler
_handler: Optional[MCPResourceHandler] = None


def get_resource_handler() -> MCPResourceHandler:
    """Get MCP resource handler singleton."""
    global _handler
    if _handler is None:
        _handler = MCPResourceHandler()
    return _handler
