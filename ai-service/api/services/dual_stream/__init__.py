"""
Dual-Stream Architecture Package

This package provides real-time streaming conversation capabilities
for the LexiLingo AI English tutor.

Components:
- DualStreamState: Extended state schema for streaming
- StreamingSTTService: Real-time speech-to-text with VAD
- StreamingTTSService: Chunked text-to-speech output
- ThinkingBuffer: Smart pause/resume for LLM thinking
- DualStreamOrchestrator: Main coordinator for all streams
"""

from api.services.dual_stream.dual_stream_state import (
    DualStreamState,
    StreamingContext,
    ThinkingAction,
    TranscriptResult,
    AudioChunk,
    StreamStatus,
    create_dual_stream_state,
)
from api.services.dual_stream.protocol import (
    MessageType,
    StreamMessage,
    create_message,
)
from api.services.dual_stream.streaming_stt_service import (
    StreamingSTTService,
    get_streaming_stt_service,
)
from api.services.dual_stream.streaming_tts_service import (
    StreamingTTSService,
    get_streaming_tts_service,
)
from api.services.dual_stream.thinking_buffer import (
    ThinkingBuffer,
    ThinkingConfig,
    ThinkingState,
    create_thinking_buffer,
)
from api.services.dual_stream.dual_stream_orchestrator import (
    DualStreamOrchestrator,
    OrchestratorConfig,
    create_orchestrator,
)

__all__ = [
    # State
    "DualStreamState",
    "StreamingContext",
    "ThinkingAction",
    "TranscriptResult",
    "AudioChunk",
    "StreamStatus",
    "create_dual_stream_state",
    # Protocol
    "MessageType",
    "StreamMessage",
    "create_message",
    # STT
    "StreamingSTTService",
    "get_streaming_stt_service",
    # TTS
    "StreamingTTSService",
    "get_streaming_tts_service",
    # Thinking
    "ThinkingBuffer",
    "ThinkingConfig",
    "ThinkingState",
    "create_thinking_buffer",
    # Orchestrator
    "DualStreamOrchestrator",
    "OrchestratorConfig",
    "create_orchestrator",
]
