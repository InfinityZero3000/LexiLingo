"""RecGraph — the recommender as a LangGraph StateGraph.

Mirrors TraceCAGPipeline deliberately: same cache-gate-first shape, same
singleton access, same "never raise into the caller" contract. It is a separate
graph rather than nodes bolted onto TraceCAG because the two have different
cache lifetimes (learner state epoch vs. conversation turn) and different SLAs.

    INPUT ─▶ CACHE_GATE ──hit──▶ END
                  │ miss
                  ▼
              EMBED ─▶ SCORE ─▶ RERANK ─▶ EXPLAIN ─▶ END
"""

from __future__ import annotations

import logging
import time
from typing import Any, Dict, List, Optional

from langgraph.graph import END, StateGraph

from api.services.rec_graph.nodes import (
    RecState,
    cache_gate_node,
    embed_node,
    explain_node,
    rerank_node,
    score_node,
)

logger = logging.getLogger(__name__)

_pipeline: Optional["RecGraphPipeline"] = None


def _check_cache_hit(state: RecState) -> str:
    return "cache_hit" if state.get("cache_hit") else "process"


class RecGraphPipeline:
    def __init__(self) -> None:
        graph = StateGraph(RecState)
        graph.add_node("cache_gate_node", cache_gate_node)
        graph.add_node("embed_node", embed_node)
        graph.add_node("score_node", score_node)
        graph.add_node("rerank_node", rerank_node)
        graph.add_node("explain_node", explain_node)

        graph.set_entry_point("cache_gate_node")
        graph.add_conditional_edges(
            "cache_gate_node",
            _check_cache_hit,
            {"cache_hit": END, "process": "embed_node"},
        )
        graph.add_edge("embed_node", "score_node")
        graph.add_edge("score_node", "rerank_node")
        graph.add_edge("rerank_node", "explain_node")
        graph.add_edge("explain_node", END)

        self.compiled = graph.compile()
        logger.info("RecGraph pipeline compiled")

    async def recommend(
        self,
        *,
        user_id: str,
        profile: Dict[str, Any],
        candidates: List[Dict[str, Any]],
        surface: str = "home",
        k: int = 10,
    ) -> Dict[str, Any]:
        started = time.time()
        initial: RecState = {
            "user_id": user_id,
            "surface": surface,
            "k": k,
            "profile": profile,
            "candidates": candidates,
        }
        try:
            final = await self.compiled.ainvoke(initial)
        except Exception as exc:
            logger.error("RecGraph failed: %s", exc)
            return {
                "recommendations": [],
                "metadata": {"error": str(exc), "cache_hit": False, "latency_ms": 0},
            }

        return {
            "recommendations": final.get("recommendations", []),
            "metadata": {
                "cache_hit": bool(final.get("cache_hit")),
                "candidates_considered": len(candidates),
                "latency_ms": int((time.time() - started) * 1000),
            },
        }


async def get_rec_graph() -> RecGraphPipeline:
    global _pipeline
    if _pipeline is None:
        _pipeline = RecGraphPipeline()
    return _pipeline
