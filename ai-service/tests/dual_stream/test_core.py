"""
Unit Tests for Dual-Stream Architecture

Tests core components:
1. DualStreamState
2. ThinkingBuffer
3. Protocol messages
4. StreamingSTTService (mocked)
5. StreamingTTSService (mocked)
6. DualStreamOrchestrator (mocked)
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch
from dataclasses import dataclass

# Import components to test
from api.services.dual_stream.dual_stream_state import (
    DualStreamState,
    TranscriptResult,
    AudioChunk,
    ThinkingAction,
    StreamStatus,
    StreamingContext,
    create_dual_stream_state,
)
from api.services.dual_stream.protocol import (
    MessageType,
    StreamMessage,
    create_message,
    msg_transcript_partial,
    msg_transcript_final,
    msg_thinking_start,
    msg_thinking_stop,
    msg_response_text,
    msg_audio_start,
    msg_audio_end,
    msg_connected,
    msg_error,
)
from api.services.dual_stream.thinking_buffer import (
    ThinkingBuffer,
    ThinkingConfig,
    ThinkingState,
    create_thinking_buffer,
)


# ============================================================
# TEST: DualStreamState
# ============================================================

class TestDualStreamState:
    """Test DualStreamState creation and manipulation."""
    
    def test_create_initial_state(self):
        """Test creating initial state with default values."""
        state = create_dual_stream_state(
            session_id="test-session-123",
            user_id="user-456",
        )
        
        assert state["session_id"] == "test-session-123"
        assert state["user_id"] == "user-456"
        assert state["stream_id"] is not None
        assert state["is_listening"] == False
        assert state["is_thinking"] == False
        assert state["is_speaking"] == False
        assert state["listening_status"] == StreamStatus.IDLE.value
        assert state["thinking_status"] == StreamStatus.IDLE.value
        assert state["speaking_status"] == StreamStatus.IDLE.value
    
    def test_state_with_learner_profile(self):
        """Test state with learner profile."""
        profile = {"level": "B1", "native_language": "vi"}
        state = create_dual_stream_state(
            session_id="test",
            learner_profile=profile,
        )
        
        assert state["learner_profile"] == profile
    
    def test_state_with_tutor_personality(self):
        """Test state with tutor personality."""
        state = create_dual_stream_state(
            session_id="test",
            tutor_personality="encouraging",
        )
        
        assert state["tutor_personality"] == "encouraging"


class TestTranscriptResult:
    """Test TranscriptResult dataclass."""
    
    def test_partial_result(self):
        """Test partial transcript result."""
        result = TranscriptResult.partial("Hello", confidence=0.85)
        
        assert result.is_partial == True
        assert result.is_final == False
        assert result.is_interruption == False
        assert result.text == "Hello"
        assert result.confidence == 0.85
    
    def test_final_result(self):
        """Test final transcript result."""
        result = TranscriptResult.final("Hello world", confidence=0.95)
        
        assert result.is_partial == False
        assert result.is_final == True
        assert result.text == "Hello world"
    
    def test_interruption_result(self):
        """Test interruption detection result."""
        result = TranscriptResult.interruption()
        
        assert result.is_interruption == True
        assert result.is_partial == False
        assert result.is_final == False


class TestAudioChunk:
    """Test AudioChunk dataclass."""
    
    def test_audio_chunk_creation(self):
        """Test audio chunk creation."""
        chunk = AudioChunk(
            audio_bytes=b"fake_audio_data",
            chunk_index=0,
            is_final=False,
            text_spoken="Hello",
            duration_ms=500,
            sample_rate=22050,
        )
        
        assert chunk.audio_bytes == b"fake_audio_data"
        assert chunk.chunk_index == 0
        assert chunk.is_final == False
        assert chunk.text_spoken == "Hello"
        assert chunk.duration_ms == 500


# ============================================================
# TEST: Protocol Messages
# ============================================================

class TestProtocol:
    """Test WebSocket protocol messages."""
    
    def test_message_type_enum(self):
        """Test MessageType enum values."""
        assert MessageType.AUDIO_CHUNK == "audio_chunk"
        assert MessageType.TRANSCRIPT_PARTIAL == "transcript_partial"
        assert MessageType.THINKING_START == "thinking_start"
        assert MessageType.RESPONSE_TEXT == "response_text"
    
    def test_stream_message_creation(self):
        """Test StreamMessage creation."""
        msg = StreamMessage(
            type=MessageType.TRANSCRIPT_PARTIAL,
            data={"text": "Hello"},
        )
        
        assert msg.type == MessageType.TRANSCRIPT_PARTIAL
        assert msg.data["text"] == "Hello"
    
    def test_stream_message_to_json(self):
        """Test StreamMessage JSON serialization."""
        msg = StreamMessage(
            type=MessageType.THINKING_START,
            data={"context": "user question"},
            stream_id="stream-123",
        )
        
        json_str = msg.to_json()
        assert '"type": "thinking_start"' in json_str
        assert '"context": "user question"' in json_str
    
    def test_stream_message_from_json(self):
        """Test StreamMessage JSON deserialization."""
        json_str = '{"type": "transcript_final", "data": {"text": "Hello"}, "timestamp": 123.0}'
        msg = StreamMessage.from_json(json_str)
        
        assert msg.type == MessageType.TRANSCRIPT_FINAL
        assert msg.data["text"] == "Hello"
    
    def test_msg_transcript_partial(self):
        """Test partial transcript message factory."""
        msg = msg_transcript_partial("Hello wo...", 0.8, "stream-1")
        
        assert msg.type == MessageType.TRANSCRIPT_PARTIAL
        assert msg.data["text"] == "Hello wo..."
        assert msg.data["confidence"] == 0.8
    
    def test_msg_transcript_final(self):
        """Test final transcript message factory."""
        msg = msg_transcript_final("Hello world", 0.95, 1500, "stream-1")
        
        assert msg.type == MessageType.TRANSCRIPT_FINAL
        assert msg.data["text"] == "Hello world"
        assert msg.data["duration_ms"] == 1500
    
    def test_msg_thinking_start(self):
        """Test thinking start message factory."""
        msg = msg_thinking_start("What is grammar?", "stream-1")
        
        assert msg.type == MessageType.THINKING_START
        assert msg.data["context"] == "What is grammar?"
    
    def test_msg_response_text(self):
        """Test response text message factory."""
        msg = msg_response_text("Great job!", is_partial=False, stream_id="stream-1")
        
        assert msg.type == MessageType.RESPONSE_TEXT
        assert msg.data["text"] == "Great job!"
        assert msg.data["is_partial"] == False
    
    def test_msg_connected(self):
        """Test connected message factory."""
        msg = msg_connected("stream-123", "session-456")
        
        assert msg.type == MessageType.CONNECTED
        # stream_id is the top-level field, session_id is in data
        assert msg.stream_id == "stream-123"
        assert msg.data["session_id"] == "session-456"
    
    def test_msg_error(self):
        """Test error message factory."""
        msg = msg_error("Connection failed", "CONN_ERROR", "stream-1")
        
        assert msg.type == MessageType.ERROR
        assert msg.data["message"] == "Connection failed"
        assert msg.data["code"] == "CONN_ERROR"


# ============================================================
# TEST: ThinkingBuffer
# ============================================================

class TestThinkingBuffer:
    """Test ThinkingBuffer pause/resume logic."""
    
    def test_create_thinking_buffer(self):
        """Test creating ThinkingBuffer."""
        buffer = create_thinking_buffer(
            pause_timeout=1.0,
            merge_window=0.5,
        )
        
        assert buffer.config.pause_timeout_s == 1.0
        assert buffer.config.merge_window_s == 0.5
        assert buffer.state == ThinkingState.IDLE
    
    def test_initial_state(self):
        """Test initial buffer state."""
        buffer = ThinkingBuffer()
        
        assert buffer.state == ThinkingState.IDLE
        assert buffer.is_thinking == False
        assert buffer.current_text == ""
    
    @pytest.mark.asyncio
    async def test_add_partial_starts_waiting(self):
        """Test adding partial text starts waiting state."""
        buffer = ThinkingBuffer()
        
        action = await buffer.add_partial("Hello")
        
        assert action == ThinkingAction.WAIT
        assert buffer.current_text == "Hello"
    
    @pytest.mark.asyncio
    async def test_finalize_starts_thinking(self):
        """Test finalizing utterance starts thinking."""
        buffer = ThinkingBuffer()
        
        # Add partial first
        await buffer.add_partial("Hello")
        
        # Finalize
        action = await buffer.finalize("Hello world")
        
        assert action == ThinkingAction.START
        assert buffer.state == ThinkingState.THINKING
    
    @pytest.mark.asyncio
    async def test_cancel_keywords_detected(self):
        """Test cancel keywords are detected."""
        buffer = ThinkingBuffer()
        
        action = await buffer.add_partial("stop")
        
        assert action == ThinkingAction.CANCEL
        assert buffer.state == ThinkingState.IDLE
    
    @pytest.mark.asyncio
    async def test_cancel_keywords_wait_never_mind(self):
        """Test 'never mind' cancels."""
        buffer = ThinkingBuffer()
        
        action = await buffer.add_partial("never mind")
        
        assert action == ThinkingAction.CANCEL
    
    def test_continuation_detection(self):
        """Test continuation keyword detection."""
        buffer = ThinkingBuffer()
        
        # Test with continuation keywords
        assert buffer._detect_continuation("I like cats", "and dogs") == True
        assert buffer._detect_continuation("I have a", "but also") == True
        
        # Test without continuation
        assert buffer._detect_continuation("I like cats", "What time is") == False
    
    def test_context_merging(self):
        """Test context merging logic."""
        buffer = ThinkingBuffer()
        
        merged = buffer._merge_contexts("I want to learn", "and practice English")
        assert "I want to learn" in merged
        assert "and practice English" in merged
    
    def test_complete_resets_state(self):
        """Test completing thinking resets state."""
        buffer = ThinkingBuffer()
        buffer._state = ThinkingState.THINKING
        buffer._current_context = "test context"
        
        buffer.complete("Great job!")
        
        assert buffer.state == ThinkingState.IDLE
        assert buffer._previous_response == "Great job!"
    
    def test_reset_clears_everything(self):
        """Test reset clears all state."""
        buffer = ThinkingBuffer()
        buffer._partial_texts = ["hello", "world"]
        buffer._current_context = "test"
        buffer._state = ThinkingState.THINKING
        
        buffer.reset()
        
        assert buffer.state == ThinkingState.IDLE
        assert buffer._partial_texts == []
        assert buffer._current_context == ""


# ============================================================
# TEST: ThinkingConfig
# ============================================================

class TestThinkingConfig:
    """Test ThinkingConfig defaults and customization."""
    
    def test_default_config(self):
        """Test default configuration values."""
        config = ThinkingConfig()
        
        assert config.pause_timeout_s == 1.5
        assert config.merge_window_s == 0.8
        assert config.min_word_overlap == 2
        assert "stop" in config.cancel_keywords
        assert "and" in config.continuation_keywords
    
    def test_custom_config(self):
        """Test custom configuration."""
        config = ThinkingConfig(
            pause_timeout_s=2.0,
            merge_window_s=1.0,
        )
        
        assert config.pause_timeout_s == 2.0
        assert config.merge_window_s == 1.0


# ============================================================
# INTEGRATION TESTS (with mocks)
# ============================================================

class TestDualStreamIntegration:
    """Integration tests for dual-stream components."""
    
    @pytest.mark.asyncio
    async def test_thinking_buffer_callback(self):
        """Test ThinkingBuffer callback integration."""
        buffer = ThinkingBuffer()
        
        received_actions = []
        
        async def on_action(action: ThinkingAction, context: str):
            received_actions.append((action, context))
        
        buffer.set_callback(on_action)
        
        # Finalize should trigger START callback
        await buffer.add_partial("Hello")
        await buffer.finalize("Hello world")
        
        # Give async tasks time to run
        await asyncio.sleep(0.1)
        
        assert len(received_actions) == 1
        assert received_actions[0][0] == ThinkingAction.START
        assert received_actions[0][1] == "Hello Hello world"


# ============================================================
# RUN TESTS
# ============================================================

if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
