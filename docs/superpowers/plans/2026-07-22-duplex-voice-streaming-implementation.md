# Duplex Voice Streaming Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one bounded, authenticated duplex WebSocket that carries microphone PCM through streaming STT, safe LLM token streaming, sentence-level streaming TTS, and immediate PCM playback on every supported Flutter platform.

**Architecture:** Add `/api/v1/voice/ticket` and `/api/v1/voice/stream` as thin transports over the existing STT runtime, `VoiceSession`, VAD, and transcript finalizer. `DuplexTurn` owns safe token streaming, sentence boundaries, ordered TTS, and terminal persistence; the existing `VoiceSession` owns bounded live/replay state. Flutter uses `record.startStream` for canonical PCM capture, a reference RMS VAD only for client-clock SLO measurement, and `flutter_soloud` for released-buffer playback. V1 runs one AI voice worker, preserving in-process resume without a new routing service.

**Tech Stack:** Python 3.11, FastAPI WebSocket, asyncio, Redis Streams, MongoDB, Pydantic 2, Flutter/Dart, `record` 5.2.1, `flutter_soloud` 3.5.4, pytest, flutter_test, integration_test.

**References:**
- Design: `docs/superpowers/specs/2026-07-22-duplex-voice-streaming-design.md`
- Rollout: `docs/superpowers/plans/2026-07-22-voice-streaming-v1-rollout.md`
- Existing STT plan: `ai-service/docs/superpowers/plans/2026-06-14-stt-streaming-ensemble-implementation.md`

---

## File Map

### Shared contract

- Create `contracts/voice/v1/envelope.schema.json`: common JSON event envelope.
- Create `contracts/voice/v1/control.schema.json`: client control union.
- Create `contracts/voice/v1/event.schema.json`: server event union.
- Create `contracts/voice/v1/fixtures/protocol-v1.json`: valid/invalid JSON and binary fixtures.

### AI service

- Create `ai-service/api/routes/voice.py`: ticket and duplex WebSocket transports only.
- Create `ai-service/api/services/stt/duplex_protocol.py`: framing, event envelope, state transitions.
- Create `ai-service/api/services/stt/voice_ticket_store.py`: hashed single-use Redis tickets.
- Create `ai-service/api/services/stt/stream_sanitizer.py`: bounded incremental hidden-marker sanitizer.
- Create `ai-service/api/services/stt/voice_output_guard.py`: bounded streaming safety gate.
- Create `ai-service/api/services/stt/voice_renderer.py`: UI-safe to TTS-safe text conversion.
- Create `ai-service/api/services/stt/sentence_splitter.py`: timed speakable-fragment boundaries.
- Create `ai-service/api/services/stt/duplex_turn.py`: one turn's LLM → sentence → TTS orchestration.
- Create `ai-service/api/services/stt/streaming_tts.py`: bounded ordered Piper stream and semaphore.
- Create `ai-service/api/services/stt/voice_turn_outbox.py`: Redis Stream persistence handoff.
- Modify `ai-service/api/services/stt/{config,schemas,voice_session,session_manager,runtime}.py`: reuse existing session engine with turn/replay hooks.
- Modify `ai-service/api/services/{lexi_chat_service,tts_service}.py`: expose safe token iterator and PCM chunk iterator without breaking legacy endpoints.
- Modify `ai-service/api/{main.py,core/config.py}`: lifecycle, readiness, router, flags.

### Flutter

- Create `flutter-app/lib/core/voice/{voice_protocol,voice_audio_normalizer,voice_reference_vad,pcm_frame_chunker,voice_ticket_client,voice_feature_config,duplex_voice_socket,duplex_voice_socket_io,duplex_voice_socket_web,streaming_pcm_player,duplex_voice_controller}.dart`.
- Modify `flutter-app/lib/features/lexi_chat/presentation/{pages/lexi_chat_page.dart,providers/lexi_chat_provider.dart}`: switch voice turns behind flag; retain fallback.
- Modify `flutter-app/lib/features/lexi_chat/di/lexi_chat_di.dart`: construct shared controller.
- Modify `flutter-app/pubspec.yaml` and lockfile: pin `flutter_soloud: 3.5.4`, the latest release compatible with the repository's Dart 3.10 toolchain; retain existing `record` overrides until Gate 0 proves removal safe.

### Gateway and operations

- Modify `gateway/nginx/templates/default.conf.template`: WebSocket upgrade route, limits, ticket redaction.
- Modify `gateway/kong/{kong.yml,kong.hybrid.yml}`: voice routes and WebSocket timeouts.
- Modify `docker-compose.yml`: one AI voice worker, Redis requirement, health settings.
- Modify `.env.production.example` and `.env.production`: validated server `VOICE_*` settings.
- Create `ai-service/docs/voice-streaming-runbook.md` and Gate 0/qualification reports under `docs/Report/`.
- Modify `ai-service/api/services/stt/metrics.py` and add Python/Dart telemetry tests.
- Modify `monitoring/{prometheus.yml,rules/alerts.yml}` and create provisioned Grafana voice dashboard artifacts.

---

## Chunk 1: Gate 0 and Contract

### Task 1: Run the feasibility gate with production-shaped code

**Depends on:** none

**Files:**
- Modify: `flutter-app/pubspec.yaml`
- Modify: `flutter-app/pubspec.lock`
- Create: `flutter-app/lib/core/voice/pcm_frame_chunker.dart`
- Create: `flutter-app/lib/core/voice/voice_audio_normalizer.dart`
- Create: `flutter-app/test/core/voice/pcm_frame_chunker_test.dart`
- Create: `flutter-app/test/core/voice/voice_audio_normalizer_test.dart`
- Create: `flutter-app/integration_test/duplex_audio_spike_test.dart`
- Create: `ai-service/scripts/benchmark_voice_gate0.py`
- Create: `ai-service/tests/stt/test_voice_gate0_benchmark.py`
- Create: `docs/Report/voice-streaming-gate0-template.md`

- [ ] **Step 1: Add the playback dependency only**

  Pin `flutter_soloud: 3.5.4`. Do not upgrade Flutter/Dart, `record`, or remove its Web/Linux overrides in the same change. Gate 0 rejected 4.x because it requires Dart ≥3.11 while the repository uses Dart 3.10.

