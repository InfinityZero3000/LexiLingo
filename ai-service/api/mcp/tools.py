"""
MCP Tools Definition

Defines tools that the MCP server exposes to external clients.
Each tool has a schema, description, and handler function.
"""

import logging
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


# ============================================================
# TOOL SCHEMAS
# ============================================================


class AnalyzeTextInput(BaseModel):
    """Input schema for analyze_text tool."""
    text: str = Field(..., description="User input text to analyze")
    user_id: Optional[str] = Field(None, description="User ID for personalization")
    session_id: str = Field("mcp_session", description="Session identifier")
    level: str = Field("B1", description="CEFR level: A1, A2, B1, B2, C1, C2")


class AnalyzeTextOutput(BaseModel):
    """Output schema for analyze_text tool."""
    tutor_response: str
    grammar_errors: List[Dict[str, Any]]
    fluency_score: float
    vocabulary_level: str
    corrections: List[Dict[str, Any]]


class GetUserProfileInput(BaseModel):
    """Input for get_user_profile tool."""
    user_id: str = Field(..., description="User ID to get profile for")


class GetUserProfileOutput(BaseModel):
    """Output for get_user_profile tool."""
    user_id: str
    level: str
    common_errors: List[str]
    strengths: List[str]
    areas_to_improve: List[str]
    total_interactions: int


class ExpandConceptsInput(BaseModel):
    """Input for expand_concepts tool."""
    concepts: List[str] = Field(..., description="Concept IDs to expand")
    hops: int = Field(1, description="Number of graph hops")


class ExpandConceptsOutput(BaseModel):
    """Output for expand_concepts tool."""
    expanded: List[Dict[str, Any]]
    total_concepts: int


class AssessLevelInput(BaseModel):
    """Input for assess_level tool."""
    user_id: str = Field(..., description="User to assess")
    days: int = Field(30, description="Days of history to analyze")


class AssessLevelOutput(BaseModel):
    """Output for assess_level tool."""
    current_level: str
    confidence: float
    progress_to_next: float
    recommendations: List[str]


class GetDueReviewsInput(BaseModel):
    """Input for get_due_reviews tool."""
    user_id: str = Field(..., description="User ID")
    limit: int = Field(10, description="Max items to return")


class GetDueReviewsOutput(BaseModel):
    """Output for get_due_reviews tool."""
    due_items: List[Dict[str, Any]]
    total_due: int


# ============================================================
# TOOL DEFINITIONS
# ============================================================


TOOL_DEFINITIONS = [
    {
        "name": "analyze_text",
        "description": "Analyze English text for grammar, fluency, and vocabulary. Returns corrections and tutor feedback.",
        "input_schema": AnalyzeTextInput.model_json_schema(),
        "output_schema": AnalyzeTextOutput.model_json_schema(),
    },
    {
        "name": "get_user_profile",
        "description": "Get a user's learning profile including level, common errors, and strengths.",
        "input_schema": GetUserProfileInput.model_json_schema(),
        "output_schema": GetUserProfileOutput.model_json_schema(),
    },
    {
        "name": "expand_concepts",
        "description": "Expand grammar/vocabulary concepts using the knowledge graph.",
        "input_schema": ExpandConceptsInput.model_json_schema(),
        "output_schema": ExpandConceptsOutput.model_json_schema(),
    },
    {
        "name": "assess_level",
        "description": "Assess user's CEFR level based on recent interactions.",
        "input_schema": AssessLevelInput.model_json_schema(),
        "output_schema": AssessLevelOutput.model_json_schema(),
    },
    {
        "name": "get_due_reviews",
        "description": "Get concepts due for spaced repetition review.",
        "input_schema": GetDueReviewsInput.model_json_schema(),
        "output_schema": GetDueReviewsOutput.model_json_schema(),
    },
]


# ============================================================
# TOOL HANDLERS
# ============================================================


