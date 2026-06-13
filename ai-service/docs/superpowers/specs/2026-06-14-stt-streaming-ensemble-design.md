# STT Streaming Ensemble Design

**Date:** 2026-06-14
**Status:** Written specification reviewed, pending user approval
**Scope:** LexiLingo `ai-service` realtime speech-to-text path

## 1. Goal

Replace the current file/base64-oriented STT paths with one bounded-memory,
session-based streaming service that:

- receives PCM16 mono 16 kHz audio over WebSocket binary frames;
- emits low-latency partial transcripts for the UI;
- emits normalized final transcripts with timestamps and confidence metadata;
- sends only final transcripts to TRACE-CAG;
- uses Moonshine Streaming Tiny as the primary recognizer and Faster-Whisper
  `base.en` as a selective verifier;
- remains stable for 30-60 minute sessions without retaining the complete audio
  stream in RAM;
- provides bounded queues, backpressure, reconnect, cleanup, metrics, and
  controlled model fallbacks;
- keeps the protocol ready for later duplex TTS and barge-in support.

## 2. Current Problems

The existing implementation has two independent STT paths:

1. `api/services/stt_service.py` serves the upload endpoint and defaults to
   `large-v3` through `api/core/config.py`.
2. `api/services/handlers/whisper_handler.py` is registered in ModelGateway and
   defaults to `base`.

This causes conflicting configuration, loading, output schemas, and runtime
behavior. Additional confirmed issues are:

- `api/routes/stt.py` reads an entire upload into memory before transcription.
- `api/routes/lexi_chat.py` accepts base64 audio and invokes Whisper with
  `audio_bytes`, while `WhisperHandler.transcribe()` accepts `audio`. This call
  fails before inference.
- TRACE-CAG contains a second `audio_bytes` STT entry point, but its normal
  Lexi flow transcribes before entering the graph. The graph voice path is
  therefore inconsistent and partially unreachable.
- `WHISPER_MODEL_PATH=models/whisper` points at a cache parent rather than a
  guaranteed CTranslate2 model directory.
- ModelGateway's loading lock does not bound concurrent inference.
- Whisper calls have a request-style timeout. A recording session must not be
  represented by one long-running inference request.
- There is no bounded per-session audio queue, endpointing service, reconnect
  protocol, long-session cleanup, or final-only TRACE-CAG contract.
- Current confidence conversion (`1 + avg_logprob`) is not calibrated.

## 3. Scope and Non-Goals

### In scope

- Backend WebSocket protocol and binary audio ingest.
- Unified STT configuration and lifecycle.
- Session management, sequence validation, bounded queues, and backpressure.
- Bounded audio ring buffer and rotating temporary segment storage.
- VAD/endpointing abstraction with Silero and an energy-based fallback.
- Moonshine streaming adapter and Faster-Whisper verifier adapter.
- Partial, candidate, and final transcript state.
- Selective verification and uncertainty handling.
- TRACE-CAG final transcript adapter.
- Metrics, structured logs, cleanup, graceful shutdown, and automated tests.
- A compatibility HTTP endpoint for short offline uploads during migration.

### Out of scope

- Browser or mobile AudioWorklet implementation in this repository.
- WebRTC signaling, TTS streaming, echo cancellation, and barge-in behavior.
- Cross-worker migration of active decoder state.
- Persisting raw production audio or base64 audio.
- Pronunciation scoring model redesign.
- Guaranteeing model accuracy or latency without target-hardware benchmarks.

## 4. Architectural Decision

Use a streaming ensemble:

```text
WebSocket PCM frames
  -> AudioIngest
  -> VoiceSession bounded input queue
  -> RingBuffer + bounded rotating spool
  -> VAD/Endpointing
  -> Moonshine primary
  -> partial UI events
  -> candidate utterance
  -> VerifierRouter
  -> optional Faster-Whisper verification
  -> TranscriptNormalizer
  -> final event
  -> TraceCAGAdapter
```

