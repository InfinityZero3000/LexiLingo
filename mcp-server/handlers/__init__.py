"""
Model Handlers Package

- GeminiHandler: Direct Gemini API calls (lightweight, primary backend)
- QwenHandler: Proxies to ai-service for local Qwen inference
- WhisperHandler: Proxies to ai-service for STT
- PiperHandler: Proxies to ai-service for TTS
"""

from .gemini import GeminiHandler
from .qwen import QwenHandler
from .whisper import WhisperHandler
from .piper import PiperHandler

__all__ = [
    "GeminiHandler",
    "QwenHandler",
    "WhisperHandler",
    "PiperHandler",
]
