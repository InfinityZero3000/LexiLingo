"""Sherpa-ONNX Zipformer streaming fallback for x86_64 and edge CPUs."""

from __future__ import annotations

import asyncio
from pathlib import Path

import numpy as np

from api.services.stt.schemas import AudioSegment, PrimaryResult


class SherpaSession:
    def __init__(self, recognizer, language: str):
        self.recognizer = recognizer
        self.stream = recognizer.create_stream()
        self.language = language
        self.last_text = ""

    async def push_audio(self, pcm16: bytes, start_ms: int, end_ms: int):
        samples = np.frombuffer(pcm16, dtype="<i2").astype(np.float32) / 32768.0

        def _decode():
            self.stream.accept_waveform(16000, samples)
            while self.recognizer.is_ready(self.stream):
                self.recognizer.decode_stream(self.stream)
            return _result_text(self.recognizer.get_result(self.stream))

        text = await asyncio.to_thread(_decode)
        if not text or text == self.last_text:
            return None
        self.last_text = text
        return PrimaryResult(
            text=text,
            confidence=_sherpa_confidence(text),
            confidence_source="stream_stability",
            language=self.language,
            source="sherpa-zipformer",
        )

    async def finalize(self, audio: AudioSegment) -> PrimaryResult:
        def _finish():
            self.stream.input_finished()
            while self.recognizer.is_ready(self.stream):
                self.recognizer.decode_stream(self.stream)
            return _result_text(self.recognizer.get_result(self.stream))

        text = await asyncio.to_thread(_finish) or self.last_text
        return PrimaryResult(
            text=text,
            confidence=_sherpa_confidence(text),
            confidence_source="stream_stability",
            language=self.language,
            source="sherpa-zipformer",
        )

    async def close(self) -> None:
        self.stream = None


class SherpaPrimary:
    def __init__(self, model_dir: str):
        self.model_dir = Path(model_dir)
        self.recognizer = None

    async def load(self) -> None:
        if self.recognizer is not None:
            return
        required = {
            "tokens": self.model_dir / "tokens.txt",
            "encoder": self.model_dir / "encoder-epoch-99-avg-1.int8.onnx",
            "decoder": self.model_dir / "decoder-epoch-99-avg-1.int8.onnx",
            "joiner": self.model_dir / "joiner-epoch-99-avg-1.int8.onnx",
        }
        missing = [str(path) for path in required.values() if not path.exists()]
        if missing:
            raise FileNotFoundError(f"Missing Sherpa model files: {missing}")

        def _load():
            import sherpa_onnx

            return sherpa_onnx.OnlineRecognizer.from_transducer(
                tokens=str(required["tokens"]),
                encoder=str(required["encoder"]),
                decoder=str(required["decoder"]),
                joiner=str(required["joiner"]),
                num_threads=2,
                sample_rate=16000,
                feature_dim=80,
                decoding_method="greedy_search",
                provider="cpu",
            )

        self.recognizer = await asyncio.to_thread(_load)

    async def create_session(self, language: str) -> SherpaSession:
        await self.load()
        return SherpaSession(self.recognizer, language)

    async def close(self) -> None:
        self.recognizer = None


def _sherpa_confidence(text: str) -> float:
    if not text:
        return 0.0
    words = text.split()
    return min(0.88, 0.7 + min(len(words), 12) * 0.015)


def _result_text(result) -> str:
    if isinstance(result, str):
        return result.strip()
    return str(getattr(result, "text", "")).strip()
