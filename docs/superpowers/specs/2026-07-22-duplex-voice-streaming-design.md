# Duplex Voice Streaming Design

**Date:** 2026-07-22
**Status:** Approved for implementation planning
**Scope:** Flutter Web, Android, iOS, macOS, Windows, Linux, and AI service

## Goal and Boundaries

Deliver first audible assistant audio within 1.5 seconds p95 after the learner
stops speaking, using one duplex WebSocket for microphone PCM, streaming STT,
real LLM token streaming, sentence detection, streaming TTS, and immediate
playback. Reuse the existing STT session/VAD/resume code. Keep REST STT and Lexi
SSE behind a migration fallback. Defer WebRTC, full barge-in, and acoustic echo
cancellation; v1 is half duplex.

The SLO applies to warm models and an established socket at qualified load.
Cold startup is measured separately.

## Architecture and Latency Path

```text
Flutter client
  -> POST /api/v1/voice/ticket
  -> WS /api/v1/stt/stream?ticket=<single-use ticket>
       -> microphone PCM frames
       <- STT partial/final -> safe LLM tokens -> sentence events
       <- TTS metadata + PCM frames -> bounded client buffer -> playback
```

The route remains a transport adapter. `VoiceSession` owns bounded turn state.
Models are prewarmed at startup; history and learner profile are prefetched when
the socket opens. After `stt.final`, TRACE-CAG diagnosis/retrieval run in parallel
with a 250 ms deadline. Late context does not block generation: the voice prompt
falls back to prefetched context and records degradation. This is a new bounded
voice path; the legacy SSE path keeps its existing behavior.

Provider reasoning is disabled or read from a structurally separate field. A
defensive incremental sanitizer retains bounded look-behind/state for markers
split across tokens, including `<think>` and internal TRACE-CAG payloads.
Possible marker prefixes are withheld until classified; hidden spans are never
emitted, and EOF while hidden discards the hidden buffer.

Latency budget, measured at qualified concurrency:

| Stage | p95 |
|---|---:|
| VAD end to STT final | 350 ms |
| STT final to first safe LLM token | 400 ms |
| First token to first TTS boundary | 350 ms |
| First TTS boundary to playback | 300 ms |
| Total budget / SLO | 1,400 / 1,500 ms |

## Authentication and Turn Context

`POST /api/v1/voice/ticket` uses the normal bearer JWT. It issues 256 random
bits with at most a 30-second opening lifetime. Only the SHA-256 ticket hash is
stored, bound to the authenticated user, and atomically consumed once through
the shared cache (`GETDEL` semantics). Production fails closed without shared
storage; process-local storage is development-only.

Ticket issuance and WebSocket attempts are rate limited. Web handshakes enforce
the configured Origin allowlist. Ticket query values are redacted from logs.
Quotas cover connection time, STT seconds, LLM tokens, TTS characters, and
maximum turn/session duration.

Socket-level `start` creates only the voice session and supplies
`chat_session_id`, audio configuration, language, learner level, native language,
voice, TTS speed, and TTS enabled. Each `start_turn` supplies a unique
`idempotency_key` for that logical learner turn. The server derives the user from
the ticket, validates chat ownership, and generates `turn_id`; it never trusts a
client `user_id`. Repeating `start_turn` with the same key returns the original
`turn_started` and retained terminal state instead of creating another turn.

## Wire Contract

Every server JSON event includes `type`, `session_id`, nullable `turn_id`, and
monotonic `event_seq`; connection-level events use `turn_id=null`. Required
control/events are `start`, `resume`, `start_turn`, `cancel_turn`,
`session_started`, `turn_started`, `stt.partial`, `stt.final`, `llm.token`, `llm.done`,
`sentence.final`, `tts.audio.start`, `tts.audio.end`, `ack`, `playback.ack`,
`stt.backpressure`, `turn.cancelled`, `turn.done`, `turn.persisted`, and
`voice.error`.

Client microphone binary retains the deployed 14-byte big-endian header:

```text
version:u8 | flags:u8 | audio_seq:u32 | client_ts_ms:u64 | pcm:s16le
```

Version 1 accepts 640-1,280 payload bytes: 20-40 ms at 16 kHz mono. Server TTS
binary uses a distinct 16-byte big-endian header:

```text
version:u8 | kind:u8=2 | turn_seq:u32 | sentence_seq:u16 |
audio_seq:u32 | payload_len:u32 | pcm:s16le[payload_len]
```

Unknown versions/kinds close with `4400`; oversized frames close with `4409`.
After `session_started`, each exchange begins with `start_turn`; the server
allocates `turn_id`/`turn_seq` and replies `turn_started` with
`accept_audio_after_seq`. Audio is rejected until that reply. Microphone sequence
numbers remain session-global and strictly increasing, so frames at or below the
cutover cannot enter the new turn. Because one socket preserves message order,
`cancel_turn` closes admission before a later `start_turn`; queued frames retain
the turn assigned at admission and are discarded when that turn is cancelled.

`ack` means microphone data entered the bounded STT queue. `playback.ack`
contains sentence/audio sequence and `state=buffered|played`; only `played`
advances the non-replay cursor. `resume` supplies last microphone ACK,
`event_seq`, and played-audio cursor. Shared JSON fixtures are canonical for
field types, limits, and error codes.

One outbound writer serializes JSON and binary. `tts.audio.start`, its frames,
`tts.audio.end`, then `turn.done` cannot race. `turn.done` is emitted only after
the final audio end event has actually been written.

## Processing and Bounds

