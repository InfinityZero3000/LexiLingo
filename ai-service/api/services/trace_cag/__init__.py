"""
TraceCAG - Graph-based Cache-Aware Generation.

LangGraph-based orchestration pipeline for LexiLingo AI Tutor.
Uses RAPID cache gate + Knowledge Graph (KuzuDB) retrieval +
StateGraph routing for low-latency grounded responses.
"""

from api.services.trace_cag.state import TraceCAGState, create_initial_state
from api.services.trace_cag.graph import get_trace_cag, TraceCAGPipeline

__all__ = [
    "TraceCAGState",
    "create_initial_state",
    "get_trace_cag",
    "TraceCAGPipeline",
]
