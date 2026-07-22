# Voice Streaming v1 — Rollout Plan

**Version:** 1.0  
**Updated:** 2026-07-22  
**Status:** Ready for technical spike; implementation starts only after Gate 0 passes  
**Scope:** Flutter Web, Android, iOS, macOS, Windows, Linux, and the AI voice service

## 1. Product outcome and release boundary

Deliver a natural, low-latency learner-to-assistant voice turn over one bidirectional WebSocket:

```text
microphone PCM -> streaming STT -> LLM -> sentence boundary -> streaming TTS -> PCM playback
```

### v1 promise

- First **non-silent audible** assistant PCM reaches the client playback adapter within **1.5 s p95** after the learner's last speech-positive frame.
- The 1.5 s SLO applies only to: warm models, an established WebSocket, qualified Tier-1 platforms, qualified load, and RTT at or below 80 ms.
- RTT 150 ms is measured and reported separately. It is a stretch target of 2.0 s p95 until Gate 0 proves the 1.5 s target feasible there.
- The interaction is **half duplex**: after the learner finalizes speech, capture pauses until the assistant finishes. A deliberate user interruption cancels the assistant, then starts a fresh turn.
- REST STT and Lexi SSE remain available as a fallback for the next turn while duplex rollout is gated.

### Explicit non-goals for v1

- WebRTC transport.
- Full barge-in while microphone and TTS run concurrently.
- Acoustic echo cancellation implemented by this feature.
- Replay of microphone audio after the owning voice worker has died.
- Cross-worker migration of a live decoder/session.

## 2. Architecture decisions

| Decision | v1 choice | Reason |
|---|---|---|
| Transport | One TLS WebSocket carrying JSON control plus binary PCM | Low overhead; enough for half-duplex streaming; one ordered transport |
| Public route | `POST /api/v1/voice/ticket`, `WS /api/v1/voice/stream` | Route reflects STT, LLM, TTS, replay, and playback—not STT alone |
| Interaction model | Half duplex | Keeps v1 deterministic while AEC/barge-in are deferred |
| Client microphone wire format | Canonical PCM16LE, mono, 16 kHz, exact 20 ms frames | Fixed STT input, simple bounds, stable test fixtures |
| Assistant audio | PCM16LE, mono, sample rate declared per `tts.audio.start` | Avoid base64/WAV latency and allow TTS implementation changes |
| Session ownership | One worker owns live decoder, queues, replay and turn state | Keeps state simple and bounded in v1 |
| Resume | One AI voice worker in v1; reconnect to that worker or start clean | Avoid an unimplemented dynamic routing layer |
| Context retrieval | TRACE-CAG runs in parallel with a 250 ms deadline | Retrieval helps quality but must not block speech |
| Persistence | AI-service Redis Stream outbox before asynchronous Mongo/Redis persistence | Reuse deployed Redis and existing Lexi stores |

## 3. End-to-end flow

```text
Flutter client
  -> POST /api/v1/voice/ticket (Bearer JWT)
  -> WS /api/v1/voice/stream?ticket=<single-use>&resume_session_id=<optional non-secret id>
  -> start
  <- session_started
  -> start_turn(idempotency_key)
  <- turn_started(accept_audio_after_seq)
  -> canonical microphone PCM frames
  <- stt.partial / stt.final
  <- llm.token / sentence.final
  <- tts.audio.start / binary PCM / tts.audio.end
  <- turn.done / turn.persisted
```

The ticket is mandatory and bound to the authenticated user and, when resuming, to that same session. V1 deploys one AI voice worker; horizontal voice-worker routing is deferred until measured capacity requires it.

## 4. Gate 0 — feasibility spike before full implementation

No protocol-reliability work begins until all four spikes pass on representative hardware.

| Spike | Deliverable | Pass condition |
|---|---|---|
| Capture normalization | Flutter proof on Chrome, Android, iOS | Arbitrary recorder chunks become exact 640-byte PCM16LE/16 kHz/mono frames; no drift in 10-minute capture |
| Playback | `flutter_soloud` released buffer stream proof | First non-silent PCM playback, cancellation, disposal and underrun callback work on Tier 1 |
| TTS time-to-first-audio | Piper CPU benchmark on production-like host | Warm p95 first non-silent PCM <= 150 ms for 20/80/160-character inputs |
| Provider time-to-first-token | Real LLM/provider benchmark with voice prompt | Warm p95 TTFT <= 300 ms at 1/5/10 qualified concurrent sessions |

