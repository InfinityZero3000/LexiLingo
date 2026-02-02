# Dual-Stream Architecture v5.0 - Implementation Plan

> **Document**: Kế hoạch tích hợp kiến trúc Dual-Stream vào LexiLingo AI  
> **Version**: 5.0  
> **Created**: 2026-02-02  
> **Status**: Planning

---

## 1. Tổng Quan

### 1.1 Mục Tiêu

Tích hợp kiến trúc **Dual-Stream** (lấy cảm hứng từ NVIDIA PersonaPlex) vào hệ thống AI tutor, cho phép:

- **Streaming STT**: Real-time transcription với VAD-based interruption detection
- **Streaming TTS**: Chunked audio output để giảm perceived latency
- **Parallel Processing**: Listen + Speak đồng thời
- **Smart Thinking**: Tạm dừng/tiếp tục suy luận khi user sửa câu hoặc nói tiếp

### 1.2 Kiến Trúc Tổng Quan

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     DUAL-STREAM ARCHITECTURE v5.0                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                    DUAL-STREAM ORCHESTRATOR                             ││
│  │                                                                         ││
│  │  ┌───────────────────┐   ┌──────────────────┐   ┌───────────────────┐   ││
│  │  │  LISTENING STREAM │   │  THINKING STREAM │   │  SPEAKING STREAM  │   ││
│  │  │  (Async Audio)    │   │  (LLM Reasoning) │   │  (TTS Output)     │   ││
│  │  │                   │   │                  │   │                   │   ││
│  │  │  • WebSocket In   │   │  • GraphCAG      │   │  • Chunked TTS    │   ││
│  │  │  • Streaming STT  │   │  • Smart Pause   │   │  • WebSocket Out  │   ││
│  │  │  • VAD Detection  │   │  • Context Merge │   │  • Interruptible  │   ││
│  │  │  • Interruption   │◀──│  • Resume Logic  │──▶│  • Pre-cache      │   ││
│  │  │                   │   │                  │   │                   │   ││
│  │  └─────────┬─────────┘   └────────┬─────────┘   └─────────┬─────────┘   ││
│  │            │                      │                       │             ││
│  │            └──────────────────────┼───────────────────────┘             ││
│  │                                   │                                     ││
│  │                    ┌──────────────▼──────────────┐                      ││
│  │                    │      SHARED STATE           │                      ││
│  │                    │  (Thread-safe, Redis-backed)│                      ││
│  │                    └─────────────────────────────┘                      ││
│  │                                                                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
│  LATENCY TARGETS:                                                           │
│  • First audio output: <200ms (streaming TTS starts before full response)   │
│  • Interruption response: <100ms (VAD + TTS stop)                           │
│  • Context switch: <50ms (thinking pause/resume)                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────┐
│         LEXILINGO DUAL-STREAM ARCHITECTURE v5.0                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              ASYNC DUAL-STREAM ORCHESTRATOR                 ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │                                                             ││
│  │   STREAM 1: Listening Stream (Async)                        ││
│  │   ─────────────────────────────────────                     ││
│  │   ┌─────────────┐    ┌─────────────┐    ┌──────────────┐    ││
│  │   │ Audio Chunk │───▶│ Whisper VAD │───▶│ Partial Text │    ││
│  │   │ (Streaming) │    │ (Real-time) │    │ (WebSocket)  │    ││
│  │   └─────────────┘    └─────────────┘    └──────┬───────┘    ││
│  │                                                │            ││
│  │   STREAM 2: Analysis Stream (Parallel)         │            ││
│  │   ────────────────────────────────────        ▼             ││
│  │   ┌─────────────┐    ┌─────────────┐    ┌──────────────┐    ││
│  │   │ Qwen Engine │◀───│ State Buffer│◀───│ Full Text    │    ││
│  │   │ (Processing)│    │ (Sync)      │    │ (On Pause)   │    ││
│  │   └─────┬───────┘    └─────────────┘    └──────────────┘    ││
│  │         │                                                   ││
│  │   STREAM 3: Speaking Stream (Async)                         ││
│  │   ─────────────────────────────────                         ││
│  │         ▼                                                   ││
│  │   ┌─────────────┐    ┌─────────────┐    ┌──────────────┐    ││
│  │   │ Response Gen│───▶│ Piper TTS   │───▶│ Audio Stream │    ││
│  │   │ (Streaming) │    │ (Chunked)   │    │ (WebSocket)  │    ││
│  │   └─────────────┘    └─────────────┘    └──────────────┘    ││
│  │                                                             ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  KEY FEATURES:                                                  │
│  ✓ Streaming STT: Real-time transcription                       │
│  ✓ Interruption Detection: VAD-based, can stop TTS              │
│  ✓ Chunked TTS: Stream audio while generating                   │
│  ✓ Parallel Processing: Listen while speaking                   │
│  ✓ State Sync: Shared state between streams                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Task Breakdown

