"""Validated configuration for realtime STT."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _bool(name: str, default: bool) -> bool:
    return os.getenv(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class STTConfig:
    enabled: bool = True
    sample_rate: int = 16000
    channels: int = 1
    audio_format: str = "pcm16"
    frame_ms: int = 20
    max_client_chunk_ms: int = 250
    primary_engine: str = "moonshine"
    primary_model: str = "tiny_streaming"
    primary_device: str = "cpu"
    fallback_primary_engine: str = "sherpa"
    sherpa_model_dir: str = (
        "models/sherpa/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17"
    )
    vad_engine: str = "silero"
    silero_model_path: str = "models/sherpa/silero_vad.onnx"
    verify_enabled: bool = True
    verify_model: str = "base.en"
    verify_device: str = "cpu"
    verify_compute_type: str = "int8"
    verify_language: str = "en"
    verify_beam_size: int = 1
    verify_timeout_ms: int = 10000
    confidence_accept: float = 0.85
    confidence_verify: float = 0.78
    verify_max_duration_ms: int = 8000
    min_speech_ms: int = 250
    min_silence_ms: int = 600
    speech_pad_ms: int = 200
    pre_roll_ms: int = 300
    max_segment_ms: int = 12000
    hard_cap_segment_ms: int = 15000
    ring_buffer_seconds: int = 30
    temp_dir: str = "/tmp/stt_sessions"
    temp_file_ttl_minutes: int = 60
    temp_rotation_seconds: int = 30
    save_audio_for_debug: bool = False
    audio_queue_max_frames: int = 200
    max_active_sessions: int = 20
    max_sessions_per_user: int = 2
    max_connections_per_user: int = 3
    max_verify_concurrency: int = 2
    first_message_timeout_seconds: float = 10.0
    session_start_timeout_seconds: float = 10.0
    session_idle_timeout_seconds: int = 60
    session_hard_limit_minutes: int = 60
    session_stop_timeout_seconds: float = 3.0
    downstream_response_timeout_seconds: float = 35.0
    resume_window_seconds: int = 30
    degraded_whisper_primary: bool = True
    legacy_upload_max_bytes: int = 10 * 1024 * 1024
    emit_candidate_events: bool = False

    @classmethod
    def from_env(cls) -> "STTConfig":
        legacy_model = os.getenv("STT_MODEL_NAME") or os.getenv("WHISPER_MODEL_SIZE")
        return cls(
            enabled=_bool("STT_ENABLED", True),
            sample_rate=int(os.getenv("STT_SAMPLE_RATE", "16000")),
            channels=int(os.getenv("STT_CHANNELS", "1")),
            audio_format=os.getenv("STT_AUDIO_FORMAT", "pcm16"),
            frame_ms=int(os.getenv("STT_FRAME_MS", "20")),
            max_client_chunk_ms=int(os.getenv("STT_MAX_CLIENT_CHUNK_MS", "250")),
            primary_engine=os.getenv("STT_PRIMARY_ENGINE", "moonshine"),
            primary_model=os.getenv("STT_PRIMARY_MODEL", "tiny_streaming"),
            primary_device=os.getenv("STT_PRIMARY_DEVICE", "cpu"),
            fallback_primary_engine=os.getenv("STT_FALLBACK_PRIMARY_ENGINE", "sherpa"),
            sherpa_model_dir=os.getenv(
                "STT_SHERPA_MODEL_DIR",
                "models/sherpa/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17",
            ),
            vad_engine=os.getenv("STT_VAD_ENGINE", "silero"),
            silero_model_path=os.getenv(
                "STT_SILERO_MODEL_PATH", "models/sherpa/silero_vad.onnx"
            ),
            verify_enabled=_bool("STT_VERIFY_ENABLED", True),
            verify_model=os.getenv("STT_VERIFY_MODEL", legacy_model or "base.en"),
            verify_device=os.getenv(
                "STT_VERIFY_DEVICE", os.getenv("STT_DEVICE", "cpu")
            ),
            verify_compute_type=os.getenv(
                "STT_VERIFY_COMPUTE_TYPE",
                os.getenv(
                    "STT_COMPUTE_TYPE", os.getenv("WHISPER_COMPUTE_TYPE", "int8")
                ),
            ),
            verify_language=os.getenv("STT_VERIFY_LANGUAGE", "en"),
            verify_beam_size=int(os.getenv("STT_VERIFY_BEAM_SIZE", "1")),
            verify_timeout_ms=int(os.getenv("STT_VERIFY_TIMEOUT_MS", "10000")),
            confidence_accept=float(os.getenv("STT_CONFIDENCE_ACCEPT", "0.85")),
            confidence_verify=float(os.getenv("STT_CONFIDENCE_VERIFY", "0.78")),
            verify_max_duration_ms=int(os.getenv("STT_VERIFY_MAX_DURATION_MS", "8000")),
            min_speech_ms=int(os.getenv("STT_MIN_SPEECH_MS", "250")),
            min_silence_ms=int(os.getenv("STT_MIN_SILENCE_MS", "600")),
            speech_pad_ms=int(os.getenv("STT_SPEECH_PAD_MS", "200")),
            pre_roll_ms=int(os.getenv("STT_PRE_ROLL_MS", "300")),
            max_segment_ms=int(os.getenv("STT_MAX_SEGMENT_MS", "12000")),
            hard_cap_segment_ms=int(os.getenv("STT_HARD_CAP_SEGMENT_MS", "15000")),
            ring_buffer_seconds=int(os.getenv("STT_RING_BUFFER_SECONDS", "30")),
            temp_dir=os.getenv("STT_TEMP_DIR", "/tmp/stt_sessions"),
            temp_file_ttl_minutes=int(os.getenv("STT_TEMP_FILE_TTL_MINUTES", "60")),
            save_audio_for_debug=_bool("STT_SAVE_AUDIO_FOR_DEBUG", False),
            audio_queue_max_frames=int(os.getenv("AUDIO_QUEUE_MAX_FRAMES", "200")),
            max_active_sessions=int(os.getenv("STT_MAX_ACTIVE_SESSIONS", "20")),
            max_sessions_per_user=int(os.getenv("STT_MAX_SESSIONS_PER_USER", "2")),
            max_connections_per_user=int(
                os.getenv("STT_MAX_CONNECTIONS_PER_USER", "3")
            ),
            max_verify_concurrency=int(os.getenv("STT_MAX_VERIFY_CONCURRENCY", "2")),
            first_message_timeout_seconds=float(
                os.getenv("STT_FIRST_MESSAGE_TIMEOUT_SECONDS", "10")
            ),
            session_start_timeout_seconds=float(
                os.getenv("STT_SESSION_START_TIMEOUT_SECONDS", "10")
            ),
            session_idle_timeout_seconds=int(
                os.getenv("STT_SESSION_IDLE_TIMEOUT_SECONDS", "60")
            ),
            session_hard_limit_minutes=int(
                os.getenv("STT_SESSION_HARD_LIMIT_MINUTES", "60")
            ),
            session_stop_timeout_seconds=float(
                os.getenv("STT_SESSION_STOP_TIMEOUT_SECONDS", "3")
            ),
            downstream_response_timeout_seconds=float(
                os.getenv("STT_DOWNSTREAM_RESPONSE_TIMEOUT_SECONDS", "35")
            ),
            resume_window_seconds=int(os.getenv("STT_RESUME_WINDOW_SECONDS", "30")),
            degraded_whisper_primary=_bool("STT_DEGRADED_WHISPER_PRIMARY", True),
            legacy_upload_max_bytes=int(
                os.getenv("STT_LEGACY_UPLOAD_MAX_BYTES", str(10 * 1024 * 1024))
            ),
            emit_candidate_events=_bool("STT_EMIT_CANDIDATE_EVENTS", False),
        ).validate()

    def validate(self) -> "STTConfig":
        if (self.sample_rate, self.channels, self.audio_format) != (16000, 1, "pcm16"):
            raise ValueError("Realtime STT requires PCM16 mono 16 kHz audio")
        if self.frame_ms not in {20, 30}:
            raise ValueError("STT_FRAME_MS must be 20 or 30")
        if self.hard_cap_segment_ms < self.max_segment_ms:
            raise ValueError("STT_HARD_CAP_SEGMENT_MS must be >= STT_MAX_SEGMENT_MS")
        if self.confidence_accept < self.confidence_verify:
            raise ValueError("STT_CONFIDENCE_ACCEPT must be >= STT_CONFIDENCE_VERIFY")
        if not 0 <= self.confidence_verify <= self.confidence_accept <= 1:
            raise ValueError("STT confidence thresholds must be between 0 and 1")
        for value in (
            self.audio_queue_max_frames,
            self.max_active_sessions,
            self.max_sessions_per_user,
            self.max_connections_per_user,
            self.max_verify_concurrency,
            self.first_message_timeout_seconds,
            self.session_start_timeout_seconds,
            self.ring_buffer_seconds,
            self.session_stop_timeout_seconds,
            self.downstream_response_timeout_seconds,
        ):
            if value <= 0:
                raise ValueError("STT limits must be positive")
        Path(self.temp_dir).mkdir(parents=True, exist_ok=True)
        return self
