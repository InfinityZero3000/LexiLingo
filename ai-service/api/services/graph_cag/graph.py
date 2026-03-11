"""
GraphCAG StateGraph Builder

Compiles the LangGraph StateGraph from nodes and edges.
This is the main entry point for the GraphCAG pipeline.
"""

import logging
import time
from typing import Optional, Dict, Any

from langgraph.graph import StateGraph, END

from api.services.graph_cag.state import GraphCAGState, create_initial_state
# Using nodes_v2 with ModelGateway for lazy loading
from api.services.graph_cag.nodes_v2 import (
    input_node,
    cache_gate_node,
    kg_expand_node,
    diagnose_node,
    retrieve_node,
    generate_node,
    vietnamese_node,
    tts_node,
    ask_clarify_node,
)
from api.services.graph_cag.edges import (
    route_after_diagnosis,
    should_generate_tts,
    check_cache_hit,
)
from api.services.model_gateway import get_gateway

logger = logging.getLogger(__name__)


# Singleton instance
_graph_cag_instance: Optional["GraphCAGPipeline"] = None


class GraphCAGPipeline:
    """
    GraphCAG Pipeline using LangGraph StateGraph.
    
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
        logger.info("✓ GraphCAG pipeline compiled")
    
    def _build_graph(self) -> StateGraph:
        """
        Build the StateGraph with all nodes and edges.
        """
        # Create StateGraph with our state schema
        graph = StateGraph(GraphCAGState)
        
        # ============================================
        # ADD NODES
        # ============================================
        graph.add_node("input_node", input_node)
        graph.add_node("cache_gate_node", cache_gate_node)
        graph.add_node("kg_expand_node", kg_expand_node)
        graph.add_node("diagnose_node", diagnose_node)
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
        # ADD EDGES
        # ============================================
        
        # Input → Cache Gate (check for cached response first)
        graph.add_edge("input_node", "cache_gate_node")
        
        # Cache Gate → (END if hit) or (kg_expand if miss)
        graph.add_conditional_edges(
            "cache_gate_node",
            check_cache_hit,
            {
                "cache_hit": END,
                "process": "kg_expand_node",
            }
        )
        
        # KG expand → diagnose
        graph.add_edge("kg_expand_node", "diagnose_node")
        
        # Conditional: diagnose → (retrieve | vietnamese | ask_clarify)
        graph.add_conditional_edges(
            "diagnose_node",
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
        
        # Conditional: generate → (tts | end)
        graph.add_conditional_edges(
            "generate_node",
            should_generate_tts,
            {
                "tts_node": "tts_node",
                "end": END,
            }
        )
        
        # TTS → end
        graph.add_edge("tts_node", END)
        
        return graph
    
    async def analyze(
        self,
        user_input: str,
        session_id: str,
        user_id: Optional[str] = None,
        input_type: str = "text",
        learner_profile: Optional[Dict[str, Any]] = None,
        *,
        cache_policy: str = "on",
        retrieval_policy: str = "full",
        diagnosis_policy: str = "auto",
        generation_policy: str = "auto",
        benchmark_task: Optional[str] = None,
        benchmark_context: Optional[str] = None,
        benchmark_metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Run the GraphCAG pipeline.
        
        Args:
            user_input: Text from user
            session_id: Unique session ID
            user_id: Optional user ID
            input_type: "text" or "voice"
            learner_profile: Optional learner profile
            
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
            cache_policy=cache_policy,
            retrieval_policy=retrieval_policy,
            diagnosis_policy=diagnosis_policy,
            generation_policy=generation_policy,
            benchmark_task=benchmark_task,
            benchmark_context=benchmark_context,
            benchmark_metadata=benchmark_metadata,
        )
        
        logger.info(f"[GraphCAG] Starting analysis: {user_input[:50]}...")
        
        # Run the graph
        try:
            final_state = await self.compiled.ainvoke(initial_state)
            
            # Add total latency
            total_latency_ms = int((time.time() - start_time) * 1000)
            final_state["latency_ms"] = total_latency_ms
            
            logger.info(
                f"[GraphCAG] Completed in {total_latency_ms}ms, "
                f"models: {final_state.get('models_used', [])}"
            )
            
            return self._format_response(final_state)
            
        except Exception as e:
            logger.error(f"[GraphCAG] Error: {e}")
            return {
                "tutor_response": "I'm sorry, something went wrong. Please try again.",
                "error": str(e),
                "metadata": {
                    "latency_ms": int((time.time() - start_time) * 1000),
                    "models_used": [],
                    "path": "error",
                }
            }
    
    def _format_response(self, state: GraphCAGState) -> Dict[str, Any]:
        """Format final state into API response."""
        return {
            "tutor_response": state.get("tutor_response", ""),
            "corrections": [
                {
                    "error": err.get("span", ""),
                    "correction": err.get("correction", ""),
                    "type": err.get("type", ""),
                    "explanation": err.get("explanation", ""),
                }
                for err in state.get("diagnosis_errors", [])
            ],
            "linked_concepts": state.get("kg_seed_concepts", []),
            "vietnamese_hint": state.get("vietnamese_hint"),
            "pronunciation_tip": state.get("pronunciation_tip"),
            "scores": {
                "fluency": state.get("fluency_score", 0.0),
                "grammar": state.get("grammar_score", 0.0),
                "overall": state.get("overall_score", 0.0),
                "vocabulary_level": state.get("vocabulary_level", "B1"),
            },
            "action": {
                "strategy": state.get("strategy", "scaffold"),
                "next": state.get("next_action", "continue"),
            },
            "metadata": {
                "latency_ms": state.get("latency_ms", 0),
                "models_used": state.get("models_used", []),
                "path": state.get("path", "slow"),
                "cache_hit": state.get("cache_hit", False),
                "cache_decision": state.get("cache_decision", "full"),
                "cache_layer": state.get("cache_layer", "none"),
                "cache_bucket": state.get("cache_bucket", ""),
                "reuse_risk": state.get("reuse_risk", 1.0),
                "diagnosis_intent": state.get("diagnosis_intent", "unknown"),
                "kg_concepts_expanded": len(state.get("kg_expanded_nodes", [])),
                "retrieval_trace": state.get("retrieval_trace", []),
            },
            "audio": {
                "bytes": state.get("tts_audio_bytes"),
                "url": state.get("tts_audio_url"),
            } if state.get("tts_audio_bytes") or state.get("tts_audio_url") else None,
        }
    
    async def stream(
        self,
        user_input: str,
        session_id: str,
        **kwargs,
    ):
        """
        Stream the GraphCAG pipeline execution.
        
        Yields state updates as they happen.
        """
        initial_state = create_initial_state(
            user_input=user_input,
            session_id=session_id,
            **kwargs,
        )
        
        async for event in self.compiled.astream(initial_state):
            yield event


async def get_graph_cag() -> GraphCAGPipeline:
    """
    Get or create the GraphCAG pipeline singleton.
    
    Returns:
        Compiled GraphCAGPipeline ready for use
    """
    global _graph_cag_instance
    
    if _graph_cag_instance is None:
        _graph_cag_instance = GraphCAGPipeline()
    
    return _graph_cag_instance


# Convenience function for quick testing
async def analyze_text(text: str, session_id: str = "test") -> Dict[str, Any]:
    """Quick analysis function for testing."""
    pipeline = await get_graph_cag()
    return await pipeline.analyze(text, session_id)