**Gate 0 output:** a short benchmark report with host specification, model versions, prompt size, RTT profile, p50/p90/p95/p99, sample count, raw failures, and an explicit go/no-go decision.

The current package choices are feasible but must be pinned and tested: `record` supports PCM16 streaming on all six targets, while Linux requires `parecord`, `pactl`, and `ffmpeg`; `flutter_soloud` supports raw PCM and released streaming buffers. Minimum OS/browser versions are product requirements, not assumptions.

## 5. Latency definition and SLO measurement

### Canonical timestamps

| Timestamp | Definition |
|---|---|
| `t0` | Client reference VAD sees the last speech-positive microphone frame |
| `t1` | Client receives `stt.final` |
| `t2` | Client receives first safe, speakable LLM token |
| `t3` | Client receives first `tts.audio.start` for a finalized speakable fragment |
| `t4` | Playback adapter consumes the first PCM window above the configured RMS/silence threshold |

Product latency is `t4 - t0`. All five timestamps use the client monotonic clock where possible. Server timestamps are trace diagnostics only and are never subtracted from client timestamps.

### Component guards

The following are diagnostic guards, **not additive proof** of end-to-end p95:

| Stage | Guard |
|---|---:|
| `t0 -> t1` VAD endpointing, transport and STT final | p95 <= 350 ms |
| `t1 -> t2` prompt assembly, retrieval deadline and LLM TTFT | p95 <= 400 ms |
| `t2 -> t3` sentence decision and TTS admission | p95 <= 350 ms |
| `t3 -> t4` first PCM, network and 80–120 ms prebuffer | p95 <= 300 ms |

Qualification reports end-to-end p50/p90/p95/p99 separately for warm/cold, cache hit/miss, utterance mix, RTT 20/80/150 ms, and 1/5/10 concurrent sessions. A primary release condition uses at least 400 valid turns per main scenario; 50 turns is smoke coverage only.

## 6. Client audio normalization

`record.startStream` output is treated as an arbitrary byte stream, never as already framed protocol data.

```text
platform capture
  -> channel downmix
  -> sample-rate conversion to 16 kHz
  -> PCM16LE conversion
  -> PcmFrameChunker (exact 320 samples / 640 bytes)
  -> client sequence assignment
  -> one serialized WebSocket writer
```

Rules:

- Every microphone frame is exactly 20 ms / 640 payload bytes after normalization.
- The chunker retains a remainder; it never pads normal speech frames.
- Route/device changes, permission loss and capture format changes stop the active turn, notify the server, then require a clean `start_turn` after renegotiation.
- The client reports its source and effective capture configuration in `start`, but the server only receives canonical microphone frames.
- Linux readiness checks verify `parecord`, `pactl`, and `ffmpeg` before voice capture is enabled.

## 7. Authentication, routing and connection lifecycle

### Ticket issue

`POST /api/v1/voice/ticket` requires normal bearer JWT authentication and returns a 256-bit random, opaque, single-use ticket.

- Store only `SHA-256(ticket)` in shared cache.
- TTL: 30 seconds from issue to WebSocket upgrade.
- Bind ticket to authenticated user, allowed origin/client class, quota policy and optional `resume_session_id`.
- Consume atomically with `GETDEL` semantics. Production fails closed when shared storage is unavailable.
- Rate-limit issue attempts and upgrades independently.

### Handshake controls

- Browser: require an allowlisted `Origin`; native clients may omit `Origin` but remain ticket-authenticated.
- Redact ticket query values at CDN, gateway, app, APM, error tracker and access-log layers. Do not include them in traces.
- Disable `permessage-deflate` for PCM traffic.
- Enforce max HTTP upgrade headers, max JSON control message, max binary frame, ping/pong heartbeat and idle timeout.
- Close with documented application codes: `4400` invalid protocol, `4401` invalid/expired ticket, `4403` ownership/origin failure, `4408` idle timeout, `4409` size/quota limit, `4503` server overloaded.

### Worker ownership and resume

- New sessions may land on any ready worker.
- V1 runs one AI voice worker, so reconnect reaches the in-process session owner.
- If that worker restarted or the session expired, server returns `resume_unavailable`; client opens a clean session and does not replay microphone audio.
- A reconnect always uses a fresh ticket. `session_id` is non-secret and only selects routing; the ticket authorizes access.
- Deployments drain WebSockets for at least the configured maximum session duration before worker termination.

## 8. Protocol v1

### JSON envelope

Every server event has this envelope:

```json
{
  "protocol_version": 1,
  "type": "stt.partial",
  "session_id": "vs_...",
  "turn_id": "vt_...",
  "event_seq": 42,
  "trace_id": "...",
  "payload": {}
}
```