class MCPToolHandler:
    """Handler for MCP tool calls."""

    async def handle_tool(
        self,
        tool_name: str,
        arguments: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Route tool call to appropriate handler.

        Args:
            tool_name: Name of tool to call
            arguments: Tool arguments

        Returns:
            Tool result
        """
        handlers = {
            "analyze_text": self._handle_analyze_text,
            "get_user_profile": self._handle_get_user_profile,
            "expand_concepts": self._handle_expand_concepts,
            "assess_level": self._handle_assess_level,
            "get_due_reviews": self._handle_get_due_reviews,
        }

        handler = handlers.get(tool_name)
        if not handler:
            return {"error": f"Unknown tool: {tool_name}"}

        try:
            return await handler(arguments)
        except Exception as e:
            logger.error(f"Tool {tool_name} failed: {e}")
            return {"error": str(e)}

    async def _handle_analyze_text(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle analyze_text tool call."""
        from api.services.graph_cag import get_graph_cag

        input_data = AnalyzeTextInput(**args)
        pipeline = await get_graph_cag()

        result = await pipeline.analyze(
            user_input=input_data.text,
            session_id=input_data.session_id,
            user_id=input_data.user_id,
            learner_profile={"level": input_data.level},
        )

        return AnalyzeTextOutput(
            tutor_response=result.get("tutor_response", ""),
            grammar_errors=result.get("corrections", []),
            fluency_score=result.get("scores", {}).get("fluency", 0.0),
            vocabulary_level=result.get("scores", {}).get("vocabulary_level", "B1"),
            corrections=result.get("corrections", []),
        ).model_dump()

    async def _handle_get_user_profile(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle get_user_profile tool call."""
        from api.repositories.learning_patterns_repo import get_learning_pattern_repository

        input_data = GetUserProfileInput(**args)
        repo = get_learning_pattern_repository()

        pattern = await repo.get_pattern(input_data.user_id)

        if pattern:
            return GetUserProfileOutput(
                user_id=input_data.user_id,
                level=pattern.estimated_level,
                common_errors=[e.type for e in pattern.common_errors[:5]],
                strengths=pattern.strengths,
                areas_to_improve=pattern.weaknesses,
                total_interactions=pattern.stats.get("total_interactions", 0),
            ).model_dump()

        return GetUserProfileOutput(
            user_id=input_data.user_id,
            level="B1",
            common_errors=[],
            strengths=[],
            areas_to_improve=[],
            total_interactions=0,
        ).model_dump()

    async def _handle_expand_concepts(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle expand_concepts tool call."""
        from api.services.kg_service_v3 import KnowledgeGraphServiceV3

        input_data = ExpandConceptsInput(**args)
        kg = KnowledgeGraphServiceV3()

        # Use 'expand' method, not 'expand_concepts'
        result = await kg.expand(input_data.concepts, hops=input_data.hops)

        # Extract from KGHits -> nodes with properties
        return ExpandConceptsOutput(
            expanded=[
                {
                    "id": node.id,
                    "title": node.properties.get("title", node.id)
                }
                for node in result.expanded_nodes
            ],
            total_concepts=len(result.expanded_nodes),
        ).model_dump()

    async def _handle_assess_level(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle assess_level tool call."""
        from api.services.assessment_service import get_assessment_service

        input_data = AssessLevelInput(**args)
        service = get_assessment_service()

        assessment = await service.assess_user(input_data.user_id, input_data.days)

        return AssessLevelOutput(
            current_level=assessment.current_level.value,
            confidence=assessment.confidence,
            progress_to_next=assessment.progress_to_next,
            recommendations=assessment.recommendations,
        ).model_dump()

    async def _handle_get_due_reviews(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle get_due_reviews tool call."""
        from api.services.spaced_repetition_service import get_spaced_repetition_service

        input_data = GetDueReviewsInput(**args)
        service = get_spaced_repetition_service()

        due = await service.get_due_concepts(input_data.user_id, input_data.limit)

        return GetDueReviewsOutput(
            due_items=[item.model_dump() for item in due],
            total_due=len(due),
        ).model_dump()


# Singleton handler
_handler: Optional[MCPToolHandler] = None


def get_tool_handler() -> MCPToolHandler:
    """Get MCP tool handler singleton."""
    global _handler
    if _handler is None:
        _handler = MCPToolHandler()
    return _handler