- [ ] **Step 2: Write failing chunker tests**

  Cover arbitrary 1/319/640/641/4096-byte input chunks, retained remainder, exact 640-byte output, little-endian samples, 10-minute byte count, and reset after route change. Also test `VoiceAudioNormalizer.normalize(bytes, sampleRate, channels)` for 48/44.1/16 kHz, mono/stereo downmix, clipping, PCM16LE output, fractional resampling carry, and reset after format change.

- [ ] **Step 3: Run the focused Flutter test and confirm failure**

  Run: `cd flutter-app && flutter test test/core/voice/pcm_frame_chunker_test.dart test/core/voice/voice_audio_normalizer_test.dart`

  Expected: FAIL because `PcmFrameChunker` and `VoiceAudioNormalizer` do not exist.

- [ ] **Step 4: Implement the minimal rechunker**

  `PcmFrameChunker.add(Uint8List)` appends to one bounded remainder and emits only 640-byte views/copies. `reset()` drops the remainder. `VoiceAudioNormalizer` decodes PCM16LE, averages channels with saturation, and uses a stateful linear interpolator to 16 kHz while carrying fractional phase across chunks. This intentionally small speech-grade converter is replaced only if Gate 0 accuracy/drift tests fail.

  Required interfaces:

  ```dart
  final class VoiceAudioNormalizer {
    Uint8List normalize(Uint8List pcm16le, {required int sampleRate, required int channels});
    void reset();
  }

  final class PcmFrameChunker {
    List<Uint8List> add(Uint8List canonicalPcm);
    void reset();
  }
  ```

- [ ] **Step 5: Add the real-device capture/playback spike**

  The integration test must call `record.isEncoderSupported(pcm16bits)`, start PCM16 streaming, pass the effective sample rate/channels through `VoiceAudioNormalizer`, feed canonical frames to `flutter_soloud` `BufferType.s16le` with `BufferingType.released`, unlock Web audio from a user gesture, measure first non-silent playback, cancel, dispose, and report underruns.

- [ ] **Step 6: Add the backend benchmark harness**

  Use fixed 20/80/160-character English inputs and the configured Groq/Gemini provider. Record warm Piper first non-silent PCM and LLM TTFT at concurrency 1/5/10. The script exits non-zero when Piper p95 exceeds 150 ms or provider TTFT p95 exceeds 300 ms.

- [ ] **Step 7: Make the benchmark test deterministic**

  Unit-test percentile calculation, silence detection, JSON report schema, threshold exit status, and sample validation with fakes. Real provider/model execution remains an explicit CLI mode and never downloads during CI.

- [ ] **Step 8: Run Gate 0**

  Run:

  ```bash
  (cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_gate0_benchmark.py)
  (cd ai-service && venv/bin/python scripts/benchmark_voice_gate0.py --samples 100 --concurrency 1,5,10 --output ../docs/Report/voice-streaming-gate0.json)
  (cd flutter-app && flutter test test/core/voice/pcm_frame_chunker_test.dart test/core/voice/voice_audio_normalizer_test.dart)
  (cd flutter-app && flutter test integration_test/duplex_audio_spike_test.dart -d <tier-1-device> --dart-define=VOICE_GATE0_DEVICE=true)
  ```

  Expected: all automated tests pass; the report says `go=true`. Stop implementation if any Tier-1 capture/playback proof fails or either p95 threshold fails.

- [ ] **Step 9: Commit**

  `git add flutter-app/pubspec.yaml flutter-app/pubspec.lock flutter-app/linux/flutter/generated_plugins.cmake flutter-app/windows/flutter/generated_plugins.cmake flutter-app/lib/core/voice/pcm_frame_chunker.dart flutter-app/lib/core/voice/voice_audio_normalizer.dart flutter-app/test/core/voice/pcm_frame_chunker_test.dart flutter-app/test/core/voice/voice_audio_normalizer_test.dart flutter-app/integration_test/duplex_audio_spike_test.dart ai-service/scripts/benchmark_voice_gate0.py ai-service/tests/stt/test_voice_gate0_benchmark.py docs/Report/voice-streaming-gate0-template.md && git commit -m "test(voice): qualify duplex audio dependencies"`

### Task 2: Version the cross-language protocol contract

**Depends on:** Task 1 Gate 0 passes

**Files:**
- Create: `contracts/voice/v1/envelope.schema.json`
- Create: `contracts/voice/v1/control.schema.json`
- Create: `contracts/voice/v1/event.schema.json`
- Create: `contracts/voice/v1/fixtures/protocol-v1.json`
- Create: `ai-service/api/services/stt/duplex_protocol.py`
- Create: `ai-service/tests/stt/test_duplex_protocol.py`
- Create: `flutter-app/lib/core/voice/voice_protocol.dart`
- Create: `flutter-app/test/core/voice/voice_protocol_test.dart`

- [ ] **Step 1: Write the canonical fixtures first**

  Include `start`, `resume`, `start_turn`, `cancel_turn`, `playback.ack`, every server event, malformed state/event pairs, the 14-byte microphone header, and the 16-byte TTS header. Mark direction explicitly; `ack` is server output and `playback.ack` is client input. Its optional `client_metrics` accepts only bounded numeric durations (`speech_end_to_stt_final_ms`, `stt_final_to_first_token_ms`, `first_token_to_audio_start_ms`, `speech_end_to_playback_ms`, `prebuffer_ms`, `underrun_count`)—never raw text, IDs, or absolute timestamps.

- [ ] **Step 2: Write failing Python and Dart contract tests**

  Both test suites load `contracts/voice/v1/fixtures/protocol-v1.json`. Assert exact field types, nullable connection-level `turn_id`, monotonic `event_seq`, close codes, header widths/endianness, maximum sizes, and round trips.

- [ ] **Step 3: Implement the smallest protocol codecs**

  Use Pydantic discriminated unions and Python `struct`; use sealed Dart event classes and `ByteData`. Do not add code generation until maintaining the two codecs demonstrably causes drift.

- [ ] **Step 4: Run contract checks**

  ```bash
  (cd ai-service && venv/bin/python -m pytest -q tests/stt/test_duplex_protocol.py)
  (cd flutter-app && flutter test test/core/voice/voice_protocol_test.dart)
  ```

  Expected: both suites pass against the same fixture file.

