"""
GraphCAG - Graph-based Cache-Aware Generation.

LangGraph-based orchestration pipeline for LexiLingo AI Tutor.
Uses RAPID cache gate + Knowledge Graph (KuzuDB) retrieval +
StateGraph routing for low-latency grounded responses.
"""

from api.services.graph_cag.state import GraphCAGState, create_initial_state
from api.services.graph_cag.graph import get_graph_cag, GraphCAGPipeline

__all__ = [
    "GraphCAGState",
    "create_initial_state",
    "get_graph_cag",
    "GraphCAGPipeline",
]
