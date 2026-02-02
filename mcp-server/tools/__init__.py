"""MCP Tools for LexiLingo"""

# Core tool - Model Gateway (manages all AI models)
from . import model_gateway

# Individual tools (use these for simple cases, or use model_gateway for unified access)
from . import chat
from . import stt
from . import tts
from . import grammar

# Placeholder tools (to be implemented)
from .placeholder import pronunciation, knowledge_graph, exercise

__all__ = [
    # Core unified tool
    "model_gateway",  # ← THE MAIN TOOL - use this for most cases
    
    # Individual tools (legacy/simple use)
    "chat",
    "stt",
    "tts",
    "grammar",
    
    # Placeholder
    "pronunciation",
    "knowledge_graph",
    "exercise",
]