- [ ] **Step 5: Commit**

  `git add contracts/voice/v1 ai-service/api/services/stt/duplex_protocol.py ai-service/tests/stt/test_duplex_protocol.py flutter-app/lib/core/voice/voice_protocol.dart flutter-app/test/core/voice/voice_protocol_test.dart && git commit -m "feat(voice): define duplex protocol v1"`

---

## Chunk 2: Secure Transport and Session Reuse

### Task 3: Issue and consume single-use voice tickets

**Depends on:** Task 2

**Files:**
- Create: `ai-service/api/services/stt/voice_ticket_store.py`
- Create: `ai-service/tests/stt/test_voice_ticket_store.py`
- Modify: `ai-service/api/core/config.py`
- Modify: `ai-service/api/core/rate_limiter.py`
- Modify: `ai-service/api/core/quota_guard.py`
- Modify: `ai-service/api/services/stt/config.py`

- [ ] **Step 1: Write failing security tests**

  Cover 256-bit entropy shape, SHA-256-only storage, 30-second TTL, atomic consume, replay rejection, user/session binding, Redis failure closed in production, local fallback only in development, ticket-safe logs, independent issue/upgrade limits, and redaction of exception/APM fields.

- [ ] **Step 2: Implement with existing Redis client**

  Reuse `api.core.redis_client.get_redis` and `RedisRateLimiter`, adding fail-closed support instead of creating a second limiter. Use a single Lua script for get-and-delete if deployed Redis/client compatibility does not expose `GETDEL`; do not build a new cache wrapper.

- [ ] **Step 3: Add validated settings**

  Put ticket TTL, allowed origins, environment mode, local-fallback toggle, issue/upgrade limits, heartbeat/idle duration, maximum JSON/binary sizes, connection minutes, STT seconds, LLM tokens, TTS characters, and turn/session durations in existing config objects. Extend `quota_guard.py` with named voice units/atomic counters; reject unsafe production combinations at startup.

- [ ] **Step 4: Run tests**

  `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_ticket_store.py tests/stt/test_config.py tests/test_quota_guard.py)`

  Expected: PASS; replay/Redis-failure/rate/quota cases return stable denial decisions without logging tickets.

- [ ] **Step 5: Security review**

  Invoke `security-reviewer` for ticket storage, origin enforcement, query redaction, and quota boundaries. Resolve high/critical findings before continuing.

- [ ] **Step 6: Commit**

  `git add ai-service/api/services/stt/voice_ticket_store.py ai-service/tests/stt/test_voice_ticket_store.py ai-service/api/core/config.py ai-service/api/core/rate_limiter.py ai-service/api/core/quota_guard.py ai-service/api/services/stt/config.py && git commit -m "feat(voice): add single-use connection tickets"`

### Task 4A: Expose the authenticated ticket endpoint

**Depends on:** Task 3

**Files:**
- Create: `ai-service/api/routes/voice.py`
- Create: `ai-service/tests/stt/test_voice_ticket_route.py`
- Modify: `ai-service/api/main.py`

- [ ] **Step 1: Write the failing endpoint tests**

  Test bearer auth, issue-rate denial, Redis fail-closed, response shape, no raw ticket in logs/exceptions, and optional resume-session ownership binding. Run `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_ticket_route.py)`; expect FAIL because `/api/v1/voice/ticket` is 404.

- [ ] **Step 2: Implement only POST `/ticket`**

  ```python
  @router.post("/ticket", response_model=VoiceTicketResponse)
  async def issue_voice_ticket(
      request: VoiceTicketRequest,
      user: AuthenticatedUser = Depends(get_current_user),
  ) -> VoiceTicketResponse: ...
  ```

  Delegate storage/rate logic to Task 3. Register the router; do not add WebSocket logic in this step.

- [ ] **Step 3: Run and commit**

  Run `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_ticket_route.py)`; expected PASS.

  `git add ai-service/api/routes/voice.py ai-service/tests/stt/test_voice_ticket_route.py ai-service/api/main.py && git commit -m "feat(voice): expose connection tickets"`

### Task 4B: Add the duplex WebSocket state machine and sole writer

**Depends on:** Task 4A

**Files:**
- Modify: `ai-service/api/routes/voice.py`
- Create: `ai-service/tests/stt/test_voice_routes.py`
- Modify: `ai-service/api/services/stt/session_manager.py`
- Modify: `ai-service/api/services/stt/voice_session.py`
- Modify: `ai-service/api/services/stt/schemas.py`

- [ ] **Step 1: Write failing handshake/state tests**

  Cover invalid/reused/expired ticket before session allocation; upgrade-rate denial; Origin/redaction; `start → session_started → start_turn → turn_started`; invalid state/event rejection; audio before turn; max control/binary sizes; heartbeat/idle close; global sequence cutover; cancel; and `resume_unavailable`. Run `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_routes.py)`; expect FAIL because `/api/v1/voice/stream` does not exist.

- [ ] **Step 2: Implement one transport-owned writer**

  ```python
  class VoiceSocketWriter:
      async def emit_json(self, event: ServerEvent, *, droppable: bool = False) -> None: ...
      async def emit_audio(self, header: TTSAudioHeader, pcm: bytes) -> None: ...
      async def close(self) -> None: ...
  ```

  A bounded queue/task is the sole caller of `send_json/send_bytes`. Coalesce partial/token state; non-droppable overflow becomes `OUTPUT_BACKPRESSURE`. Enforce sizes, heartbeat, idle time, and `permessage-deflate` policy in application tests.

- [ ] **Step 3: Reuse existing session ownership**

  Obtain `get_stt_sessions()` and existing `VoiceSession`; add only active-turn admission/cutover state. Move shared helpers from `routes/stt.py` rather than copying. Do not load a second STT/VAD/verifier.

- [ ] **Step 4: Add application quota enforcement**

  Consume connection/STT-time quota during admission and expose hooks for later LLM/TTS units. Test quota termination independently of gateway limits.

- [ ] **Step 5: Run regression tests and commit**

  Run `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_routes.py tests/stt/test_stt_routes.py tests/stt/test_session_manager.py tests/stt/test_voice_session.py)`; expected PASS with legacy STT unchanged.

  `git add ai-service/api/routes/voice.py ai-service/tests/stt/test_voice_routes.py ai-service/api/services/stt/session_manager.py ai-service/api/services/stt/voice_session.py ai-service/api/services/stt/schemas.py && git commit -m "feat(voice): add duplex websocket transport"`