This is preferred over:

- **Whisper-only chunking:** fewer dependencies, but weaker partial latency and
  higher sustained CPU use.
- **Vosk plus Whisper:** very small and stream-friendly, but lower expected
  English transcription quality for this learning use case.

Moonshine is isolated behind an engine protocol. If its package, model, or
runtime is unavailable, the service can run in degraded Whisper-chunk mode
without changing transport or downstream contracts.

## 5. Module Boundaries

Create `api/services/stt/` with focused units:

| Module | Responsibility |
|---|---|
| `config.py` | Parse and validate all STT environment settings. |
| `schemas.py` | Control messages and outbound event models. |
| `errors.py` | Stable STT error codes and protocol exceptions. |
| `model_registry.py` | Load each STT/VAD engine once and expose readiness. |
| `audio_ingest.py` | Decode frame headers, validate format and sequence. |
| `ring_buffer.py` | Retain only the configured recent PCM window. |
| `temp_audio_writer.py` | Maintain bounded rotating PCM/WAV spool files. |
| `vad_endpointing.py` | Detect speech boundaries and enforce segment caps. |
| `engines/base.py` | Primary and verifier engine protocols. |
| `engines/moonshine.py` | Moonshine streaming adapter. |
| `engines/faster_whisper.py` | Segment verifier and degraded primary mode. |
| `verifier_router.py` | Decide accept, verify, or uncertain. |
| `transcript_state.py` | Maintain partial/candidate/final transitions. |
| `transcript_normalizer.py` | Apply conservative final-text normalization. |
| `sentence_finalizer.py` | Merge engine results into one final event. |
| `trace_cag_adapter.py` | Submit only final transcript payloads downstream. |
| `voice_session.py` | Own one session pipeline and its bounded tasks/queues. |
| `session_manager.py` | Create, resume, expire, and close sessions. |
| `metrics.py` | STT counters, gauges, histograms, and structured fields. |
| `cleanup.py` | Expire sessions and remove stale spool files. |

`api/routes/stt.py` becomes the transport adapter. It must not own model logic.
The old `STTService` and `WhisperHandler` cease to be independent public STT
implementations. ModelGateway may retain a compatibility registration that
delegates to the unified verifier, but it must not load a second Whisper model.

Core interfaces are intentionally narrow:

```python
class PrimarySTTEngine(Protocol):
    async def create_session(self, config: SessionAudioConfig) -> PrimarySTTSession: ...

class PrimarySTTSession(Protocol):
    async def push_audio(self, pcm16: bytes, start_ms: int, end_ms: int) -> PartialResult | None: ...
    async def finalize(self, audio: AudioSegment) -> PrimaryResult: ...
    async def close(self) -> None: ...

class VerifierEngine(Protocol):
    async def verify(self, audio: AudioSegment, language: str) -> VerificationResult: ...

class FinalTranscriptSink(Protocol):
    async def submit(self, event: FinalTranscriptEvent) -> None: ...
```

Engine result types contain text, timestamps, language, score values, and score
provenance. They do not know about WebSockets or TRACE-CAG. `VoiceSession`
coordinates these interfaces but does not instantiate model weights.

## 6. Model Lifecycle

`STTModelRegistry` is created in FastAPI lifespan startup and closed during
shutdown.

- Moonshine, Faster-Whisper, and Silero load at most once per process.
- Startup validates configured local paths. A missing explicit path fails fast.
- A model ID without a local path may download only when the deployment permits
  it; production deployment should pre-bake or pre-download model artifacts.
- Verifier concurrency is controlled by one process-wide semaphore.
- Primary streaming capacity is controlled by active session limits and, if the
  runtime is not safe for concurrent decoder state, by an engine worker pool.
- Session objects own decoder session state, not model weights.

Readiness policy is explicit:

- If STT is disabled, application readiness does not depend on STT.
- If Moonshine fails and degraded Whisper-primary mode is enabled and ready,
  the application reports STT as `degraded` and accepts sessions with reduced
  partial behavior.
