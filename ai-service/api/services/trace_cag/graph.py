"""
TraceCAG StateGraph Builder

Compiles the LangGraph StateGraph from nodes and edges.
This is the main entry point for the TraceCAG pipeline.
"""

import logging
import time
from typing import Optional, Dict, Any, List

from langgraph.graph import StateGraph, END

from api.services.trace_cag.state import TraceCAGState, create_initial_state
from api.services.trace_cag.evaluation_agent import EvaluationAgent
# Using nodes_v2 with ModelGateway for lazy loading
from api.services.trace_cag.nodes_v2 import (
    input_node,
    cache_gate_node,
    kg_expand_node,
    diagnose_node,
    kg_diagnose_node,
    retrieve_node,
    generate_node,
    vietnamese_node,
    tts_node,
    ask_clarify_node,
)
from api.services.trace_cag.edges import (
    route_after_diagnosis,
    check_cache_hit,
)

logger = logging.getLogger(__name__)


# Singleton instance
_trace_cag_instance: Optional["TraceCAGPipeline"] = None


class TraceCAGPipeline:
    """
    TraceCAG Pipeline using LangGraph StateGraph.
    
    Architecture:
    ┌─────────┐   ┌───────────┐
    │  INPUT  │──▶│CACHE GATE │──── hit ──▶ END
    └─────────┘   └─────┬─────┘
                        │ miss
               ┌────────┴────────┐
               ▼                 ▼
         ┌──────────┐     ┌───────────┐
         │ KG_EXPAND│     │ DIAGNOSE  │
         └────┬─────┘     └─────┬─────┘
              │                 │
              └────────┬────────┘
                       │
           ┌───────────┼───────────────┐
           ▼           ▼               ▼
    ┌────────────┐┌───────────┐ ┌─────────────┐
    │ ASK_CLARIFY││VIETNAMESE │ │  RETRIEVE   │
    └─────┬──────┘└─────┬─────┘ └──────┬──────┘
          │             └──────────────┤
          │                            ▼
          │                     ┌───────────┐
          └────────────────────▶│ GENERATE  │
                                └─────┬─────┘
                                      ▼
                                ┌───────────┐
                                │    END    │
                                └───────────┘
    """
    
    def __init__(self):
        """Initialize and compile the StateGraph."""
        self.graph = self._build_graph()
        self.compiled = self.graph.compile()
        logger.info(" TraceCAG pipeline compiled")
    
    def _build_graph(self) -> StateGraph:
        """
        Build the StateGraph with all nodes and edges.
        """
        # Create StateGraph with our state schema
        graph = StateGraph(TraceCAGState)
        
        # ============================================
        # ADD NODES
        # ============================================
        graph.add_node("input_node", input_node)
        graph.add_node("cache_gate_node", cache_gate_node)
        graph.add_node("kg_expand_node", kg_expand_node)
        graph.add_node("diagnose_node", diagnose_node)
        graph.add_node("kg_diagnose_node", kg_diagnose_node)
        graph.add_node("retrieve_node", retrieve_node)
        graph.add_node("generate_node", generate_node)
        graph.add_node("vietnamese_node", vietnamese_node)
        graph.add_node("tts_node", tts_node)
        graph.add_node("ask_clarify_node", ask_clarify_node)
        
        # ============================================
        # SET ENTRY POINT
        # ============================================
        graph.set_entry_point("input_node")
        
        # ============================================
        # ============================================
        # ADD EDGES
        # ============================================

        # Realtime STT finalizes audio before TRACE-CAG is invoked.
        graph.add_edge("input_node", "cache_gate_node")

        # Cache Gate → (END if hit) or (kg_diagnose if miss)
        # kg_diagnose_node runs kg_expand + diagnose concurrently via asyncio.gather
        graph.add_conditional_edges(
            "cache_gate_node",
            check_cache_hit,
            {
                "cache_hit": END,
                "process": "kg_diagnose_node",
            }
        )

        # Conditional: kg_diagnose → (retrieve | vietnamese | ask_clarify)
        graph.add_conditional_edges(
            "kg_diagnose_node",
            route_after_diagnosis,
            {
                "retrieve_node": "retrieve_node",
                "vietnamese_node": "vietnamese_node",
                "ask_clarify_node": "ask_clarify_node",
            }
        )

        # Vietnamese → retrieve (continue normal flow)
        graph.add_edge("vietnamese_node", "retrieve_node")

        # Retrieve → generate
        graph.add_edge("retrieve_node", "generate_node")

        # Ask clarify → END (already has complete tutor_response, skip generate)
        graph.add_edge("ask_clarify_node", END)

        graph.add_edge("generate_node", END)

        # TTS → end (node remains registered but unreachable; TTS handled externally)
        graph.add_edge("tts_node", END)
        
        return graph
    
    async def analyze(
        self,
        user_input: str,
        session_id: str,
        user_id: Optional[str] = None,
        input_type: str = "text",
        learner_profile: Optional[Dict[str, Any]] = None,
        conversation_history: Optional[List[Dict[str, Any]]] = None,
        stt_final: Optional[Dict[str, Any]] = None,
        *,
        cache_policy: str = "on",
        retrieval_policy: str = "full",
        diagnosis_policy: str = "auto",
        generation_policy: str = "auto",
        benchmark_task: Optional[str] = None,
        benchmark_context: Optional[str] = None,
        benchmark_metadata: Optional[Dict[str, Any]] = None,
        kg_seed_concepts: Optional[List[str]] = None,
        return_raw_state: bool = False,
    ) -> Dict[str, Any]:
        """
        Run the TraceCAG pipeline.

        Args:
            user_input: Text from user
            session_id: Unique session ID
            user_id: Optional user ID
            input_type: "text" or "voice"
            learner_profile: Optional learner profile
            conversation_history: Optional prior turns to inject (bypasses Redis load)

        Returns:
            Final state with tutor response
        """
        start_time = time.time()

        # Create initial state
        initial_state = create_initial_state(
            user_input=user_input,
            session_id=session_id,
            user_id=user_id,
            input_type=input_type,
            learner_profile=learner_profile,
            stt_final=stt_final,
            cache_policy=cache_policy,
            retrieval_policy=retrieval_policy,
            diagnosis_policy=diagnosis_policy,
            generation_policy=generation_policy,
            benchmark_task=benchmark_task,
            benchmark_context=benchmark_context,
            benchmark_metadata=benchmark_metadata,
        )

        # Inject preloaded KG seed concepts (from SubgraphHotCache) to skip KG lookup
        if kg_seed_concepts:
            initial_state["kg_seed_concepts"] = list(kg_seed_concepts)

        # Override conversation_history if caller supplies it directly
        # (avoids a redundant Redis round-trip when lexi_chat already holds the store)
        if conversation_history is not None:
            initial_state["conversation_history"] = conversation_history
        
        logger.info(f"[TraceCAG] Starting analysis: {user_input[:50]}...")
        
        # Run the graph
        try:
            final_state = await self.compiled.ainvoke(initial_state)

            # Add total latency
            total_latency_ms = int((time.time() - start_time) * 1000)
            final_state["latency_ms"] = total_latency_ms

            logger.info(
                f"[TraceCAG] Completed in {total_latency_ms}ms, "
                f"models: {final_state.get('models_used', [])}"
            )

            if return_raw_state:
                return dict(final_state)

            return self._format_response(final_state)
            
        except Exception as e:
            logger.error(f"[TraceCAG] Error: {e}")
            return {
                "tutor_response": "I'm sorry, something went wrong. Please try again.",
                "error": str(e),
                "metadata": {
                    "latency_ms": int((time.time() - start_time) * 1000),
                    "ttft_ms": 0,
                    "graph_update": {"latency_ms": 0, "nodes_added": 0, "edges_added": 0},
                    "models_used": [],
                    "path": "error",
                }
            }
    
    def _format_response(self, state: TraceCAGState) -> Dict[str, Any]:
        """
        Format final state into API response with weighted evidence fusion.

        Scores are recomputed here via EvaluationAgent to ensure consistency
        regardless of which node path executed (cache hit vs. slow path).
        """
        grammar = state.get("grammar_score", 0.0)
        fluency = state.get("fluency_score", 0.0)
        vocab_level = state.get("vocabulary_level", "B1")
        trace = state.get("retrieval_trace", [])
        errors = state.get("diagnosis_errors", [])
        user_input = state.get("user_input", "")

        # ── Composite score ────────────────────────────────────────────────
        overall_weighted = EvaluationAgent.compute_overall_score(grammar, fluency, vocab_level)

        # ── Text quality metrics ───────────────────────────────────────────
        word_count = len(user_input.split()) if user_input.strip() else 0
        correction_count = len(errors)
        corrected_text = EvaluationAgent.apply_corrections(user_input, errors)
        wer = EvaluationAgent.compute_wer(user_input, corrected_text) if errors else 0.0
        ttr = EvaluationAgent.compute_type_token_ratio(user_input)
        error_density = EvaluationAgent.compute_error_density(correction_count, word_count)

        # ── Retrieval quality metrics ──────────────────────────────────────
        precision_k = EvaluationAgent.compute_retrieval_quality(trace)
        ndcg_k = EvaluationAgent.compute_ndcg_k(trace)
        mrr = EvaluationAgent.compute_mrr(trace)

        bm_meta = state.get("benchmark_metadata") or {}
        total_relevant = len(
            bm_meta.get("supporting_titles")
            or bm_meta.get("relevant_passage_ids")
            or []
        )
        recall_k = EvaluationAgent.compute_recall_k(trace, total_relevant)

        return {
            "tutor_response": state.get("tutor_response", ""),
            "corrections": [
                {
                    "error": err.get("span", ""),
                    "correction": err.get("correction", ""),
                    "type": err.get("type", ""),
                    "explanation": err.get("explanation", ""),
                }
                for err in errors
            ],
            "linked_concepts": state.get("kg_seed_concepts", []),
            "action_plan": state.get("action_plan", []),
            "vietnamese_hint": state.get("vietnamese_hint"),
            "pronunciation_tip": state.get("pronunciation_tip"),
            "scores": {
                "fluency": fluency,
                "grammar": grammar,
                "overall": overall_weighted,
                "vocabulary_level": vocab_level,
                "diagnosis_confidence": state.get("diagnosis_confidence", 0.0),
                "wer": round(wer, 4),
                "word_count": word_count,
                "correction_count": correction_count,
                "error_density": error_density,
                "type_token_ratio": round(ttr, 4),
                "retrieval": {
                    "precision_k": precision_k,
                    "recall_k": recall_k,
                    "ndcg_k": round(ndcg_k, 4) if ndcg_k is not None else None,
                    "mrr": round(mrr, 4) if mrr is not None else None,
                },
            },
            "action": {
                "strategy": state.get("strategy", "scaffold"),
                "next": state.get("next_action", "continue"),
            },
            "metadata": {
                "latency_ms": state.get("latency_ms", 0),
                "ttft_ms": state.get("ttft_ms", 0),
                "models_used": state.get("models_used", []),
                "path": state.get("path", "slow"),
                "cache_hit": state.get("cache_hit", False),
                "cache_decision": state.get("cache_decision", "full"),
                "cache_layer": state.get("cache_layer", "none"),
                "cache_bucket": state.get("cache_bucket", ""),
                "reuse_risk": state.get("reuse_risk", 1.0),
                "adaptive_profile": state.get("adaptive_profile"),
                "adaptive_features": state.get("adaptive_features", {}),
                "adaptive_controller": state.get("adaptive_controller", {}),
                "tokens_saved": state.get("tokens_saved", 0),
                "diagnosis_intent": state.get("diagnosis_intent", "unknown"),
                "kg_concepts_expanded": len(state.get("kg_expanded_nodes", [])),
                "retrieval_trace": trace,
                "retrieval_meta": state.get("retrieval_meta", {}),
                "graph_update": state.get("graph_update", {"latency_ms": 0, "nodes_added": 0, "edges_added": 0}),
            },
            "audio": {
                "bytes": state.get("tts_audio_bytes"),
                "url": state.get("tts_audio_url"),
            } if state.get("tts_audio_bytes") or state.get("tts_audio_url") else None,
        }
    
    async def analyze_for_streaming(
        self,
        user_input: str,
        session_id: str,
        user_id: Optional[str] = None,
        learner_profile: Optional[Dict[str, Any]] = None,
        conversation_history: Optional[List[Dict[str, Any]]] = None,
        **kwargs: Any,
    ) -> Dict[str, Any]:
        """Run the pipeline with generation skipped; return raw state.

        Used by the SSE streaming endpoint so it can stream LLM tokens itself
        after the cheaper KG / diagnosis / retrieval steps have prepared context.
        On a cache hit the cached tutor_response is already in the state and
        the caller should use it directly instead of calling the LLM.
        """
        return await self.analyze(
            user_input=user_input,
            session_id=session_id,
            user_id=user_id,
            learner_profile=learner_profile,
            conversation_history=conversation_history,
            generation_policy="skip",
            return_raw_state=True,
            **kwargs,
        )

    async def stream(
        self,
        user_input: str,
        session_id: str,
        **kwargs,
    ):
        """
        Stream the TraceCAG pipeline execution.
        
        Yields state updates as they happen.
        """
        initial_state = create_initial_state(
            user_input=user_input,
            session_id=session_id,
            **kwargs,
        )
        
        async for event in self.compiled.astream(initial_state):
            yield event


async def get_trace_cag() -> TraceCAGPipeline:
    """
    Get or create the TraceCAG pipeline singleton.
    
    Returns:
        Compiled TraceCAGPipeline ready for use
    """
    global _trace_cag_instance
    
    if _trace_cag_instance is None:
        _trace_cag_instance = TraceCAGPipeline()
    
    return _trace_cag_instance


# Convenience function for quick testing
async def analyze_text(text: str, session_id: str = "test") -> Dict[str, Any]:
    """Quick analysis function for testing."""
    pipeline = await get_trace_cag()
    return await pipeline.analyze(text, session_id)
