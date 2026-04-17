"""
Model Handlers for LexiLingo AI Service

Each handler is responsible for loading, managing, and executing
a specific AI model with lazy loading support.
"""

from .ollama_qwen_handler import OllamaQwenHandler
from .whisper_handler import WhisperHandler
from .piper_handler import PiperHandler
from .hubert_handler import HuBERTHandler
from .gemini_handler import GeminiHandler

__all__ = [
    "OllamaQwenHandler",
    "WhisperHandler", 
    "PiperHandler",
    "HuBERTHandler",
    "GeminiHandler",
]