### Phase 1: Core Infrastructure (2-3 days)

| Task | Description | Status |
|------|-------------|--------|
| 1.1 | Create `DualStreamState` extended from `GraphCAGState` | [ ] |
| 1.2 | Create `StreamingSTTService` with VAD and interruption detection | [ ] |
| 1.3 | Create `StreamingTTSService` with chunked audio output | [ ] |
| 1.4 | Create `ThinkingBuffer` for smart pause/resume thinking | [ ] |

### Phase 2: Dual-Stream Orchestrator (2-3 days)

| Task | Description | Status |
|------|-------------|--------|
| 2.1 | Create `DualStreamOrchestrator` main class | [ ] |
| 2.2 | Implement `ListeningStream` (async audio processing) | [ ] |
| 2.3 | Implement `ThinkingStream` (context-aware LLM reasoning) | [ ] |
| 2.4 | Implement `SpeakingStream` (TTS output streaming) | [ ] |
| 2.5 | Implement stream synchronization and state sharing | [ ] |

### Phase 3: Smart Thinking & Context Management (1-2 days)

| Task | Description | Status |
|------|-------------|--------|
| 3.1 | Implement utterance boundary detection | [ ] |
| 3.2 | Implement thinking interruption handler | [ ] |
| 3.3 | Implement context continuation logic | [ ] |
| 3.4 | Integrate GraphCAG cache for fast context lookup | [ ] |

### Phase 4: API & WebSocket Integration (1-2 days)

| Task | Description | Status |
|------|-------------|--------|
| 4.1 | Create WebSocket endpoint `/ws/conversation/stream` | [ ] |
| 4.2 | Create streaming response protocol | [ ] |
| 4.3 | Implement graceful degradation fallback | [ ] |

### Phase 5: Testing & Optimization (1-2 days)

| Task | Description | Status |
|------|-------------|--------|
| 5.1 | Unit tests for each streaming service | [ ] |
| 5.2 | Integration tests for full pipeline | [ ] |
| 5.3 | Performance benchmarking | [ ] |
| 5.4 | Latency optimization | [ ] |

---

## 3. File Structure

```
ai-service/api/services/dual_stream/
├── __init__.py                     # Package exports
├── dual_stream_state.py            # Extended state schema
├── streaming_stt_service.py        # Real-time STT
├── streaming_tts_service.py        # Chunked TTS
├── thinking_buffer.py              # Smart pause/resume
├── dual_stream_orchestrator.py     # Main coordinator
└── protocol.py                     # WebSocket message types

ai-service/api/routes/
└── websocket_stream.py             # WebSocket endpoint

ai-service/tests/test_dual_stream/
├── test_streaming_stt.py
├── test_streaming_tts.py
├── test_thinking_buffer.py
├── test_orchestrator.py
└── test_websocket_integration.py
```

---

## 4. Component Details

### 4.1 StreamingSTTService

```python
class StreamingSTTService:
    """
    Streaming Speech-to-Text with Voice Activity Detection.
    
    Features:
    - Real-time audio chunk processing
    - VAD-based utterance boundary detection
    - Interruption detection (user speaks while AI is talking)
    - Partial transcript streaming
    """
    
    async def stream_transcribe(
        self, 
        audio_chunks: AsyncGenerator[bytes, None]
    ) -> AsyncGenerator[TranscriptResult, None]:
        """
        Yields:
            - partial: Intermediate transcripts (for UI feedback)
            - final: Complete utterance (triggers thinking)
            - interruption: User interrupted AI speech
        """
```

