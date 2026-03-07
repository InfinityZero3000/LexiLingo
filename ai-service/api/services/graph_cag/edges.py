"""
GraphCAG Edge Functions

Conditional routing logic for the StateGraph.
Determines which node to execute next based on current state.
"""

from typing import Literal
from api.services.graph_cag.state import GraphCAGState


def route_after_diagnosis(state: GraphCAGState) -> Literal["retrieve_node", "ask_clarify_node", "vietnamese_node"]:
    """
    Route after diagnosis based on confidence and learner level.
    
    Decision tree:
    - confidence < 0.5 → ask_clarify (need more info)
    - level in A1/A2 and errors → vietnamese (explain in VN first)
    - otherwise → retrieve (continue normal flow)
    """
    confidence = state.get("diagnosis_confidence", 1.0)
    level = state.get("learner_profile", {}).get("level", "B1")
    errors = state.get("diagnosis_errors", [])
    
    # Very low confidence - need clarification
    if confidence < 0.5:
        return "ask_clarify_node"
    
    # Beginner with errors - provide Vietnamese first
    if level in ["A1", "A2"] and len(errors) > 0:
        return "vietnamese_node"
    
    # Normal flow
    return "retrieve_node"


def route_after_vietnamese(state: GraphCAGState) -> Literal["retrieve_node"]:
    """
    After Vietnamese explanation, always continue to retrieval.
    """
    return "retrieve_node"


def should_generate_tts(state: GraphCAGState) -> Literal["tts_node", "end"]:
    """
    Decide whether to generate TTS audio within the GraphCAG pipeline.
    
    NOTE: TTS is handled by the caller (lexi_chat.py) using gTTS,
    which is more reliable and doesn't require loading Piper model.
    GraphCAG pipeline skips TTS to avoid duplicate audio generation
    and unnecessary model loading (~100MB RAM for Piper).
    """
    # Always skip — TTS is handled externally by lexi_chat.py
    return "end"


def check_cache_hit(state: GraphCAGState) -> Literal["cache_hit", "process"]:
    """
    RAPID cache gate (paper Alg. 1).

    Both 'reuse' and 'patch' decisions are considered cache hits —
    the ternary decision was already resolved inside cache_gate_node.
    """
    decision = state.get("cache_decision", "full")
    if decision in ("reuse", "patch"):
        return "cache_hit"
    return "process"
