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
    Decide whether to generate TTS audio.
    
    Skip TTS if:
    - Response is empty
    - Input was text-only and short response
    - Error occurred
    """
    if state.get("error"):
        return "end"
    
    if not state.get("tutor_response"):
        return "end"
    
    # Always generate TTS for voice input
    if state.get("input_type") == "voice":
        return "tts_node"
    
    # For text input, generate TTS if response is meaningful
    response_len = len(state.get("tutor_response", ""))
    if response_len > 20:
        return "tts_node"
    
    return "end"


def check_cache_hit(state: GraphCAGState) -> Literal["cache_hit", "process"]:
    """
    Check if we have a cached response.
    Called early in the pipeline.
    """
    if state.get("cache_hit"):
        return "cache_hit"
    return "process"