---

## Chunk 3: Real LLM Streaming and Sentence Boundaries

### Task 5: Stream safe LLM tokens without whole-response buffering

**Depends on:** Task 4B

**Files:**
- Create: `ai-service/api/services/stt/stream_sanitizer.py`
- Create: `ai-service/tests/stt/test_stream_sanitizer.py`
- Modify: `ai-service/api/services/lexi_chat_service.py`
- Modify: `ai-service/tests/test_lexi_chat_routes.py`

- [ ] **Step 1: Write adversarial failing tests**

  Split `<think>`, closing tags, TRACE-CAG markers, JSON payloads, markdown delimiters, and near-prefix normal text at every token boundary. Assert no hidden byte is emitted, look-behind stays bounded, EOF hidden content is discarded, and ordinary text streams immediately.

- [ ] **Step 2: Implement a bounded state machine**

  Reuse `_sanitize_lexi_response` rules but make marker handling incremental. Configure providers to disable/separate reasoning first; the sanitizer remains defense in depth.

- [ ] **Step 3: Expose one safe async iterator**

  Refactor the legacy Lexi stream to consume the safe iterator too, deleting its `tokens: list[str]` whole-response buffer. Preserve final full text by appending already-sanitized emitted chunks.

- [ ] **Step 4: Run tests**

  `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_stream_sanitizer.py tests/test_lexi_chat_routes.py)`

  Expected: PASS; the first ordinary token is emitted before provider completion and no hidden marker fragment appears.

- [ ] **Step 5: Commit**

  `git add ai-service/api/services/stt/stream_sanitizer.py ai-service/tests/stt/test_stream_sanitizer.py ai-service/api/services/lexi_chat_service.py ai-service/tests/test_lexi_chat_routes.py && git commit -m "fix(ai): stream sanitized Lexi tokens incrementally"`

### Task 6: Split safe text into bounded speakable fragments

**Depends on:** Task 5

**Files:**
- Create: `ai-service/api/services/stt/sentence_splitter.py`
- Create: `ai-service/tests/stt/test_sentence_splitter.py`
- Create: `ai-service/api/services/stt/voice_output_guard.py`
- Create: `ai-service/tests/stt/test_voice_output_guard.py`
- Create: `ai-service/api/services/stt/voice_renderer.py`
- Create: `ai-service/tests/stt/test_voice_renderer.py`

- [ ] **Step 1: Write failing output-safety tests**

  Require provider safety/reasoning settings in the generation request and test a bounded `VoiceOutputGuard.feed(token)` that withholds incomplete words, rejects configured unsafe/control patterns even when split across tokens, emits a safe replacement event, and resets on cancellation. Hidden-marker sanitization is not counted as this safety check.

- [ ] **Step 2: Write failing renderer tests**

  Cover markdown emphasis/lists, fenced and inline code, URLs, emoji/control characters, English numbers/decimals, Unicode punctuation, Vietnamese text preservation, whitespace, split-token input, and cancellation. The renderer returns UI-safe text unchanged separately from TTS-safe text.

- [ ] **Step 3: Write failing splitter tests**

  Cover `.?!` and Unicode terminators, abbreviations, decimals, initials, paired quotes, markdown/code, URLs, minimum speakable size, 160-character ceiling, 250 ms first-boundary timer, EOF flush, and cancellation reset. Inject a monotonic clock; do not sleep in unit tests.

- [ ] **Step 4: Implement minimum state only**

  Pipeline order is `StreamSanitizer → VoiceOutputGuard → VoiceRenderer → SentenceSplitter`. Reuse `lexi_pipeline_helpers.py` markdown normalization where applicable. Keep only bounded look-behind/text buffers, delimiter state, first-token timestamp, and sentence sequence. Prefer punctuation/clause/whitespace in that order. Emit no punctuation-only or rejected fragment.

  Required interfaces:

  ```python
  class VoiceOutputGuard:
      def feed(self, token: str) -> list[str]: ...
      def finish(self) -> list[str]: ...
      def cancel(self) -> None: ...

  def render_for_voice(text: str, language: str) -> str: ...
  ```

- [ ] **Step 5: Run tests**

  `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_output_guard.py tests/stt/test_voice_renderer.py tests/stt/test_sentence_splitter.py)`

  Expected: PASS; adversarial unsafe/hidden/markdown fixtures never enter emitted TTS fragments.

- [ ] **Step 6: Commit**

  `git add ai-service/api/services/stt/voice_output_guard.py ai-service/tests/stt/test_voice_output_guard.py ai-service/api/services/stt/voice_renderer.py ai-service/tests/stt/test_voice_renderer.py ai-service/api/services/stt/sentence_splitter.py ai-service/tests/stt/test_sentence_splitter.py && git commit -m "feat(voice): guard and split streamed speech"`

---

## Chunk 4: Streaming TTS and Turn Orchestration

### Task 7: Yield Piper PCM chunks off the event loop

**Depends on:** Tasks 1 and 6

**Files:**
- Modify: `ai-service/api/services/tts_service.py`
- Create: `ai-service/api/services/stt/streaming_tts.py`
- Create: `ai-service/tests/stt/test_streaming_tts.py`
- Modify: `ai-service/tests/test_tts_routes.py`

- [ ] **Step 1: Write failing streaming tests**

  Prove the first fake Piper chunk is observable before the producer completes; chunk metadata is stable; cancellation suppresses stale chunks; concurrency/admission are bounded; and legacy `synthesize()` still returns a valid WAV.

- [ ] **Step 2: Add `iter_pcm` to the existing service**

  Adapt Piper's existing chunk iterator instead of `list(voice.synthesize(text))`. Bridge the blocking iterator through one worker thread and bounded asyncio queue. Keep WAV assembly as a consumer for the legacy REST route.

- [ ] **Step 3: Add one global TTS limiter**

  `StreamingTTS` owns the configured semaphore/admission bound and one ordered sentence consumer per turn. Do not add parallel sentence synthesis or reordering in v1.