### 4.2 StreamingTTSService

```python
class StreamingTTSService:
    """
    Streaming Text-to-Speech with chunk-based output.
    
    Features:
    - Sentence-level chunking for fast first output
    - Interruptible: can stop mid-sentence
    - Pre-caching common phrases (from GraphCAG)
    - Smooth audio concatenation
    """
    
    async def stream_speak(
        self,
        text_generator: AsyncGenerator[str, None]
    ) -> AsyncGenerator[AudioChunk, None]:
        """Stream audio chunks as text becomes available."""
```

### 4.3 ThinkingBuffer

```python
class ThinkingBuffer:
    """
    Manages LLM thinking state with smart pause/resume.
    
    Scenarios:
    1. User finishes speaking → Start thinking
    2. User continues speaking → Pause thinking, merge context
    3. User corrects themselves → Cancel thinking, restart
    4. User asks new question → Cancel thinking, new context
    """
    
    def __init__(
        self,
        pause_timeout: float = 1.5,    # Seconds to wait for more input
        merge_window: float = 0.5,      # Window for context merging
    ):
```

### 4.4 DualStreamOrchestrator

```python
class DualStreamOrchestrator:
    """
    Coordinates Listening, Thinking, and Speaking streams.
    
    Architecture:
    - Three async streams running concurrently
    - Shared state with thread-safe access
    - Event-driven communication between streams
    """
    
    async def start_conversation(
        self,
        audio_input: AsyncGenerator[bytes, None],
        audio_output: Callable[[bytes], Awaitable[None]],
        text_output: Callable[[str], Awaitable[None]],
    ):
        """Main entry point for dual-stream conversation."""
```

---

## 5. WebSocket Protocol

### 5.1 Endpoint

```
ws://localhost:8001/ws/conversation/stream?session_id=xxx&user_id=xxx
```

### 5.2 Message Types

**Client → Server:**
- Binary audio chunks (PCM 16kHz mono)

**Server → Client:**

| Type | Description |
|------|-------------|
| `transcript_partial` | Intermediate STT result |
| `transcript_final` | Complete utterance |
| `thinking_start` | AI started processing |
| `thinking_stop` | AI stopped (interrupted or done) |
| `response_text` | Tutor response text |
| `response_audio_start` | Audio stream beginning |
| `response_audio_end` | Audio stream complete |
| `error` | Error message |

---

## 6. Verification Plan

### 6.1 Automated Tests

```bash
# Run all dual-stream unit tests
cd /path/to/LexiLingo/ai-service
python -m pytest tests/test_dual_stream/ -v
```

### 6.2 Manual Tests

| Test Case | Expected Result |
|-----------|-----------------|
| User speaks, AI responds | Response < 500ms |
| User interrupts AI | TTS stops immediately |
| User continues speaking | Context merged correctly |
| WebSocket disconnect | Graceful fallback |

---

## 7. Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Core Services | 2-3 days | None |
| Phase 2: Orchestrator | 2-3 days | Phase 1 |
| Phase 3: Smart Thinking | 1-2 days | Phase 2 |
| Phase 4: WebSocket API | 1-2 days | Phase 2 |
| Phase 5: Testing | 1-2 days | All |

**Total Estimated Time**: 7-12 days

---

## 8. Dependencies

- Faster-Whisper (existing) - STT
- Piper TTS (existing) - TTS
- LangGraph (existing) - Orchestration
- Redis (existing) - State caching
- KuzuDB (existing) - Knowledge Graph

---

## 9. Rollback Plan

Nếu có vấn đề:
1. Disable WebSocket endpoint trong `main.py`
2. Các API cũ (`/ai/analyze`, `/ai/chat`) vẫn hoạt động bình thường
3. Không có breaking changes với existing clients

---

> **Author**: LexiLingo AI Team  
> **Last Updated**: 2026-02-02