- If neither primary nor degraded primary is ready, STT reports `unavailable`;
  the rest of the AI service may start, but new STT sessions receive
  `MODEL_NOT_READY`.
- If only the verifier is unavailable, STT remains ready and low-confidence
  finals are marked uncertain according to fallback policy.
- An invalid explicit model path is a configuration error and fails startup,
  because silently ignoring an operator-supplied path hides deployment faults.

Default realtime settings:

- primary: Moonshine Streaming Tiny on CPU;
- verifier: Faster-Whisper `base.en`, CPU, `int8`, beam size 1;
- GPU override: `small.en`, CUDA, `float16`;
- `large-v3` is offline-only.

The Moonshine adapter must expose capability metadata. Confidence routing cannot
assume the engine supplies a calibrated probability. When calibrated confidence
is unavailable, the router uses transcript stability, no-speech/VAD evidence,
token probability if exposed, suspicious-text heuristics, use case, and a small
verification sample rate. Metrics identify the confidence source.

## 7. WebSocket Protocol

Endpoint: `GET /api/v1/stt/stream`

Authentication uses the existing service authentication mechanism before a
session is created. The first client message must be JSON `start` or `resume`.
Subsequent control messages are JSON; audio is binary.

### Start

```json
{
  "type": "start",
  "session_id": "s_123",
  "user_id": "u_123",
  "sample_rate": 16000,
  "channels": 1,
  "format": "pcm16",
  "language": "en",
  "use_case": "conversation",
  "client_started_at": 1781416800000
}
```

The authenticated identity is authoritative. A mismatched `user_id` is rejected.

### Binary frame

Each binary WebSocket message contains a fixed header followed by PCM bytes:

```text
version:u8 | flags:u8 | seq:u32be | client_ts_ms:u64be | pcm_payload:bytes
```

Binding sequence metadata to the payload avoids races caused by sending a JSON
`audio_meta` message separately. Version 1 accepts only little-endian signed
PCM16, mono, 16 kHz negotiated at start. Payload length must represent an
allowed 20-250 ms audio duration and contain an even number of bytes.

### Sequence policy

- `seq == last_seq + 1`: accept.
- `seq <= last_seq`: acknowledge as duplicate and do not process again.
- `seq > last_seq + 1`: record missing frames and emit a gap event; accept the
  new frame rather than blocking the realtime stream indefinitely.
- Reordered frames older than `last_seq` are treated as duplicates.

### Resume

```json
{"type":"resume","session_id":"s_123","last_seq":128}
```

Version 1 resume is guaranteed only when the request returns to the worker that
owns the live session. Deployments must use one worker or sticky routing for the
WebSocket endpoint. Redis may store session ownership and metadata, but active
Moonshine decoder state is not serialized. A wrong-worker or expired resume
returns `SESSION_EXPIRED` and requires a new session.

The server retains a disconnected session for a short configurable resume
window. It does not claim to replay audio the server never received. The client
may resend frames after its last acknowledged sequence; duplicate detection
prevents double transcription.

### Events

Server events include:

- `session_started`
- `ack`
- `stt.partial`
- `stt.candidate` (optional debug/development emission; not downstream)
- `stt.final`
- `stt.backpressure`
- `stt.gap`
- `stt.error`
- `session_closed`
- `pong`

Candidate events are internal by default. They can be exposed only under a
development flag.

## 8. Session and Memory Model

Each `VoiceSession` owns:

- immutable audio format and use-case metadata;
- `last_seq`, `last_ack_seq`, gap/duplicate counters, and reconnect count;
- a bounded audio input queue;
- a fixed-size recent-audio ring buffer;
- VAD and primary decoder session state;
- the current utterance buffer;
- bounded output/event queues;
- task handles and cancellation state;
- per-session metrics.