1. Client captures PCM16/16 kHz/mono in 20-40 ms frames.
2. Existing VAD/STT emits partials. Any accepted, non-empty `stt.final` may open
   generation; verification is optional enrichment. An uncertain final follows
   the configured confidence policy: request confirmation below the hard
   threshold, otherwise proceed while marking uncertainty. Verifier timeout or
   overload cannot silently suppress a turn.
3. Safe tokens stream immediately to UI and sentence splitter.
4. The splitter handles Unicode terminators while protecting abbreviations,
   decimals, initials, markdown/code spans, and paired quotes. A monotonic 250 ms
   first-boundary timer or 160-character ceiling uses a safe whitespace split.
   EOF flushes remaining text; cancellation resets state; empty/punctuation-only
   fragments are dropped. Defaults remain benchmark-tunable.
5. Completed sentences enter one ordered, bounded TTS queue per session.
6. A streaming TTS engine emits PCM chunks without constructing WAV/base64.
7. Client starts playback after a configurable 80-120 ms prebuffer.

Live output and replay have separate item and byte bounds. Partial STT and UI
tokens may coalesce. Finals, sentence events, audio, and terminal events cannot
be silently dropped: non-droppable overflow cancels the turn with
`OUTPUT_BACKPRESSURE`. Replay is partitioned per turn and evicts only completed,
fully played turns. Played audio is never replayed.

Starting capture creates a new turn only when none is active. After VAD final,
capture pauses while assistant audio plays. A user gesture sends `cancel_turn`,
cancels LLM/TTS, drops unplayed audio, then restarts capture.

Persistence receives one immutable idempotent turn snapshot off the audio
critical path with bounded retry. `turn.done` may say `persistence_status=pending`;
the socket later emits `turn.persisted` or a scoped persistence error.

## CPU/GPU and TTS Runtime

`VOICE_RUNTIME_PROFILE=auto|cpu|gpu` selects explicit STT/TTS models and
concurrency; `auto` detects capability once at startup. Remote LLM configuration
is independent of local GPU availability. Piper CPU is the baseline. A GPU TTS
adapter is optional but must advertise streaming and pass the same contract.

The streaming TTS interface exposes readiness/warmup, chunk metadata,
cancellation, and close. Blocking synthesis runs off the event loop. A dedicated
global semaphore and bounded admission queue control cross-session TTS per
profile; one consumer per session preserves sentence order until benchmarks
justify parallel synthesis.

On overload, optional STT verification degrades first; then new turns receive
`server_busy`. Queues never grow without limit.

## Cross-Platform Client

Capture reuses `record.startStream` with PCM16/16 kHz/mono on Web, Android, iOS,
macOS, Windows, and Linux. Startup checks `isEncoderSupported` and reports any
effective hardware-adjusted configuration before `start`. Duplex mode no longer
writes AAC files or uses browser speech recognition.

Playback adds `flutter_soloud`, using a released buffer stream with raw s16le PCM
on all six targets. The adapter owns bounded buffering, 80-120 ms prebuffer,
interruptions/audio-session handling, disposal, underrun callbacks, and browser
autoplay unlock from the initiating microphone gesture. Existing `just_audio`
remains for complete-file playback elsewhere.

## Failure Handling

- STT/LLM/TTS errors are scoped to a turn; the socket may remain open.
- TTS failure preserves text and identifies `sentence_seq`.
- Duplicate frames are acknowledged/ignored; gaps emit a stable event/metric.
- Resume operates only inside the existing bounded session window. Production
  uses sticky routing keyed by the non-secret `session_id`, while every reconnect
  obtains a fresh single-use ticket. Session, decoder, queues, and replay remain
  process-local in v1. If the owning worker is gone, the server returns
  `resume_unavailable`; the client opens a clean session and does not replay
  microphone audio from the failed worker.
- Engine unavailability is visible in readiness and returns a stable error.
- Client may raise prebuffer within configured bounds after measured underruns.

## Verification and Rollout

Python tests cover ticket security, protocol framing, output serialization,
incremental sanitizer adversarial token splits, sentence boundaries/timers,
queues, cancellation, replay, persistence, and CPU/GPU configuration. Dart tests
consume the shared fixtures and cover parsing, capture adjustments, ordering,
duplicate suppression, reconnect, playback ACKs, buffer bounds, and disposal.

An integration harness sends a fake microphone through paced fake STT/LLM/TTS
and asserts ordering and time to first audio. Real-device checks cover supported
Chrome/Safari/Firefox, Android/iOS, macOS, Windows, and Linux. Existing STT, TTS,
Lexi, provider, and gateway suites remain green.

For reproducible product SLO measurement, a lightweight client reference VAD
marks the last speech-positive microphone frame without controlling endpointing.
Its `audio_seq` and monotonic `client_ts_ms` already travel in that binary frame.
Timing starts at that timestamp and ends at the playback adapter's
first-consumed-audio callback on the same monotonic client clock. This includes
server VAD hangover, transport, and all processing after actual observed speech;
the server-stage table is diagnostic and must fit inside the end-to-end SLO.
Reference-VAD algorithm/threshold fixtures are identical across qualification
clients. Trace IDs correlate server stages but never subtract different clocks.
Qualification fixes host specs; 1/5/10 concurrent sessions; at least 50
turns per condition; cache-hit/miss and utterance mixes; and 20/80/150 ms RTT
profiles with declared jitter/loss. Reports separate warm/cold results and use
nearest-rank percentiles. Real playback callbacks supplement fake sinks.

`VOICE_DUPLEX_ENABLED` gates rollout. REST STT plus Lexi SSE remains fallback
until telemetry meets the SLO/error budget. Metrics include every latency stage,
queue depth, coalescing, underruns, reconnects, cancellations, and turn failures.