`turn_id` is `null` only for connection-level events. `event_seq` is strictly monotonic for all server JSON events. JSON Schema fixtures define every field, type, limit, close code and retryability rule; Dart and Python tests consume the same fixtures.

### State machine

| State | Allowed client action | Server result |
|---|---|---|
| `connecting` | `start` | `session_started` or `voice.error` + close |
| `ready` | `start_turn`, `resume`, close | `turn_started` or resume replay |
| `listening` | binary mic, `cancel_turn` | `stt.partial`, `stt.final` |
| `generating` | `cancel_turn` | `llm.token`, `sentence.final`, TTS events |
| `speaking` | `cancel_turn` | remaining audio, `turn.done` |
| `cancelling` | no new audio | `turn.cancelled`, then `ready` |
| `terminal` | none | socket close |

Invalid state/event combinations return a stable `voice.error` with `code`, `scope`, `retryable`, `message`, and optional `sentence_seq`; they never mutate turn state.

### Control and output events

Required client controls: `start`, `resume`, `start_turn`, `cancel_turn`, `playback.ack`.

Required server outputs: `session_started`, `turn_started`, `ack`, `stt.partial`, `stt.final`, `llm.token`, `llm.done`, `sentence.final`, `tts.audio.start`, `tts.audio.end`, `stt.backpressure`, `turn.cancelled`, `turn.done`, `turn.persisted`, `voice.error`.

`start_turn` carries an idempotency key unique within `(user, chat_session_id, voice_session)`. Its retained terminal state has a bounded TTL equal to the resume window. Repeating the key returns the original `turn_started` and current terminal state; it never starts another model call.

### Binary framing

Client microphone header, 14 bytes, big-endian:

```text
version:u8 | flags:u8 | audio_seq:u32 | client_ts_ms:u64 | pcm:s16le[640]
```

Server TTS header, 16 bytes, big-endian:

```text
version:u8 | kind:u8=2 | turn_seq:u32 | sentence_seq:u16 |
audio_seq:u32 | payload_len:u32 | pcm:s16le[payload_len]
```

`tts.audio.start` declares `turn_seq`, `sentence_seq`, `sample_rate`, `channels`, `format`, expected replay cursor and whether total length is unknown. Unknown versions/kinds close with `4400`; oversized or malformed frames close with `4409`.

### Ordering, acknowledgement and replay

- Client and server each use one outbound writer. Control messages and binary frames are admitted into that writer in source order.
- `turn_started.accept_audio_after_seq` opens microphone admission. Frames at or below the cutover never enter the new turn.
- `ack` means a microphone frame has entered the bounded STT queue, not that STT processed it. Client only retransmits unacknowledged frames within a bounded resend window.
- `playback.ack(state=buffered|played)` identifies `(turn_seq, sentence_seq, audio_seq)`. Only `played` advances the non-replay cursor.
- Resume first replays the necessary `tts.audio.start` metadata, then non-played binary frames, then later JSON events. Client deduplicates by the full audio tuple and resets its released stream before replay.
- `turn.done` is emitted only after the final `tts.audio.end` has been written. `llm.done` may occur earlier than audio completion.

## 9. Turn processing

1. Client creates a fresh logical turn only in `ready` state.
2. Existing VAD/STT emits partials and a final transcript.
3. Any accepted non-empty final opens generation. Low-confidence behavior follows an explicit policy: confirmation below the hard threshold; otherwise proceed with `transcript_uncertain=true`.
4. TRACE-CAG diagnosis/retrieval starts in parallel with a 250 ms deadline. Late retrieval is recorded as degradation and does not mutate an already-issued LLM prompt.
5. The voice prompt requests plain, speakable learner-facing text. Provider reasoning must be disabled or read from a structurally separate field.
6. An incremental sanitizer with bounded look-behind removes hidden markers and internal payloads even when markers span tokens. EOF while hidden discards the hidden buffer.
7. A voice renderer converts UI-safe text into TTS-safe text: strips markdown/code/URLs when not intended for speech, normalizes numbers and punctuation, and preserves the user language.
8. The sentence splitter creates ordered TTS jobs. It protects abbreviations, decimals, initials, paired quotes and code spans; it prefers punctuation/clause boundaries, uses a minimum word/character threshold, then applies the 250 ms timer or 160-character ceiling with safe whitespace fallback.
9. The TTS adapter streams PCM chunks. The client starts released-buffer playback after a measured 80–120 ms prebuffer.
10. Cancellation propagates one cancellation token to LLM, TTS queue and synthesis worker. Blocking inference may finish physically, but stale output is discarded and never reaches the writer.

