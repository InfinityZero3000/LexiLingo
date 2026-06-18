"""Streaming endpointing with an energy fallback."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from api.services.stt.config import STTConfig


@dataclass(frozen=True)
class VADEvent:
    speech_started: bool = False
    speech_ended: bool = False
    hard_cap: bool = False


class EnergyEndpointDetector:
    def __init__(self, config: STTConfig, threshold: int = 450):
        self.config = config
        self.threshold = threshold
        self.in_speech = False
        self.speech_ms = 0
        self.silence_ms = 0

    def process(self, pcm16: bytes, duration_ms: int) -> VADEvent:
        samples = np.frombuffer(pcm16, dtype="<i2").astype(np.float32)
        rms = float(np.sqrt(np.mean(samples * samples))) if samples.size else 0.0
        is_speech = rms >= self.threshold
        started = False
        ended = False
        hard_cap = False
        if is_speech:
            self.speech_ms += duration_ms
            self.silence_ms = 0
            if not self.in_speech and self.speech_ms >= self.config.min_speech_ms:
                self.in_speech = True
                started = True
            if self.speech_ms >= self.config.hard_cap_segment_ms:
                ended = hard_cap = True
        elif self.in_speech:
            self.silence_ms += duration_ms
            if self.silence_ms >= self.config.min_silence_ms:
                ended = True
        else:
            self.speech_ms = 0
        if ended:
            self.in_speech = False
            self.speech_ms = 0
            self.silence_ms = 0
        elif self.in_speech and self.speech_ms >= self.config.max_segment_ms:
            ended = True
            self.in_speech = False
            self.speech_ms = 0
            self.silence_ms = 0
        return VADEvent(started, ended, hard_cap)


class SileroVADFactory:
    def __init__(self, model_path: str):
        self.model_path = model_path
        self._config = None

    async def load(self) -> None:
        import asyncio

        def _load():
            from pathlib import Path

            import sherpa_onnx

            if not Path(self.model_path).is_file():
                raise FileNotFoundError(self.model_path)
            silero = sherpa_onnx.SileroVadModelConfig(
                model=self.model_path,
                threshold=0.5,
                min_silence_duration=0.6,
                min_speech_duration=0.25,
                window_size=512,
                max_speech_duration=15,
            )
            return sherpa_onnx.VadModelConfig(
                silero_vad=silero,
                sample_rate=16000,
                num_threads=1,
                provider="cpu",
            )

        self._config = await asyncio.to_thread(_load)

    def create(self, config: STTConfig):
        if self._config is None:
            return EnergyEndpointDetector(config)
        return SileroEndpointDetector(config, self._config)


class SileroEndpointDetector(EnergyEndpointDetector):
    def __init__(self, config: STTConfig, vad_config):
        super().__init__(config)
        import sherpa_onnx

        self._vad = sherpa_onnx.VoiceActivityDetector(
            vad_config,
            buffer_size_in_seconds=config.ring_buffer_seconds,
        )

    def process(self, pcm16: bytes, duration_ms: int) -> VADEvent:
        was_speech = self._vad.is_speech_detected()
        samples = np.frombuffer(pcm16, dtype="<i2").astype(np.float32) / 32768.0
        self._vad.accept_waveform(samples)
        is_speech = self._vad.is_speech_detected()
        started = not was_speech and is_speech
        ended = was_speech and not is_speech and not self._vad.empty()
        if ended:
            self._vad.pop()
        self.in_speech = is_speech
        self.speech_ms = self.speech_ms + duration_ms if self.in_speech else 0
        hard_cap = self.speech_ms >= self.config.hard_cap_segment_ms
        soft_cap = self.speech_ms >= self.config.max_segment_ms
        if hard_cap or soft_cap:
            ended = True
            self.in_speech = False
            self.speech_ms = 0
            self._vad.reset()
        return VADEvent(started, ended, hard_cap)