- [ ] **Step 4: Run tests and benchmark guard**

  ```bash
  (cd ai-service && venv/bin/python -m pytest -q tests/stt/test_streaming_tts.py tests/test_tts_routes.py)
  (cd ai-service && venv/bin/python scripts/benchmark_voice_gate0.py --tts-only --samples 100)
  ```

  Expected: tests PASS and benchmark reports warm p95 first PCM ≤150 ms.

- [ ] **Step 5: Commit**

  `git add ai-service/api/services/tts_service.py ai-service/api/services/stt/streaming_tts.py ai-service/tests/stt/test_streaming_tts.py ai-service/tests/test_tts_routes.py && git commit -m "feat(tts): stream Piper PCM chunks"`

### Task 8: Orchestrate final STT → LLM → sentences → TTS

**Depends on:** Tasks 4B and 5–7

**Files:**
- Create: `ai-service/api/services/stt/duplex_turn.py`
- Create: `ai-service/tests/stt/test_duplex_turn.py`
- Modify: `ai-service/api/routes/voice.py`
- Modify: `ai-service/api/services/stt/voice_session.py`
- Modify: `ai-service/api/services/stt/trace_cag_adapter.py`

- [ ] **Step 1: Write the paced end-to-end test**

  Fake STT final, TRACE context deadline, token timings, guard/renderer/splitter state, and TTS chunks. Assert event order, first audio before LLM completion, optional verifier behavior, uncertain transcript confirmation, cancellation propagation, and no stale output. Inject unsafe text split across tokens plus markdown/code/URLs; prove rejected text never reaches TTS, TTS receives rendered speakable text, and UI retains the permitted UI-safe representation. Assert `turn.done` only after final `tts.audio.end` write acknowledgement.

- [ ] **Step 2: Implement one `DuplexTurn` owner**

  It receives an accepted final transcript, races TRACE-CAG context against 250 ms, then runs `StreamSanitizer → VoiceOutputGuard → VoiceRenderer → SentenceSplitter`. Permitted UI tokens and rendered TTS fragments are separate outputs. It queues ordered TTS and closes exactly once; route/session code only starts/cancels it.

- [ ] **Step 3: Keep legacy TRACE-CAG behavior intact**

  Add a bounded voice-context method or deadline parameter; do not lower the legacy SSE timeout globally. Late voice retrieval records degradation and cannot mutate an issued prompt.

- [ ] **Step 4: Run integration regressions**

  ```bash
  (cd ai-service && venv/bin/python -m pytest -q tests/stt/test_duplex_turn.py tests/stt tests/test_lexi_chat_routes.py tests/test_tracecag_chat_integration.py)
  ```

  Expected: PASS; paced test observes first TTS frame before `llm.done`.

- [ ] **Step 5: Commit**

  `git add ai-service/api/services/stt/duplex_turn.py ai-service/tests/stt/test_duplex_turn.py ai-service/api/routes/voice.py ai-service/api/services/stt/voice_session.py ai-service/api/services/stt/trace_cag_adapter.py && git commit -m "feat(voice): orchestrate streamed assistant turns"`

---

## Chunk 5: Replay and Durable Persistence

### Task 9A: Bound playback ACKs, replay, and turn idempotency

**Depends on:** Task 8

**Files:**
- Modify: `ai-service/api/services/stt/{config,voice_session,session_manager}.py`
- Modify: `ai-service/tests/stt/{test_voice_session,test_session_manager,test_long_session}.py`

- [ ] **Step 1: Write and run failing replay tests**

  Cover buffered/played cursors, metadata-before-audio replay, duplicate suppression, byte/item bounds, slow-client cancellation, repeated `start_turn`, expiry, and no replay of played audio. Run `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_session.py tests/stt/test_session_manager.py tests/stt/test_long_session.py)`; expect new replay assertions to FAIL.

- [ ] **Step 2: Add the minimum session-owned state**

  ```python
  @dataclass
  class PlaybackCursor:
      turn_seq: int
      sentence_seq: int
      audio_seq: int

  class VoiceReplayBuffer:
      def append(self, frame: ReplayFrame) -> None: ...
      def acknowledge_played(self, cursor: PlaybackCursor) -> None: ...
      def after(self, cursor: PlaybackCursor) -> list[ReplayFrame]: ...
  ```

  Keep it inside the existing `VoiceSession`; retain unplayed audio only, bounded by 30 seconds and 1 MiB. Overflow cancels rather than losing required frames. Store 32 terminal idempotency records with resume-window TTL.

- [ ] **Step 3: Run and commit**

  Run the focused command above; expected PASS and bounded long-session memory.

  `git add ai-service/api/services/stt/config.py ai-service/api/services/stt/voice_session.py ai-service/api/services/stt/session_manager.py ai-service/tests/stt/test_voice_session.py ai-service/tests/stt/test_session_manager.py ai-service/tests/stt/test_long_session.py && git commit -m "feat(voice): bound duplex replay state"`

### Task 9B: Persist completed turns through a Redis Stream outbox

**Depends on:** Task 9A

**Files:**
- Create: `ai-service/api/services/stt/voice_turn_outbox.py`
- Create: `ai-service/tests/stt/test_voice_turn_outbox.py`
- Modify: `ai-service/api/services/stt/duplex_turn.py`
- Modify: `ai-service/tests/stt/test_duplex_turn.py`
- Modify: `ai-service/api/main.py`

- [ ] **Step 1: Write and run failing outbox tests**

  Cover append before `turn.done(pending)`, no terminal on required append failure, idempotent consume, retry/dead-letter metadata, existing Mongo/Redis Lexi persistence, and restart recovery. Run `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_turn_outbox.py tests/stt/test_duplex_turn.py)`; expect import failure before `VoiceTurnOutbox` exists.

- [ ] **Step 2: Implement the record and worker interfaces**

  ```python
  class VoiceTurnOutbox:
      async def append(self, snapshot: VoiceTurnSnapshot) -> str: ...
      async def start(self) -> None: ...
      async def close(self) -> None: ...

  @dataclass(frozen=True)
  class VoiceTurnSnapshot:
      idempotency_key: str
      user_id: str
      chat_session_id: str
      user_text: str
      assistant_text: str
      metadata: dict[str, object]
  ```

  Reuse `get_redis`, existing Lexi stores, and lifespan. `DuplexTurn` appends after final audio-end write and before its sole `turn.done`. Do not reuse the backend PostgreSQL outbox.