## 10. TTS adapter contract

```text
prepare(profile) -> readiness
synthesize_stream(sentence, config, cancel_token) -> async PCM chunks
cancel(turn_id)
close()
```

The adapter reports model/voice version, sample rate, channel count, first-PCM timestamp, completion, cancellation and failure. A provider cannot be selected for production merely because it emits a final WAV/PCM file; it must pass the Gate 0 first-PCM benchmark.

Piper CPU is the baseline. GPU TTS is optional and must implement the same stream/cancellation contract. Model readiness is part of readiness probes; a cold/unwarmed model is never routed to the warm-SLO cohort.

## 11. Bounds, overload and durability

Initial values are benchmark-tunable but must be explicit in configuration:

| Resource | Initial bound | On overflow |
|---|---:|---|
| STT ingress per active turn | 1 s / 32 KiB | `stt.backpressure`; then cancel with `INPUT_BACKPRESSURE` |
| Coalescible partial/UI token buffer | 16 KiB | Coalesce newest state only |
| Ordered TTS job queue per session | 3 sentences / 1,000 UTF-8 bytes | Stop generation or cancel with `OUTPUT_BACKPRESSURE` |
| Live outbound audio | First of 4 s or 256 KiB | Pause admission; then cancel non-droppable turn |
| Replay cache per session | Unplayed audio, max 30 s / 1 MiB | Cancel with `OUTPUT_BACKPRESSURE` if ACKs do not free space |
| Idempotency records | 32 keys per voice session | Evict terminal records by TTL/LRU only |
| Session duration | 10 min | Graceful terminal event and close |

One global TTS semaphore and bounded admission queue control total host concurrency. Under pressure: optional STT verification degrades first, then new `start_turn` receives `server_busy`. Queues never grow without a declared byte and item limit.

Completed turns append an immutable idempotent snapshot to an AI-service Redis Stream before asynchronous persistence to the existing Mongo/Redis Lexi stores. `turn.done` may report `persistence_status=pending`; `turn.persisted` is advisory. A client never assumes a missing later event means its turn was discarded.

## 12. Privacy and safety

- Do not persist raw microphone PCM by default.
- Document transcript retention, provider data processing, deletion path, and consent text before public rollout.
- Trace IDs and metrics contain no transcript, ticket, raw audio or full prompt. Avoid high-cardinality IDs as metric labels.
- Apply streaming output safety policy before text enters the voice renderer. Sanitizing hidden reasoning is not a substitute for content safety.
- Quotas cover connection minutes, STT seconds, LLM tokens, TTS characters, max turn duration and max session duration.

## 13. Client platform plan

| Tier | Platforms | Release condition |
|---|---|---|
| Tier 1 | Chrome Web, Android, iOS/Safari | Gate 0 and device suite pass; product SLO applies |
| Tier 2 | macOS, Windows | Contract and reliability suite pass; SLO reported per platform |
| Tier 3 | Linux, Firefox | Dependency/readiness and device matrix pass; enabled after Tier 1/2 telemetry is healthy |

The playback adapter owns released-buffer lifecycle, prebuffering, underrun callbacks, interruption handling, route-change recovery, audio-session/focus behavior, and browser audio-context unlock initiated from the microphone gesture. Bluetooth and device route changes are tested as capture reconfiguration events, not assumed to preserve 16 kHz input.

## 14. Test strategy

| Layer | Required coverage |
|---|---|
| Python unit | ticket issue/consume, authorization, state machine, framing, sanitizer split tokens, sentence boundaries, queues, cancellation, replay, durable outbox, runtime profiles |
| Dart unit | normalizer/rechunker, parser, sequence/order checks, duplicate suppression, buffer bounds, playback acknowledgement, disposal, route changes |
| Contract | Shared JSON Schema and binary fixtures consumed by both languages; compatibility tests for every protocol version |
| Integration | Paced fake mic/STT/LLM/TTS asserts ordering, no stale output, cancellation and first-audio timing |
| Fuzz/security | malformed JSON/binary, duplicate/gap/wrap sequences, ticket replay, origin failure, oversized frames, reconnect race |
| Device | Chrome/Safari/Firefox, Android/iOS, macOS/Windows/Linux; speaker, headset/Bluetooth, interruptions and autoplay |
| Load | 1/5/10 qualified concurrent sessions plus saturation test to determine safe admission capacity |

Existing STT, TTS, Lexi, provider and gateway suites remain green. No migration flag is enabled by a test suite that bypasses real client playback callbacks.

