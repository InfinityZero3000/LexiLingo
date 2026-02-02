"""
Model Handlers for LexiLingo AI Service

Each handler is responsible for loading, managing, and executing
a specific AI model with lazy loading support.
"""

from .qwen_handler import QwenHandler
from .whisper_handler import WhisperHandler
from .piper_handler import PiperHandler
from .hubert_handler import HuBERTHandler
from .gemini_handler import GeminiHandler

__all__ = [
    "QwenHandler",
    "WhisperHandler", 
    "PiperHandler",
    "HuBERTHandler",
    "GeminiHandler",
]