At 16 kHz mono PCM16, a 30-second ring buffer is approximately 960 KB. The
current utterance is capped at 15 seconds, approximately 480 KB. Historical
final transcript metadata may be capped in memory and emitted/persisted
incrementally.

Temporary audio storage uses rotating files with both age and size/count caps.
It is not an ever-growing session recording. Closed utterance audio is deleted
after verification unless debug capture is explicitly enabled. Debug files
have TTL cleanup and are disabled by default.

No realtime path stores or logs raw audio as base64.

## 9. VAD and Endpointing

The primary endpointing engine is Silero VAD with a simple RMS/energy detector
as fallback.

Defaults:

- frame: 20 ms internally;
- minimum speech: 250 ms;
- silence endpoint: 600 ms;
- pre-roll: 300 ms;
- speech padding: 200 ms;
- soft segment cap: 12 seconds;
- hard segment cap: 15 seconds.

Client batches up to 250 ms are split into internal frames before VAD. A silence
endpoint closes the utterance. The soft cap seeks a recent low-energy boundary;
the hard cap closes regardless, so verifier latency remains bounded. Very short
or no-speech segments are discarded or marked uncertain based on useful text.

On `stop`, the session flushes the active speech segment within the finalize
timeout, emits its final event when possible, then closes.

## 10. Transcript State and Verification

State transitions are:

```text
partial -> candidate -> final
```

- `partial` is replaceable UI state and never reaches TRACE-CAG.
- `candidate` is a closed utterance awaiting routing/verification.
- `final` is immutable for downstream processing.

Every final event contains:

- session, turn, and utterance IDs;
- normalized and optionally original text;
- start/end timestamps;
- language;
- confidence plus confidence source;
- selected model source;
- `verified`, `uncertain`, and `needs_confirmation`;
- verification reason and latency metadata.

Initial routing policy:

- accept a high-quality, non-suspicious primary result without verification;
- verify low-quality results;
- verify borderline results for scoring use cases, names, numbers, commands,
  code-switch indicators, unstable partials, or suspicious repetition;
- verify long candidates only after endpointing has bounded them;
- reduce optional verification under overload, never mandatory low-confidence
  verification unless the verifier is unavailable;
- if the verifier fails, use a strong primary result as `moonshine_only`;
  otherwise emit an uncertain final result requiring confirmation.

Thresholds are configuration defaults, not accuracy guarantees. They must be
calibrated from logged evaluation data rather than treated as universal.

## 11. TRACE-CAG Integration

`TraceCAGAdapter` accepts only `FinalTranscriptEvent`. Its public method cannot
accept raw bytes or partial/candidate event types.

The adapter maps a final event into the existing text-oriented Lexi/TRACE-CAG
entry point, preserving:

- `session_id`, `turn_id`, and `utterance_id`;
- final text and segment timestamps;
- language and confidence;
- source, verification, uncertainty, and confirmation flags.

When `uncertain=true`, downstream policy receives that fact and may ask the user
for confirmation. TRACE-CAG graph state must remove STT responsibility and raw
input `audio_bytes`; TTS output bytes remain separate and are not affected.

Final event delivery is decoupled from the audio ingest loop. Slow TRACE-CAG
processing cannot block receiving audio. The adapter uses a bounded downstream
queue or task handoff and records delivery failures explicitly.

## 12. Backpressure and Overload

All queues are bounded.

- A full audio queue emits `stt.backpressure`.
- The server first coalesces/drops stale partial output events.
- Candidate and final events are never silently dropped.
- Audio frames that cannot be accepted are reported with sequence information;
  the client must slow down or reconnect. The server does not pretend dropped
  audio was transcribed.
- New sessions are rejected with `SERVER_BUSY` when active capacity is reached.
- Optional verification is reduced under verifier saturation.
- Low-confidence candidates become uncertain if mandatory verification cannot
  complete within policy.

Acknowledgement means the frame was accepted into the server's bounded ingest
pipeline, not that it has been transcribed.