## 15. Delivery phases and exit criteria

| Phase | Scope | Owner roles | Exit criteria |
|---|---|---|---|
| 0. Feasibility | Four Gate 0 spikes, benchmark report, package/version pinning | Flutter, AI/ML, Backend | Explicit go/no-go and approved latency envelope |
| 1. Contract | Schema, state machine, fixtures, close/error taxonomy, gateway resume routing | Backend, Flutter | Python/Dart contract tests pass independently |
| 2. Server happy path | Ticket, WebSocket session, STT final -> LLM -> first TTS PCM, traces | Backend, AI/ML | Fake-client end-to-end stream ordered and bounded |
| 3. Tier-1 client | Canonical capture, one writer, released playback, ACK/cancel | Flutter | Chrome, Android and iOS happy path passes device checks |
| 4. Resilience | Backpressure, idempotency, replay/resume, durable persistence, worker draining | Backend, Flutter | Failure-injection suite passes; no unbounded memory |
| 5. Platform expansion | macOS, Windows, Linux, Firefox adapters/readiness | Flutter, QA | Per-platform compatibility report signed off |
| 6. Qualification | Real model load tests, security review, dashboards, runbook | Backend, AI/ML, QA/Infra | SLO/error-budget gates pass for Tier 1 |
| 7. Rollout | Flagged exposure, fallback, progressive platform expansion | Product, Backend, Flutter | Telemetry remains healthy at each exposure step |

## 16. Rollout and rollback

Flags:

- `VOICE_DUPLEX_ENABLED`: master kill switch.
- `VOICE_DUPLEX_PLATFORM_ALLOWLIST`: platform/browser gate.
- `VOICE_DUPLEX_PERCENTAGE`: deterministic user rollout percentage.
- `VOICE_RUNTIME_PROFILE=auto|cpu|gpu`.

Rollout sequence: internal users -> 1% Tier 1 -> 5% -> 25% -> 100% -> Tier 2 -> Tier 3. Each stage runs long enough to capture peak and non-peak traffic.

Fallback is selected before a new learner turn starts. A duplex failure during an active turn produces a scoped error and a clear retry action; it does not silently resend captured microphone audio through REST, which could duplicate or leak a turn.

Rollback is immediate when any hard gate breaches for a sustained window:

- End-to-end warm p95 exceeds the qualified target.
- Turn failure rate, audio underrun rate, unexpected cancellation rate or security error rate exceeds the declared release threshold.
- Queue saturation grows without recovery.
- Any ticket replay, cross-user session access or transcript/privacy incident appears.

## 17. Operational metrics and release gates

Dashboards must include:

- `t0..t4` latency histogram and each component guard.
- STT final latency, LLM TTFT, sentence-boundary wait, TTS first PCM, prebuffer and first non-silent playback.
- Queue bytes/items, coalescing, backpressure, admission rejects, cancellations and stale-output drops.
- Replay/resume attempts, owner-miss resumes, reconnects, worker drains and persistence lag/failure.
- TTS/STT/LLM provider error and warmup/readiness state.
- Per-platform underrun, autoplay failure, capture-format change and route-change events.

Before 100% Tier-1 rollout, product and engineering must approve numerical thresholds for success rate, underrun rate, persistence completion, resume success, and error budget. These thresholds belong in the release checklist—not in informal dashboard interpretation.

## 18. Decisions that require explicit sign-off

1. Accept 1.5 s p95 only at RTT <=80 ms for v1; use 2.0 s p95 as the 150 ms reporting target until proven otherwise.
2. Adopt fixed canonical 16 kHz mono microphone framing with client-side normalization.
3. Run one AI voice worker for v1; add sticky multi-worker routing only after capacity measurements require it.
4. Require durable outbox semantics for completed turn persistence.
5. Release by platform tier rather than all six targets simultaneously.
6. Do not enable any TTS model until it passes first-non-silent-PCM benchmarks on production-like hardware.

## 19. Definition of done

The feature is done only when:

- Gate 0 passed and results are attached to the release record.
- Protocol v1 schemas, state machine and cross-language fixtures are versioned.
- Tier-1 devices satisfy the warm, established-socket SLO under qualified load.
- Audio normalization, replay/resume, cancellation and backpressure are proven by automated tests and failure injection.
- Privacy, retention, provider handling and user-facing failure behavior are approved.
- Dashboards, alerts, runbook, feature flags and rollback have been exercised in staging.
- REST STT plus Lexi SSE fallback remains functional until production telemetry is stable after staged rollout.
