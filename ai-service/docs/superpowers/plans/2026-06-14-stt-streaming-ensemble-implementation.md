# STT Streaming Ensemble Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one bounded-memory realtime STT service using WebSocket PCM16 streaming, Moonshine primary recognition, selective Faster-Whisper verification, and final-only TRACE-CAG delivery.

**Architecture:** Add a focused `api/services/stt/` package whose engine adapters are isolated behind protocols and whose `VoiceSession` owns bounded queues, endpointing, transcript state, and cleanup. `api/routes/stt.py` becomes a thin HTTP/WebSocket transport adapter; legacy upload and ModelGateway paths delegate to the same registry rather than loading separate Whisper instances.

**Tech Stack:** Python 3.11+, FastAPI WebSocket, Pydantic 2, asyncio, NumPy, Moonshine Voice, Silero VAD, Faster-Whisper, pytest, pytest-asyncio.

**Reference spec:** `docs/superpowers/specs/2026-06-14-stt-streaming-ensemble-design.md`

---

## Chunk 1: Core Protocol and Bounded State

### Task 1: Configuration, schemas, and errors

**Files:**
- Create: `api/services/stt/__init__.py`
- Create: `api/services/stt/config.py`
- Create: `api/services/stt/schemas.py`
- Create: `api/services/stt/errors.py`
- Test: `tests/stt/test_config.py`
- Test: `tests/stt/test_schemas.py`

- [x] Write failing tests for defaults, environment parsing, invalid segment caps, invalid confidence thresholds, start-message validation, final event fields, and stable error codes.
- [x] Run `pytest tests/stt/test_config.py tests/stt/test_schemas.py -q` and confirm failure.
- [x] Implement `STTConfig`, protocol enums, control/event models, transcript result models, and `STTProtocolError`.
- [x] Run the focused tests and confirm pass.
- [x] Commit the chunk.

### Task 2: Binary ingest and bounded buffers

**Files:**
- Create: `api/services/stt/audio_ingest.py`
- Create: `api/services/stt/ring_buffer.py`
- Create: `api/services/stt/temp_audio_writer.py`
- Test: `tests/stt/test_audio_ingest.py`
- Test: `tests/stt/test_storage.py`

- [x] Write failing tests for the 14-byte binary header, payload duration, duplicate/gap handling, fixed ring capacity, spool rotation, close, and TTL cleanup.
- [x] Run focused tests and confirm failure.
- [x] Implement frame parsing, sequence tracking, fixed PCM ring buffer, bounded rotating writer, and stale-file cleanup.
- [x] Run focused tests and confirm pass.
- [x] Commit the chunk.

## Chunk 2: Recognition Pipeline

### Task 3: Engine protocols and registry

**Files:**
- Create: `api/services/stt/engines/__init__.py`
- Create: `api/services/stt/engines/base.py`
- Create: `api/services/stt/engines/moonshine.py`
- Create: `api/services/stt/engines/faster_whisper.py`
- Create: `api/services/stt/model_registry.py`
- Modify: `requirements.txt`
- Test: `tests/stt/test_model_registry.py`

- [x] Write fake-engine tests for single-load behavior, degraded readiness, verifier semaphore, and close.
- [x] Run focused tests and confirm failure.
- [x] Define primary session and verifier protocols.
- [x] Implement lazy optional Moonshine import with callback-to-async event bridging.
- [x] Implement shared Faster-Whisper segment verification using PCM WAV temp files and calibrated score provenance.
- [x] Implement registry startup/readiness/degraded mode without duplicate model loads.
- [x] Add `moonshine-voice` and `silero-vad` dependencies with compatibility comments.
- [x] Run focused tests and confirm pass.
- [x] Commit the chunk.

### Task 4: VAD, transcript state, routing, and finalization

**Files:**
- Create: `api/services/stt/vad_endpointing.py`
- Create: `api/services/stt/transcript_state.py`
- Create: `api/services/stt/verifier_router.py`
- Create: `api/services/stt/transcript_normalizer.py`
- Create: `api/services/stt/sentence_finalizer.py`
- Test: `tests/stt/test_vad_endpointing.py`
- Test: `tests/stt/test_transcript_pipeline.py`

- [x] Write failing tests for speech/silence endpointing, pre-roll, hard cap, valid state transitions, conservative normalization, verify rules, verifier failure, and uncertain finals.
- [x] Run focused tests and confirm failure.
- [x] Implement Silero adapter with energy fallback.
- [x] Implement state, router, normalizer, and finalizer.
- [x] Run focused tests and confirm pass.
- [x] Commit the chunk.