- [ ] **Step 3: Run and commit**

  Run the focused command above; expected PASS including restart recovery fake.

  `git add ai-service/api/services/stt/voice_turn_outbox.py ai-service/tests/stt/test_voice_turn_outbox.py ai-service/api/services/stt/duplex_turn.py ai-service/tests/stt/test_duplex_turn.py ai-service/api/main.py && git commit -m "feat(voice): persist turns through Redis outbox"`

---

## Chunk 6: Flutter Duplex Client

### Task 10A: Implement feature gating, ticket fetch, and platform sockets

**Depends on:** Tasks 2, 4A, and Gate 0

**Files:**
- Create: `flutter-app/lib/core/voice/voice_feature_config.dart`
- Create: `flutter-app/lib/core/voice/voice_ticket_client.dart`
- Create: `flutter-app/lib/core/voice/duplex_voice_socket.dart`
- Create: `flutter-app/lib/core/voice/duplex_voice_socket_io.dart`
- Create: `flutter-app/lib/core/voice/duplex_voice_socket_web.dart`
- Create: `flutter-app/test/core/voice/{voice_feature_config,voice_ticket_client,duplex_voice_socket}_test.dart`
- Modify: `flutter-app/lib/core/network/api_client.dart`

- [ ] **Step 1: Write and run failing config tests**

  Test `--dart-define` defaults/validation, platform allowlist, 0/100%, and deterministic FNV-1a user bucketing. Run `(cd flutter-app && flutter test test/core/voice/voice_feature_config_test.dart)`; expect missing `VoiceFeatureConfig` failure.

- [ ] **Step 2: Implement compile-time configuration**

  ```dart
  final class VoiceFeatureConfig {
    const VoiceFeatureConfig({required this.enabled, required this.platforms, required this.percentage});
    factory VoiceFeatureConfig.fromEnvironment();
    bool enabledFor({required String userId, required String platform});
  }
  ```

- [ ] **Step 3: Write and run failing ticket/socket tests**

  Test bearer ticket POST, ticket redaction, Web/native opening, binary/JSON receive, fresh ticket on reconnect, and disabling compression where supported. Run `(cd flutter-app && flutter test test/core/voice/voice_ticket_client_test.dart test/core/voice/duplex_voice_socket_test.dart)`; expect missing adapter failures.

- [ ] **Step 4: Implement narrow platform adapters**

  ```dart
  abstract interface class DuplexVoiceSocket {
    Stream<Object> get messages;
    Future<void> sendText(String value);
    Future<void> sendBytes(Uint8List value);
    Future<void> close();
  }
  ```

  Conditional exports select only Web vs IO opening mechanics. Protocol parsing stays in `voice_protocol.dart`; `ApiClient` remains the bearer source for ticket POST.

- [ ] **Step 5: Run and commit**

  Run both focused commands; expected PASS.

  `git add flutter-app/lib/core/voice/voice_feature_config.dart flutter-app/lib/core/voice/voice_ticket_client.dart flutter-app/lib/core/voice/duplex_voice_socket.dart flutter-app/lib/core/voice/duplex_voice_socket_io.dart flutter-app/lib/core/voice/duplex_voice_socket_web.dart flutter-app/test/core/voice/voice_feature_config_test.dart flutter-app/test/core/voice/voice_ticket_client_test.dart flutter-app/test/core/voice/duplex_voice_socket_test.dart flutter-app/lib/core/network/api_client.dart && git commit -m "feat(flutter): connect to duplex voice transport"`

### Task 10B: Own the client state machine and microphone stream

**Depends on:** Tasks 4B and 10A

**Files:**
- Create: `flutter-app/lib/core/voice/duplex_voice_controller.dart`
- Create: `flutter-app/lib/core/voice/voice_reference_vad.dart`
- Create: `flutter-app/test/core/voice/duplex_voice_controller_test.dart`
- Create: `flutter-app/test/core/voice/voice_reference_vad_test.dart`

- [ ] **Step 1: Write and run failing reference-VAD tests**

  Feed canonical PCM fixtures containing noise, speech, hangover silence, and silence-only input. Assert the detector records the monotonic timestamp/audio sequence of the last speech-positive frame, applies configurable RMS threshold and hangover frames, emits no endpoint for noise-only input, and resets between turns. Run `(cd flutter-app && flutter test test/core/voice/voice_reference_vad_test.dart)`; expect missing `VoiceReferenceVad` failure.

- [ ] **Step 2: Implement measurement-only VAD**

  ```dart
  final class VoiceReferenceVad {
    VoiceReferenceVad({required double rmsThreshold, required int hangoverFrames});
    VoiceSpeechMark? add(Uint8List canonicalPcm, {required int audioSeq, required Duration monotonicNow});
    void reset();
  }
  ```

  It never controls server endpointing or model input; it only supplies the reproducible client t0 mark. Threshold/hangover are compile-time/config values recorded in qualification reports.

- [ ] **Step 3: Write and run failing controller tests**

  Cover `idle→connecting→ready→listening→generating→speaking→ready`, forbidden transitions, one outbound writer, exact frame sequence, backpressure, cancel, duplicates, resume, and route change. Run `(cd flutter-app && flutter test test/core/voice/duplex_voice_controller_test.dart)`; expect missing controller failure.

- [ ] **Step 4: Implement explicit ownership**

  ```dart
  final class DuplexVoiceController {
    Future<void> connect(String chatSessionId);
    Future<void> startTurn(String idempotencyKey);
    Future<void> cancelTurn();
    Future<void> disconnect();
  }
  ```

  The controller alone owns `AudioRecorder`, `VoiceAudioNormalizer`, `VoiceReferenceVad`, `PcmFrameChunker`, socket writer, sequence counters, injected monotonic clock, and subscriptions. Request PCM16, normalize effective sample rate/channels, feed the reference VAD before framing/send, pause after STT final, and reset all audio state on route change.

- [ ] **Step 5: Run and commit**

  Run `(cd flutter-app && flutter test test/core/voice/voice_reference_vad_test.dart test/core/voice/duplex_voice_controller_test.dart)`; expected PASS with no pending timers/subscriptions.

  `git add flutter-app/lib/core/voice/duplex_voice_controller.dart flutter-app/lib/core/voice/voice_reference_vad.dart flutter-app/test/core/voice/duplex_voice_controller_test.dart flutter-app/test/core/voice/voice_reference_vad_test.dart && git commit -m "feat(flutter): stream canonical microphone turns"`

