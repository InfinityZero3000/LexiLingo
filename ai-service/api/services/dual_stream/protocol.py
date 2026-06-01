"""
WebSocket Message Protocol

Defines message types and formats for dual-stream WebSocket communication.

Client → Server:
- Binary audio chunks (PCM 16kHz mono)
- JSON control messages

Server → Client:
- JSON event messages
- Binary audio chunks
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass, asdict
from enum import Enum
from typing import Any, Dict, Optional, Union


class MessageType(str, Enum):
    """WebSocket message types for dual-stream protocol."""
    
    # === Client → Server ===
    AUDIO_CHUNK = "audio_chunk"           # Binary audio data
    START_LISTENING = "start_listening"   # Begin STT
    STOP_LISTENING = "stop_listening"     # End STT
    CANCEL = "cancel"                     # Cancel current operation
    CONFIG = "config"                     # Update configuration
    
    # === Server → Client: STT Events ===
    TRANSCRIPT_PARTIAL = "transcript_partial"   # Intermediate STT
    TRANSCRIPT_FINAL = "transcript_final"       # Complete utterance
    
    # === Server → Client: Thinking Events ===
    THINKING_START = "thinking_start"     # AI started processing
    THINKING_PAUSE = "thinking_pause"     # Thinking paused (more input)
    THINKING_RESUME = "thinking_resume"   # Thinking resumed
    THINKING_STOP = "thinking_stop"       # Thinking complete or cancelled
    
    # === Server → Client: Response Events ===
    RESPONSE_TEXT = "response_text"       # Text response (can be partial)
    RESPONSE_COMPLETE = "response_complete"  # Full response ready
    
    # === Server → Client: Audio Events ===
    AUDIO_START = "audio_start"           # TTS stream beginning
    AUDIO_CHUNK_OUT = "audio_chunk_out"   # TTS audio chunk
    AUDIO_END = "audio_end"               # TTS stream complete
    AUDIO_INTERRUPTED = "audio_interrupted"  # TTS was interrupted
    
    # === Server → Client: Analysis Events ===
    ANALYSIS_ERRORS = "analysis_errors"   # Grammar errors found
    ANALYSIS_SCORES = "analysis_scores"   # Fluency/grammar scores
    ANALYSIS_CONCEPTS = "analysis_concepts"  # KG concepts linked
    
    # === Control ===
    CONNECTED = "connected"               # Connection established
    DISCONNECTED = "disconnected"         # Connection closed
    ERROR = "error"                       # Error occurred
    HEARTBEAT = "heartbeat"               # Keep-alive ping/pong


@dataclass
class StreamMessage:
    """
    Structured message for WebSocket communication.
    
    All messages include:
    - type: MessageType
    - timestamp: When message was created
    - data: Payload (type-dependent)
    - stream_id: Associated stream (optional)
    """
    type: MessageType
    data: Dict[str, Any]
    timestamp: float = 0.0
    stream_id: Optional[str] = None
    sequence: int = 0
    
    def __post_init__(self):
        if self.timestamp == 0.0:
            self.timestamp = time.time()
    
    def to_json(self) -> str:
        """Serialize to JSON string."""
        return json.dumps({
            "type": self.type.value if isinstance(self.type, Enum) else self.type,
            "data": self.data,
            "timestamp": self.timestamp,
            "stream_id": self.stream_id,
            "sequence": self.sequence,
        })
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "type": self.type.value if isinstance(self.type, Enum) else self.type,
            "data": self.data,
            "timestamp": self.timestamp,
            "stream_id": self.stream_id,
            "sequence": self.sequence,
        }
    
    @classmethod
    def from_json(cls, json_str: str) -> "StreamMessage":
        """Parse from JSON string."""
        data = json.loads(json_str)
        return cls(
            type=MessageType(data["type"]),
            data=data.get("data", {}),
            timestamp=data.get("timestamp", time.time()),
            stream_id=data.get("stream_id"),
            sequence=data.get("sequence", 0),
        )


# ============================================================
# MESSAGE FACTORY FUNCTIONS
# ============================================================

def create_message(
    msg_type: MessageType,
    stream_id: Optional[str] = None,
    **data
) -> StreamMessage:
    """Create a StreamMessage with given type and data."""
    return StreamMessage(
        type=msg_type,
        data=data,
        stream_id=stream_id,
    )


def msg_transcript_partial(
    text: str,
    confidence: float,
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create partial transcript message."""
    return create_message(
        MessageType.TRANSCRIPT_PARTIAL,
        stream_id=stream_id,
        text=text,
        confidence=confidence,
    )


def msg_transcript_final(
    text: str,
    confidence: float,
    duration_ms: int,
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create final transcript message."""
    return create_message(
        MessageType.TRANSCRIPT_FINAL,
        stream_id=stream_id,
        text=text,
        confidence=confidence,
        duration_ms=duration_ms,
    )


def msg_thinking_start(
    context: str = "",
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create thinking start message."""
    return create_message(
        MessageType.THINKING_START,
        stream_id=stream_id,
        context=context,
    )


def msg_thinking_stop(
    reason: str = "complete",
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create thinking stop message."""
    return create_message(
        MessageType.THINKING_STOP,
        stream_id=stream_id,
        reason=reason,  # complete, interrupted, cancelled
    )


def msg_response_text(
    text: str,
    is_partial: bool = False,
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create response text message."""
    return create_message(
        MessageType.RESPONSE_TEXT,
        stream_id=stream_id,
        text=text,
        is_partial=is_partial,
    )


def msg_response_complete(
    text: str,
    strategy: str,
    scores: Dict[str, float],
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create complete response message."""
    return create_message(
        MessageType.RESPONSE_COMPLETE,
        stream_id=stream_id,
        text=text,
        strategy=strategy,
        scores=scores,
    )


def msg_audio_start(
    total_chunks: Optional[int] = None,
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create audio stream start message."""
    return create_message(
        MessageType.AUDIO_START,
        stream_id=stream_id,
        total_chunks=total_chunks,
    )


def msg_audio_end(
    chunks_sent: int,
    duration_ms: int,
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create audio stream end message."""
    return create_message(
        MessageType.AUDIO_END,
        stream_id=stream_id,
        chunks_sent=chunks_sent,
        duration_ms=duration_ms,
    )


def msg_audio_interrupted(
    at_chunk: int,
    reason: str = "user_speaking",
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create audio interrupted message."""
    return create_message(
        MessageType.AUDIO_INTERRUPTED,
        stream_id=stream_id,
        at_chunk=at_chunk,
        reason=reason,
    )


def msg_analysis_errors(
    errors: list,
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create analysis errors message."""
    return create_message(
        MessageType.ANALYSIS_ERRORS,
        stream_id=stream_id,
        errors=errors,
    )


def msg_analysis_scores(
    fluency: float,
    grammar: float,
    overall: float,
    vocabulary_level: str,
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create analysis scores message."""
    return create_message(
        MessageType.ANALYSIS_SCORES,
        stream_id=stream_id,
        fluency=fluency,
        grammar=grammar,
        overall=overall,
        vocabulary_level=vocabulary_level,
    )


def msg_error(
    message: str,
    code: str = "UNKNOWN_ERROR",
    stream_id: Optional[str] = None,
) -> StreamMessage:
    """Create error message."""
    return create_message(
        MessageType.ERROR,
        stream_id=stream_id,
        message=message,
        code=code,
    )


def msg_connected(
    stream_id: str,
    session_id: str,
) -> StreamMessage:
    """Create connected message."""
    return create_message(
        MessageType.CONNECTED,
        stream_id=stream_id,
        session_id=session_id,
    )
