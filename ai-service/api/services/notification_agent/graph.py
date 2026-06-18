"""LangGraph StateGraph for Notification Agent content generation.

Pipeline:
  START → analyze_audience → generate_variants → evaluate_variants
    ↳ [score < 0.70 and retries < 2] → generate_variants (loop)
    ↳ [score >= 0.70 or max retries] → finalize → END
"""

from __future__ import annotations

import logging
from typing import Optional

from langgraph.graph import END, START, StateGraph

from api.services.notification_agent.nodes import (
    analyze_audience_node,
    evaluate_variants_node,
    finalize_node,
    generate_variants_node,
    should_regenerate,
)
from api.services.notification_agent.state import NotificationAgentState

logger = logging.getLogger(__name__)

_pipeline: Optional["NotificationAgentPipeline"] = None


class NotificationAgentPipeline:
    def __init__(self) -> None:
        self.graph = self._build_graph()
        self.compiled = self.graph.compile()
        logger.info("NotificationAgent LangGraph pipeline compiled")

    def _build_graph(self) -> StateGraph:
        g = StateGraph(NotificationAgentState)

        g.add_node("analyze_audience", analyze_audience_node)
        g.add_node("generate_variants", generate_variants_node)
        g.add_node("evaluate_variants", evaluate_variants_node)
        g.add_node("finalize", finalize_node)

        g.add_edge(START, "analyze_audience")
        g.add_edge("analyze_audience", "generate_variants")
        g.add_edge("generate_variants", "evaluate_variants")

        g.add_conditional_edges(
            "evaluate_variants",
            should_regenerate,
            {
                "generate_variants": "generate_variants",
                "finalize": "finalize",
            },
        )

        g.add_edge("finalize", END)
        return g

    async def run(
        self,
        *,
        title: str,
        body: str,
        notification_type: str = "campaign",
        audience_profile: dict,
    ) -> dict:
        initial_state = NotificationAgentState(
            original_title=title,
            original_body=body,
            notification_type=notification_type,
            audience_profile=audience_profile,
            audience_summary="",
            variants=[],
            retries=0,
            best_variant=None,
            best_score=0.0,
            final_title=title,
            final_body=body,
            generation_skipped=False,
        )
        result = await self.compiled.ainvoke(initial_state)
        return {
            "title": result["final_title"],
            "body": result["final_body"],
            "score": result.get("best_score", 0.0),
            "variants": result.get("variants", []),
            "retries": result.get("retries", 0),
            "generation_skipped": result.get("generation_skipped", False),
        }


def get_notification_agent_pipeline() -> NotificationAgentPipeline:
    global _pipeline
    if _pipeline is None:
        _pipeline = NotificationAgentPipeline()
    return _pipeline
