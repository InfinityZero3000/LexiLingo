# STT Production Checklist

## Runtime

- Silero VAD runs through Sherpa-ONNX and does not require PyTorch.
- Run `scripts/download_stt_models.sh` while building the image.
- Allow Moonshine model provisioning during image build, not first user request.
- On Intel macOS, expect Moonshine's current PyPI dylib to fail architecture
  loading; Sherpa Zipformer becomes the streaming primary automatically.
- Confirm Faster-Whisper `base.en` is cached and uses CPU `int8`.
- Confirm `large-v3` is not configured in the realtime environment.

## WebSocket

- Route `/api/v1/stt/stream` with sticky sessions or one worker.
- Disable proxy response buffering.
- Set proxy idle timeout above `STT_SESSION_IDLE_TIMEOUT_SECONDS`.
- Allow binary messages but cap frame payloads to 250 ms of PCM16.
- Send Authorization bearer headers where the client permits them; query tokens
  are a compatibility option and should be short-lived.

## Capacity

- Calibrate `STT_MAX_ACTIVE_SESSIONS` and verifier concurrency on target CPUs.
- Alert on queue depth, dropped frames, gaps, uncertain finals, and disk use.
- Run 30-60 minute memory tests and concurrent-session load tests.
- Keep raw/debug audio disabled in production.

## Delivery

- Verify partial and candidate events never enter TRACE-CAG.
- Verify final events preserve timestamps, confidence provenance, source,
  verification status, and uncertainty.
- Verify uncertain text causes confirmation behavior downstream.
- Exercise reconnect within the resume window without duplicate final events.

## Shutdown and Rollback

- Drain WebSockets before terminating the process.
- Confirm open temp files are closed and stale files are removed.
- Roll back by disabling `STT_ENABLED` or directing clients to the bounded
  short-clip endpoint; do not restore long base64 uploads.