### Task 11: Play streamed PCM immediately and wire Lexi Chat

**Depends on:** Tasks 7, 8, and 10B

**Files:**
- Create: `flutter-app/lib/core/voice/streaming_pcm_player.dart`
- Create: `flutter-app/test/core/voice/streaming_pcm_player_test.dart`
- Modify: `flutter-app/lib/features/lexi_chat/presentation/pages/lexi_chat_page.dart`
- Modify: `flutter-app/lib/features/lexi_chat/presentation/providers/lexi_chat_provider.dart`
- Modify: `flutter-app/lib/features/lexi_chat/di/lexi_chat_di.dart`
- Modify: `flutter-app/test/features/lexi_chat/presentation/providers/lexi_chat_provider_test.dart`

- [ ] **Step 1: Write failing player tests with a fake sink**

  Cover 80–120 ms prebuffer, `tts.audio.start` format changes, ordered frames, buffered/played ACKs, underrun adaptation, cancellation/reset, audio focus/interruption, browser unlock error, and disposal.

- [ ] **Step 2: Implement the released buffer adapter**

  Wrap only `flutter_soloud` buffer-stream operations. Bound queued bytes and release consumed data. Keep `just_audio` for legacy complete-message replay.

- [ ] **Step 3: Replace the Lexi voice path behind the flag**

  When `VOICE_DUPLEX_ENABLED` and platform-allowed, the microphone button uses `DuplexVoiceController`. Otherwise retain the current file/Web Speech → REST STT → SSE path. Never silently re-upload audio from a failed active duplex turn.

- [ ] **Step 4: Run Flutter verification**

  ```bash
  (cd flutter-app && flutter test test/core/voice test/features/lexi_chat/presentation/providers/lexi_chat_provider_test.dart)
  (cd flutter-app && flutter analyze)
  ```

- [ ] **Step 5: Run Tier-1 devices**

  Run the integration test on current supported Chrome, Android, and iOS/Safari devices. Record capture format, first playback callback, cancellation, interruption, and underrun results.

- [ ] **Step 6: Commit**

  `git add flutter-app/lib/core/voice/streaming_pcm_player.dart flutter-app/test/core/voice/streaming_pcm_player_test.dart flutter-app/lib/features/lexi_chat/presentation/pages/lexi_chat_page.dart flutter-app/lib/features/lexi_chat/presentation/providers/lexi_chat_provider.dart flutter-app/lib/features/lexi_chat/di/lexi_chat_di.dart flutter-app/test/features/lexi_chat/presentation/providers/lexi_chat_provider_test.dart && git commit -m "feat(flutter): play duplex TTS audio immediately"`

---

## Chunk 7: Gateway, Configuration, Qualification, and Rollout

### Task 12: Configure production transport and flags

**Depends on:** Tasks 4B, 9B, and 11

**Files:**
- Modify: `gateway/nginx/templates/default.conf.template`
- Modify: `gateway/kong/kong.yml`
- Modify: `gateway/kong/kong.hybrid.yml`
- Modify: `docker-compose.yml`
- Modify: `.env.production.example`
- Modify: `.env.production`
- Create: `ai-service/tests/stt/test_voice_production_config.py`

- [ ] **Step 1: Write config validation tests**

  Assert production requires Redis, one AI voice worker, safe Origin allowlist, ticket TTL, queue byte/item bounds, session duration, TTS concurrency, and valid `auto|cpu|gpu` profile.

- [ ] **Step 2: Configure WebSocket proxying**

  Add exact `/api/v1/voice/` routing with Upgrade/Connection headers, buffering off, finite idle timeout, body/frame limits, per-IP connection/rate limits, and ticket query redaction. Do not add dynamic owner routing in v1.

- [ ] **Step 3: Add rollout configuration**

  Define server-side `VOICE_DUPLEX_ENABLED`, runtime profile, ticket/origin settings, queue bounds, and model warmup in `.env.production.example`/`.env.production`. Flutter receives the master flag, platform allowlist, and deterministic percentage through the `--dart-define` values consumed by `VoiceFeatureConfig`; document exact build arguments in the runbook. Keep disabled until qualification.

- [ ] **Step 4: Run static verification**

  ```bash
  (cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_production_config.py)
  (cd . && docker compose config --quiet)
  git diff --check
  ```

- [ ] **Step 5: Security review**

  Invoke `security-reviewer` for auth, Origin, logs, quotas, Redis/outbox, configuration, and gateway rules.

- [ ] **Step 6: Commit**

  `git add gateway/nginx/templates/default.conf.template gateway/kong/kong.yml gateway/kong/kong.hybrid.yml docker-compose.yml .env.production.example .env.production ai-service/tests/stt/test_voice_production_config.py && git commit -m "ops(voice): configure duplex websocket rollout"`

### Task 12B: Instrument server and client voice telemetry

**Depends on:** Tasks 2, 8, 9B, and 11

**Files:**
- Modify: `ai-service/api/services/stt/metrics.py`
- Modify: `ai-service/api/routes/voice.py`
- Create: `ai-service/tests/stt/test_voice_metrics.py`
- Modify: `flutter-app/lib/core/voice/duplex_voice_controller.dart`
- Modify: `flutter-app/lib/core/voice/streaming_pcm_player.dart`
- Create: `flutter-app/test/core/voice/voice_telemetry_test.dart`
- Modify: `monitoring/prometheus.yml`
- Modify: `monitoring/rules/alerts.yml`
- Create: `monitoring/grafana/provisioning/dashboards/voice.yml`
- Create: `monitoring/grafana/dashboards/voice-streaming.json`

- [ ] **Step 1: Write failing server metrics tests**

  Run `(cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_metrics.py)` and expect collection/import failure before the voice metric names/exporter exist. Test bounded `playback.ack.client_metrics` validation, histogram observation, queue/replay/outbox gauges, provider readiness, cancellations, backpressure, and rejection of strings/absolute timestamps/high-cardinality labels.

