"""
Dual-Stream State Schema

Extended state for real-time streaming conversation with:
- Stream control (listening, thinking, speaking states)
- Thinking buffer for smart pause/resume
- Audio control for interruption handling

Inherits all fields from GraphCAGState for compatibility.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import TypedDict, List, Optional, Any, Dict, Annotated
from operator import add

from api.services.graph_cag.state import GraphCAGState, LearnerProfile


# ============================================================
# ENUMS & DATA CLASSES
# ============================================================

class ThinkingAction(str, Enum):
    """Actions for thinking buffer decision."""
    START = "start"           # Begin new thinking
    CONTINUE = "continue"     # Resume with merged context
    CANCEL = "cancel"         # Discard current, start fresh
    PAUSE = "pause"           # Temporarily pause thinking
    WAIT = "wait"             # Wait for more input


class StreamStatus(str, Enum):
    """Status of each stream."""
    IDLE = "idle"
    ACTIVE = "active"
    PAUSED = "paused"
    STOPPED = "stopped"


@dataclass
class TranscriptResult:
    """Result from streaming STT."""
    text: str
    is_final: bool
    is_partial: bool
    is_interruption: bool
    confidence: float
    timestamp: float
    duration_ms: int = 0
    
    @classmethod
    def partial(cls, text: str, confidence: float = 0.8) -> "TranscriptResult":
        return cls(
            text=text,
            is_final=False,
            is_partial=True,
            is_interruption=False,
            confidence=confidence,
            timestamp=time.time(),
        )
    
    @classmethod
    def final(cls, text: str, confidence: float = 0.9) -> "TranscriptResult":
        return cls(
            text=text,
            is_final=True,
            is_partial=False,
            is_interruption=False,
            confidence=confidence,
            timestamp=time.time(),
        )
    
    @classmethod
    def interruption(cls, text: str = "") -> "TranscriptResult":
        return cls(
            text=text,
            is_final=False,
            is_partial=False,
            is_interruption=True,
            confidence=1.0,
            timestamp=time.time(),
        )


@dataclass
class AudioChunk:
    """Audio chunk for streaming TTS output."""
    audio_bytes: bytes
    chunk_index: int
    is_final: bool
    text_spoken: str
    duration_ms: int
    sample_rate: int = 22050
    
    @property
    def size_bytes(self) -> int:
        return len(self.audio_bytes)


@dataclass
class StreamingContext:
    """
    Context for smart thinking with pause/resume capabilities.
    
    Tracks:
    - Partial transcripts accumulated during thinking
    - Previous response context for continuation
    - Timing for utterance boundary detection
    """
    partial_texts: List[str] = field(default_factory=list)
    last_partial_time: float = 0.0
    thinking_start_time: float = 0.0
    previous_response: str = ""
    previous_user_input: str = ""
    continuation_context: str = ""
    is_continuation: bool = False
    
    def add_partial(self, text: str) -> None:
        """Add partial transcript to buffer."""
        self.partial_texts.append(text)
        self.last_partial_time = time.time()
    
    def get_merged_text(self) -> str:
        """Get merged text from all partials."""
        return " ".join(self.partial_texts)
    
    def clear(self) -> None:
        """Clear all accumulated partials."""
        self.partial_texts.clear()
        self.last_partial_time = 0.0
    
    def time_since_last_partial(self) -> float:
        """Seconds since last partial received."""
        if self.last_partial_time == 0:
            return float("inf")
        return time.time() - self.last_partial_time


# ============================================================
# DUAL-STREAM STATE
# ============================================================

class DualStreamState(TypedDict, total=False):
    """
    Extended state for Dual-Stream Architecture.
    
    Inherits conceptually from GraphCAGState and adds:
    - Stream control states
    - Thinking buffer management
    - Audio streaming control
    - Interruption handling
    
    This state flows through all three streams:
    - Listening Stream (STT)
    - Thinking Stream (GraphCAG + LLM)
    - Speaking Stream (TTS)
    """
    
    # ============================================
    # Inherited from GraphCAGState
    # ============================================
    user_input: str
    session_id: str
    user_id: Optional[str]
    input_type: str
    audio_bytes: Optional[bytes]
    
    learner_profile: LearnerProfile
    conversation_history: List[Dict[str, Any]]
    
    kg_seed_concepts: List[str]
    kg_expanded_nodes: List[Dict[str, Any]]
    kg_paths: List[Dict[str, Any]]
    
    diagnosis_intent: str
    diagnosis_errors: List[Dict[str, Any]]
    diagnosis_root_causes: List[str]
    diagnosis_confidence: float
    
    vector_hits: List[Dict[str, Any]]
    retrieved_context: str
    
    tutor_response: str
    vietnamese_hint: Optional[str]
    pronunciation_tip: Optional[str]
    strategy: str
    next_action: str
    
    fluency_score: float
    grammar_score: float
    vocabulary_level: str
    overall_score: float
    
    tts_audio_bytes: Optional[bytes]
    tts_audio_url: Optional[str]
    
    models_used: Annotated[List[str], add]
    latency_ms: int
    cache_hit: bool
    path: str
    error: Optional[str]
    
    # ============================================
    # NEW: Stream Identification
    # ============================================
    stream_id: str                          # Unique stream identifier
    stream_created_at: float                # Creation timestamp
    
    # ============================================
    # NEW: Stream Control States
    # ============================================
    listening_status: str                   # StreamStatus value
    thinking_status: str                    # StreamStatus value
    speaking_status: str                    # StreamStatus value
    
    is_listening: bool                      # Listening stream active
    is_thinking: bool                       # LLM processing active
    is_speaking: bool                       # TTS output active
    
    # ============================================
    # NEW: Thinking Buffer
    # ============================================
    partial_text_buffer: List[str]          # Accumulated partial transcripts
    current_partial: str                    # Latest partial text
    thinking_context: str                   # Current LLM context
    thinking_interrupted: bool              # Was thinking interrupted?
    pending_continuation: bool              # Should continue previous thought?
    thinking_action: str                    # ThinkingAction value
    
    # ============================================
    # NEW: Smart Context Management
    # ============================================
    streaming_context: Dict[str, Any]       # StreamingContext as dict
    previous_user_input: str                # For continuation detection
    previous_tutor_response: str            # For context awareness
    merged_input: str                       # Combined input after pause
    
    # ============================================
    # NEW: Audio Control
    # ============================================
    audio_chunks_received: int              # Count of STT chunks
    audio_chunks_sent: int                  # Count of TTS chunks
    current_audio_chunk: Optional[bytes]    # Current chunk being processed
    tts_interrupted_at: Optional[int]       # Chunk index where interrupted
    
    # ============================================
    # NEW: Timing & Performance
    # ============================================
    first_audio_latency_ms: int             # Time to first audio output
    stt_latency_ms: int                     # STT processing time
    thinking_latency_ms: int                # LLM processing time
    tts_latency_ms: int                     # TTS generation time
    total_stream_duration_ms: int           # Full conversation turn
    
    # ============================================
    # NEW: Tutor-Specific
    # ============================================
    tutor_personality: str                  # warm, encouraging, strict
    response_style: str                     # brief, detailed, socratic
    should_explain_vi: bool                 # Include Vietnamese hint


def create_dual_stream_state(
    session_id: str,
    user_id: Optional[str] = None,
    learner_profile: Optional[Dict[str, Any]] = None,
    tutor_personality: str = "warm",
) -> DualStreamState:
    """
    Create initial state for Dual-Stream conversation.
    
    Args:
        session_id: Unique session identifier
        user_id: Optional user ID for personalization
        learner_profile: Optional pre-loaded learner profile
        tutor_personality: Tutor personality style
        
    Returns:
        Initialized DualStreamState ready for streaming
    """
    stream_id = str(uuid.uuid4())[:8]
    now = time.time()
    
    # Determine if Vietnamese hints needed based on level
    level = (learner_profile or {}).get("level", "B1")
    should_explain_vi = level in ("A1", "A2")
    
    return DualStreamState(
        # Inherited fields
        user_input="",
        session_id=session_id,
        user_id=user_id,
        input_type="voice",
        audio_bytes=None,
        
        learner_profile=learner_profile or {"level": "B1"},
        conversation_history=[],
        
        kg_seed_concepts=[],
        kg_expanded_nodes=[],
        kg_paths=[],
        
        diagnosis_intent="unknown",
        diagnosis_errors=[],
        diagnosis_root_causes=[],
        diagnosis_confidence=1.0,
        
        vector_hits=[],
        retrieved_context="",
        
        tutor_response="",
        vietnamese_hint=None,
        pronunciation_tip=None,
        strategy="scaffold",
        next_action="continue",
        
        fluency_score=0.0,
        grammar_score=0.0,
        vocabulary_level=level,
        overall_score=0.0,
        
        tts_audio_bytes=None,
        tts_audio_url=None,
        
        models_used=[],
        latency_ms=0,
        cache_hit=False,
        path="streaming",
        error=None,
        
        # Stream identification
        stream_id=stream_id,
        stream_created_at=now,
        
        # Stream control
        listening_status=StreamStatus.IDLE.value,
        thinking_status=StreamStatus.IDLE.value,
        speaking_status=StreamStatus.IDLE.value,
        
        is_listening=False,
        is_thinking=False,
        is_speaking=False,
        
        # Thinking buffer
        partial_text_buffer=[],
        current_partial="",
        thinking_context="",
        thinking_interrupted=False,
        pending_continuation=False,
        thinking_action=ThinkingAction.WAIT.value,
        
        # Smart context
        streaming_context={
            "partial_texts": [],
            "last_partial_time": 0.0,
            "thinking_start_time": 0.0,
            "previous_response": "",
            "previous_user_input": "",
            "continuation_context": "",
            "is_continuation": False,
        },
        previous_user_input="",
        previous_tutor_response="",
        merged_input="",
        
        # Audio control
        audio_chunks_received=0,
        audio_chunks_sent=0,
        current_audio_chunk=None,
        tts_interrupted_at=None,
        
        # Timing
        first_audio_latency_ms=0,
        stt_latency_ms=0,
        thinking_latency_ms=0,
        tts_latency_ms=0,
        total_stream_duration_ms=0,
        
        # Tutor-specific
        tutor_personality=tutor_personality,
        response_style="brief",
        should_explain_vi=should_explain_vi,
    )


def state_to_graphcag(dual_state: DualStreamState) -> GraphCAGState:
    """
    Convert DualStreamState to GraphCAGState for pipeline compatibility.
    
    This allows reusing existing GraphCAG nodes with streaming state.
    """
    from api.services.graph_cag.state import create_initial_state
    
    return create_initial_state(
        user_input=dual_state.get("user_input", ""),
        session_id=dual_state.get("session_id", ""),
        user_id=dual_state.get("user_id"),
        input_type=dual_state.get("input_type", "voice"),
        learner_profile=dual_state.get("learner_profile"),
    )