## 13. Error Handling

Stable protocol errors include:

- `AUTH_REQUIRED`
- `INVALID_START`
- `UNSUPPORTED_AUDIO_FORMAT`
- `INVALID_FRAME`
- `SESSION_NOT_FOUND`
- `SESSION_EXPIRED`
- `SESSION_BUSY`
- `SERVER_BUSY`
- `AUDIO_QUEUE_FULL`
- `MODEL_NOT_READY`
- `PRIMARY_STT_FAILED`
- `VERIFIER_FAILED`
- `VERIFIER_TIMEOUT`
- `VAD_FALLBACK_ACTIVE`
- `TEMP_STORAGE_FAILED`
- `INTERNAL_ERROR`

Engine and VAD failures do not crash the process. Fallback behavior is explicit
in events and metrics. Invalid model paths fail startup when the corresponding
engine is enabled.

## 14. Configuration

Introduce one `STTConfig` namespace using the `STT_*` variables from the
approved prompt. Validation additionally enforces:

- positive queue/session limits;
- `hard_cap >= max_segment`;
- `confidence_accept >= confidence_verify`;
- supported audio format and sample rate;
- valid compute type for the selected device;
- explicit local model paths exist;
- spool limits and TTL are bounded;
- production debug-audio capture requires an explicit override.

Legacy `WHISPER_*` and old `STT_MODEL_NAME` settings are supported for one
migration release with deprecation warnings, then removed.

## 15. HTTP Compatibility Migration

`POST /api/v1/stt/transcribe` remains temporarily for short offline clips and
tests. It:

- streams upload bytes to a bounded temporary file instead of `await read()`;
- enforces content length and duration limits;
- delegates to the unified Faster-Whisper engine;
- returns the same final transcript schema where practical;
- is documented as non-realtime and never used by Lexi realtime voice.

Lexi's `audio_base64` request field is deprecated, then removed after the client
uses the WebSocket path. During migration it is subject to a strict small-clip
limit and delegates to the same unified service; no second model is loaded.

## 16. Observability

Use the repository's telemetry/logging facilities through a focused STT metrics
adapter. Record:

- active sessions, starts, closes, reconnects, and close reason;
- audio received, gaps, duplicates, dropped/rejected frames;
- queue depth and peak;
- time to first partial, endpoint delay, final latency;
- primary and verifier latency/failure counts;
- verify rate and reason;
- average confidence, confidence source, uncertain rate;
- VAD speech ratio and fallback count;
- ring/spool size and cleanup results.

Structured segment logs include IDs, timing, model selection, verification
reason, and uncertainty. They exclude raw audio, base64, and full sensitive
conversation content. Text logging follows existing privacy configuration and
is truncated or hashed when detailed content is unnecessary.

## 17. Lifecycle and Cleanup

FastAPI lifespan performs:

1. validate STT configuration;
2. create model registry and session manager;
3. load required engines or mark optional degraded mode;
4. start expiry and spool cleanup tasks;
5. expose readiness only after required components are ready.

Shutdown:

1. reject new sessions;
2. notify and close WebSockets;
3. attempt bounded final flush;
4. cancel session tasks;
5. close file handles and delete non-debug spool files;
6. stop cleanup tasks;
7. unload model registry resources.

Cleanup is idempotent and runs for stop, disconnect expiry, hard limit, error,
and process shutdown.

## 18. Testing Strategy

Unit tests use fake VAD and STT engines so CI does not download model weights.
Required coverage:

- config validation and legacy mapping;
- binary frame parsing and audio validation;
- duplicate, gap, and reordered sequence handling;
- fixed ring-buffer memory bounds;
- spool rotation, close, and TTL cleanup;
- endpointing for short speech, silence, soft cap, and hard cap;
- transcript state transitions;
- verifier routing and overload behavior;
- normalizer conservatism for speaking/pronunciation use cases;
- primary, verifier, VAD, and temp-storage failure fallbacks;
- TRACE-CAG adapter rejects non-final inputs;
- session stop, idle expiry, hard limit, and graceful cleanup;
- disconnect/resume without duplicate finals;
- bounded queue backpressure preserving candidates/finals.

