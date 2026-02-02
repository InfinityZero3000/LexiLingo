"""
Model Handlers Package
Contains lazy-loadable AI model handlers
"""

# Handlers will be imported lazily to avoid loading all models at startup
# from .qwen import QwenHandler
# from .whisper import WhisperHandler
# from .hubert import HuBERTHandler
# from .piper import PiperHandler
# from .gemini import GeminiHandler

__all__ = [
    "QwenHandler",
    "WhisperHandler", 
    "HuBERTHandler",
    "PiperHandler",
    "GeminiHandler",
]
