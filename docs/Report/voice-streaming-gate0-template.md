# Voice Streaming Gate 0

- Date / commit:
- Flutter and Dart versions:
- Playback dependency: `flutter_soloud 3.5.4` (compatibility pin; 4.x requires Dart ≥3.11)
- Devices: Web, Android, iOS, macOS, Windows, Linux
- Runtime profile: CPU / GPU
- Provider and model:
- Piper voice:

## Automated evidence

- `pytest -q tests/stt/test_voice_gate0_benchmark.py`:
- Flutter chunker/normalizer tests:
- JSON report: `docs/Report/voice-streaming-gate0.json`

## Real-device evidence

For every Tier-1 platform, record capture format, first non-silent playback latency,
underruns, cancellation/disposal result, and whether Web audio was unlocked by a
user gesture.

## Decision

- Piper TTFA p95 ≤ 150 ms: PASS / FAIL
- Groq/Gemini TTFT p95 ≤ 300 ms: PASS / FAIL
- Every Tier-1 capture/playback spike: PASS / FAIL
- **GO / NO-GO**:

Gate 0 is GO only when all rows pass. CI never downloads Piper models, calls a
provider, or accesses an audio device; run the real benchmark and device spike
manually in the target environment.