- [ ] **Step 2: Implement the server metric boundary**

  Extend the existing `STTMetrics`; do not add a second metrics registry. `voice.py` accepts client durations only through authenticated `playback.ack`, validates them through the shared protocol model, and records fixed-label histograms/counters. Expose them through the repository's Prometheus scrape path.

- [ ] **Step 3: Write failing Flutter telemetry tests**

  Run `(cd flutter-app && flutter test test/core/voice/voice_telemetry_test.dart)` and expect failure before local stage timing exists. Use one injected monotonic clock. Assert the controller sends bounded duration fields only after first consumed non-silent PCM; underrun/autoplay/route-change counters contain no transcript, ticket, raw audio, or user ID.

- [ ] **Step 4: Implement client timing**

  `VoiceReferenceVad` supplies t0; `DuplexVoiceController` stores local t0/t1/t2/t3 marks and `StreamingPcmPlayer` supplies t4/underrun callbacks. Send derived durations in the next `playback.ack`; never subtract a server clock.

- [ ] **Step 5: Provision monitoring artifacts**

  Add scrape/rules and a provisioned dashboard for end-to-end/component latency, queue bytes/items, replay/outbox lag, provider readiness, backpressure/cancellations, underruns, autoplay/route failures, and turn errors. Alert rules must include explicit warning/critical thresholds documented in the runbook.

- [ ] **Step 6: Run and commit**

  ```bash
  (cd ai-service && venv/bin/python -m pytest -q tests/stt/test_voice_metrics.py)
  (cd flutter-app && flutter test test/core/voice/voice_telemetry_test.dart)
  (cd . && docker compose config --quiet)
  ```

  Expected: PASS; Grafana provisioning paths resolve in `docker compose config`.

  `git add ai-service/api/services/stt/metrics.py ai-service/api/routes/voice.py ai-service/tests/stt/test_voice_metrics.py flutter-app/lib/core/voice/duplex_voice_controller.dart flutter-app/lib/core/voice/streaming_pcm_player.dart flutter-app/test/core/voice/voice_telemetry_test.dart monitoring/prometheus.yml monitoring/rules/alerts.yml monitoring/grafana/provisioning/dashboards/voice.yml monitoring/grafana/dashboards/voice-streaming.json && git commit -m "feat(voice): instrument duplex latency and health"`

### Task 13: Qualify all platforms and stage rollout

**Depends on:** Tasks 12 and 12B

**Files:**
- Create: `ai-service/scripts/benchmark_duplex_voice.py`
- Create: `ai-service/tests/stt/test_duplex_voice_benchmark.py`
- Create: `ai-service/docs/voice-streaming-runbook.md`
- Create: `docs/Report/voice-streaming-qualification-template.md`
- Create: `docs/operations/voice-streaming-privacy-checklist.md`
- Modify: `docs/superpowers/plans/2026-07-22-voice-streaming-v1-rollout.md`

- [ ] **Step 1: Add deterministic benchmark tests**

  Test report schema, nearest-rank p50/p90/p95/p99, warm/cold separation, cache labels, failed-turn accounting, and go/no-go thresholds.

- [ ] **Step 2: Run backend suites**

  ```bash
  (cd ai-service && venv/bin/python -m pytest -q tests/stt tests/test_tts_routes.py tests/test_lexi_chat_routes.py tests/test_tracecag_chat_integration.py)
  (cd ai-service && venv/bin/python -m compileall api/services/stt api/routes/voice.py)
  ```

- [ ] **Step 3: Run Flutter suites**

  ```bash
  (cd flutter-app && flutter test test/core/voice test/features/lexi_chat)
  (cd flutter-app && flutter analyze)
  ```

- [ ] **Step 4: Run load qualification**

  Execute at least 400 valid turns per primary scenario at 1/5/10 concurrent sessions and 20/80/150 ms RTT profiles. Gate Tier 1 on warm established-socket p95 ≤1.5 s at RTT ≤80 ms; report 150 ms separately against 2.0 s.

- [ ] **Step 5: Qualify platform tiers**

  Tier 1: Chrome, Android, iOS/Safari. Tier 2: macOS, Windows. Tier 3: Linux, Firefox. Verify speaker/headset/Bluetooth, route changes, interruption, autoplay, cancellation, fallback, and privacy behavior before enabling each tier.

- [ ] **Step 6: Exercise rollback**

  In staging, disable the master flag during idle and active turns, verify scoped active-turn failure, verify the next turn uses fallback, and confirm no microphone audio is silently resent.

- [ ] **Step 7: Add operational and privacy gates**

  Verify the Task 12B dashboard/alerts in staging and exercise a maximum-session worker drain. The privacy checklist records consent copy, transcript retention/deletion, provider processing, raw-audio non-retention, log/metric redaction, and named approval before external rollout.

- [ ] **Step 8: Final reviews and commit**

  Spawn `test-writer` to audit missing public-path tests, `security-reviewer` for the final surface, and `code-reviewer` before PR. Resolve findings, then run `git diff --check` and commit:

  `git add ai-service/scripts/benchmark_duplex_voice.py ai-service/tests/stt/test_duplex_voice_benchmark.py ai-service/docs/voice-streaming-runbook.md docs/Report/voice-streaming-qualification-template.md docs/operations/voice-streaming-privacy-checklist.md docs/superpowers/plans/2026-07-22-voice-streaming-v1-rollout.md && git commit -m "docs(voice): qualify duplex streaming rollout"`

---

## Implementation Order and Stop Conditions

```text
Gate 0
  -> shared contract
  -> ticket + thin /voice transport
  -> safe token stream + splitter
  -> streaming Piper
  -> DuplexTurn integration
  -> replay/outbox
  -> Flutter capture + playback
  -> gateway/config
  -> qualification + staged rollout
```

Stop and report instead of expanding scope when:

- Gate 0 misses either latency threshold on production-like hardware.
- `record` cannot produce or expose a reliably normalizable stream on a Tier-1 target.
- `flutter_soloud` cannot provide first-consumed/underrun signals required for SLO measurement.
- Production cannot run one voice worker within measured safe capacity; write a separate sticky-routing design before adding horizontal voice workers.
- A provider cannot separate/disable reasoning safely enough for incremental streaming.

Skipped for v1: WebRTC, full barge-in/AEC, cross-worker decoder migration, parallel sentence TTS, schema code generation, and dynamic sticky routing. Add only after telemetry demonstrates the need.