## Chunk 3: Sessions and Transport

### Task 5: Voice session and session manager

**Files:**
- Create: `api/services/stt/metrics.py`
- Create: `api/services/stt/voice_session.py`
- Create: `api/services/stt/session_manager.py`
- Create: `api/services/stt/cleanup.py`
- Test: `tests/stt/test_voice_session.py`
- Test: `tests/stt/test_session_manager.py`

- [x] Write failing tests for bounded input queue, ack semantics, partial coalescing, candidate/final preservation, stop flush, idle expiry, hard limit, reconnect, and idempotent cleanup.
- [x] Run focused tests and confirm failure.
- [x] Implement the per-session worker pipeline and event stream.
- [x] Implement active-session limits, same-worker resume, expiry, cleanup, and in-memory metrics.
- [x] Run focused tests and confirm pass.
- [x] Commit the chunk.

### Task 6: WebSocket and compatibility HTTP routes

**Files:**
- Rewrite: `api/routes/stt.py`
- Modify: `api/main.py`
- Modify: `api/services/stt_service.py`
- Test: `tests/stt/test_stt_routes.py`

- [x] Write failing route tests for auth/start, binary audio, ack, invalid format, duplicate/gap, backpressure, stop/final close, resume, and bounded upload.
- [x] Run focused tests and confirm failure.
- [x] Add STT registry/session manager to FastAPI lifespan.
- [x] Implement `/api/v1/stt/stream` with JSON control and binary frame handling.
- [x] Rewrite short-clip upload to stream into a bounded temp file and delegate to the unified verifier.
- [x] Keep `get_stt_service()` as a compatibility façade without owning a model.
- [x] Run focused tests and confirm pass.
- [x] Commit the chunk.

## Chunk 4: Downstream Migration and Production Hardening

### Task 7: TRACE-CAG final-only adapter and legacy migration

**Files:**
- Create: `api/services/stt/trace_cag_adapter.py`
- Modify: `api/routes/lexi_chat.py`
- Modify: `api/services/trace_cag/state.py`
- Modify: `api/services/trace_cag/edges.py`
- Modify: `api/services/trace_cag/nodes_v2.py`
- Modify: `api/services/gateway_setup.py`
- Modify: `api/services/handlers/whisper_handler.py`
- Test: `tests/stt/test_trace_cag_adapter.py`
- Modify: `tests/test_lexi_session_management.py`
- Modify: `tests/trace_cag/test_edges_routing.py`

- [x] Write failing tests proving partial/candidate events are rejected and finals preserve confidence/timestamps/uncertainty.
- [x] Replace raw-audio TRACE-CAG STT routing with text/final metadata.
- [x] Make legacy Lexi base64 transcription size-limited and delegated to the unified service during migration.
- [x] Make ModelGateway Whisper registration delegate to the unified verifier and accept the corrected `audio` contract.
- [x] Run affected STT, Lexi, and TRACE-CAG tests.
- [x] Commit the chunk.

### Task 8: Environment, long-session tests, and verification

**Files:**
- Modify: `.env.example`
- Modify: `.env.development`
- Modify: `.env.production`
- Modify: `api/core/config.py`
- Create: `tests/stt/test_long_session.py`
- Create: `docs/stt-production-checklist.md`

- [x] Replace realtime STT defaults with the unified `STT_*` namespace and remove `large-v3` realtime default.
- [x] Add deterministic 10-minute synthetic stream, queue overload, reconnect, engine failure, VAD fallback, and cleanup tests.
- [x] Run `pytest tests/stt -q`.
- [x] Run affected existing suites: `pytest tests/test_lexi_session_management.py tests/trace_cag/test_edges_routing.py tests/trace_cag/test_pipeline_integration.py -q`.
- [x] Run `python -m compileall api/services/stt api/routes/stt.py`.
- [x] Run `git diff --check`.
- [x] Document production model provisioning, sticky WebSocket routing, proxy settings, capacity calibration, metrics, and rollback.
- [x] Commit final hardening changes.

## Execution Notes

- Real model tests remain optional markers because CI must not download weights.
- Moonshine native failures must degrade to Faster-Whisper chunk mode or a
  `MODEL_NOT_READY` event, never crash application startup.
- Silero import/runtime failure must activate the energy VAD fallback.
- The first implementation supports same-worker resume only; deploy one worker
  or sticky routing for `/api/v1/stt/stream`.
- Browser/mobile capture changes are outside this repository and require a
  separate client implementation.
