# Dual-Stream Architecture - Task Tracker

> **Project**: LexiLingo AI  
> **Feature**: Dual-Stream Architecture v5.0  
> **Created**: 2026-02-02  
> **Status**: 🔵 In Planning

---

## Overview

Tích hợp kiến trúc Dual-Stream cho phép:
- Real-time streaming STT/TTS
- Parallel listen + speak
- Smart thinking với pause/resume

---

## Task Progress

### Phase 1: Core Infrastructure
| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 1.1 | Create `DualStreamState` | - | ✅ DONE | Extended from GraphCAGState |
| 1.2 | Create `StreamingSTTService` | - | ✅ DONE | VAD + interruption detection |
| 1.3 | Create `StreamingTTSService` | - | ✅ DONE | Chunked audio output |
| 1.4 | Create `ThinkingBuffer` | - | ✅ DONE | Smart pause/resume |

### Phase 2: Dual-Stream Orchestrator
| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 2.1 | Create `DualStreamOrchestrator` | - | ✅ DONE | Main coordinator |
| 2.2 | Implement `ListeningStream` | - | ✅ DONE | Async audio processing |
| 2.3 | Implement `ThinkingStream` | - | ✅ DONE | LLM reasoning |
| 2.4 | Implement `SpeakingStream` | - | ✅ DONE | TTS streaming |
| 2.5 | Stream synchronization | - | ✅ DONE | Shared state |

### Phase 3: Smart Thinking
| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 3.1 | Utterance boundary detection | - | ✅ DONE | |
| 3.2 | Thinking interruption handler | - | ✅ DONE | |
| 3.3 | Context continuation logic | - | ✅ DONE | |
| 3.4 | GraphCAG cache integration | - | ✅ DONE | |

### Phase 4: API & WebSocket
| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 4.1 | WebSocket endpoint | - | ✅ DONE | `/ws/conversation/stream` |
| 4.2 | Streaming protocol | - | ✅ DONE | Message types |
| 4.3 | Fallback handler | - | ✅ DONE | Graceful degradation |

### Phase 5: Testing
| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 5.1 | Unit tests | - | ⬜ TODO | Each service |
| 5.2 | Integration tests | - | ⬜ TODO | Full pipeline |
| 5.3 | Performance benchmark | - | ⬜ TODO | Latency targets |
| 5.4 | Optimization | - | ⬜ TODO | |

---

## Status Legend

| Icon | Meaning |
|------|---------|
| ⬜ TODO | Not started |
| 🔵 IN PROGRESS | Currently working |
| ✅ DONE | Completed |
| ❌ BLOCKED | Blocked by issue |
| ⏸️ ON HOLD | Paused |

---

## Timeline

| Phase | Est. Duration | Start | End | Status |
|-------|---------------|-------|-----|--------|
| Phase 1 | 2-3 days | - | - | ⬜ |
| Phase 2 | 2-3 days | - | - | ⬜ |
| Phase 3 | 1-2 days | - | - | ⬜ |
| Phase 4 | 1-2 days | - | - | ⬜ |
| Phase 5 | 1-2 days | - | - | ⬜ |

**Total**: 7-12 days

---

## Files to Create

```
ai-service/api/services/dual_stream/
├── __init__.py
├── dual_stream_state.py
├── streaming_stt_service.py
├── streaming_tts_service.py
├── thinking_buffer.py
├── dual_stream_orchestrator.py
└── protocol.py

ai-service/api/routes/
└── websocket_stream.py
```

---

## Related Docs

- [DUAL_STREAM_ARCHITECTURE_PLAN.md](./DUAL_STREAM_ARCHITECTURE_PLAN.md) - Chi tiết implementation

---

> **Last Updated**: 2026-02-02