Integration tests use FastAPI's WebSocket test client with deterministic fake
engines. A long-session simulation sends at least 10 minutes of synthetic frames
and asserts bounded in-memory buffers, bounded spool files, segment caps, and no
task/file-handle leaks.

Optional hardware/model tests are marked separately and benchmark:

- real Moonshine partial latency;
- real Faster-Whisper verifier latency;
- 30-60 minute resident memory;
- concurrent session capacity and verify rate;
- accuracy/calibration on representative English and Vietnamese-English audio.

## 19. Migration Plan

### Phase 1: Correctness foundation

- Add unified config, schemas, errors, frame parser, ring buffer, session manager,
  WebSocket endpoint, bounded queues, lifecycle, and fake-engine tests.
- Fix `audio_bytes` contract mismatch.
- Remove realtime `large-v3` default.
- Make old entry points delegate to the unified service.

### Phase 2: Streaming recognition

- Add VAD abstraction and fallback.
- Add Moonshine adapter and partial/candidate/final pipeline.
- Validate long-session memory behavior with fake engines.

### Phase 3: Accuracy and TRACE-CAG

- Add shared Faster-Whisper verifier, router, normalizer, and final adapter.
- Remove raw audio from TRACE-CAG input state and enforce final-only delivery.

### Phase 4: Production hardening

- Add resume ownership, backpressure policy, metrics, cleanup, readiness,
  graceful shutdown, failure injection tests, and load benchmarks.
- Calibrate thresholds and concurrency on deployment hardware.

### Phase 5: Duplex readiness

- Reserve protocol event namespaces for TTS output and barge-in.
- Add `turn_id` lifecycle without coupling STT ingest to TTS playback.
- Implement duplex behavior in a separate approved design.

Each phase must leave the service deployable and retain the short-clip HTTP
compatibility path until clients migrate.

## 20. Acceptance Criteria

The design is complete when:

1. realtime audio uses authenticated WebSocket binary PCM frames;
2. no realtime request, database record, or log contains full base64 audio;
3. one service owns STT config, model lifecycle, and output contracts;
4. `large-v3` is not the realtime default;
5. sessions have bounded queues, RAM buffers, spool files, and concurrency;
6. partial output is UI-only and TRACE-CAG receives only immutable finals;
7. final events contain timestamps, source, confidence provenance, verification,
   uncertainty, and confirmation metadata;
8. timeouts apply to chunks, segments, verification, idle, and hard session
   limits rather than one recording request;
9. reconnect/resume behavior and same-worker limitation are explicit;
10. overload and model failures produce controlled events and metrics;
11. stop, expiry, errors, and shutdown close tasks and files idempotently;
12. deterministic tests cover long sessions, reconnect, overload, and failures;
13. target-hardware benchmarks determine whether the requested 300-700 ms
    partial and 1.2-2.5 second final latency targets are met.

## 21. Deployment Checklist

- Pre-provision Moonshine, Faster-Whisper, and Silero artifacts.
- Validate model paths and compute types at startup.
- Use one WebSocket worker or sticky routing for version 1 resume.
- Configure active-session and verifier concurrency from measured capacity.
- Verify binary frame limits at the reverse proxy.
- Disable proxy buffering and set appropriate WebSocket idle timeouts.
- Confirm `large-v3` is absent from realtime environment defaults.
- Confirm raw/debug audio capture is disabled.
- Verify temp directory permissions, space caps, and TTL cleanup.
- Exercise graceful shutdown with active sessions.
- Run real-model latency, memory, and concurrent-session benchmarks.
- Confirm TRACE-CAG sees only final events and handles uncertainty.
- Monitor queue depth, gaps, drops, verifier saturation, memory, and disk.
