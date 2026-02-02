"""
Streaming Speech-to-Text Service

Real-time STT with Voice Activity Detection (VAD) for:
- Streaming transcription with partial results
- Utterance boundary detection
- Interruption detection (user speaks while AI is talking)

Uses Faster-Whisper with Silero VAD for optimal latency.
"""

from __future__ import annotations

import asyncio
import io
import logging
import time
import wave
from collections import deque
from dataclasses import dataclass, field
from typing import AsyncGenerator, Callable, Optional, List, Tuple

import numpy as np

from api.core.config import settings
from api.services.dual_stream.dual_stream_state import TranscriptResult

logger = logging.getLogger(__name__)


# ============================================================
# CONFIGURATION
# ============================================================

@dataclass
class STTConfig:
    """Configuration for Streaming STT."""
    # Audio format
    sample_rate: int = 16000
    channels: int = 1
    sample_width: int = 2  # 16-bit
    
    # Whisper settings
    model_name: str = "base"
    device: str = "cuda"
    compute_type: str = "float16"
    beam_size: int = 1  # Faster with beam_size=1
    language: str = "en"
    
    # VAD settings
    vad_threshold: float = 0.5
    min_speech_duration_ms: int = 250
    min_silence_duration_ms: int = 500
    speech_pad_ms: int = 30
    
    # Streaming settings
    chunk_duration_ms: int = 100  # Process every 100ms
    partial_update_interval_ms: int = 300  # Update partials every 300ms
    max_buffer_duration_s: float = 30.0  # Max buffer size


# ============================================================
# AUDIO BUFFER
# ============================================================

@dataclass
class AudioBuffer:
    """
    Ring buffer for audio chunks with VAD state tracking.
    
    Maintains:
    - Raw audio bytes
    - Speech/silence state
    - Timestamps for boundary detection
    """
    config: STTConfig = field(default_factory=STTConfig)
    
    _chunks: deque = field(default_factory=lambda: deque(maxlen=1000))
    _speech_chunks: List[bytes] = field(default_factory=list)
    _is_speaking: bool = False
    _speech_start_time: float = 0.0
    _last_speech_time: float = 0.0
    _total_duration_ms: int = 0
    
    def add(self, chunk: bytes) -> None:
        """Add audio chunk to buffer."""
        self._chunks.append(chunk)
        chunk_duration = len(chunk) / (
            self.config.sample_rate * 
            self.config.channels * 
            self.config.sample_width
        ) * 1000
        self._total_duration_ms += int(chunk_duration)
    
    def add_speech_chunk(self, chunk: bytes) -> None:
        """Add chunk identified as speech."""
        self._speech_chunks.append(chunk)
        self._last_speech_time = time.time()
        if not self._is_speaking:
            self._is_speaking = True
            self._speech_start_time = time.time()
    
    def mark_silence(self) -> None:
        """Mark current audio as silence."""
        if self._is_speaking:
            silence_duration = (time.time() - self._last_speech_time) * 1000
            if silence_duration >= self.config.min_silence_duration_ms:
                self._is_speaking = False
    
    def get_speech_audio(self) -> bytes:
        """Get accumulated speech audio."""
        return b"".join(self._speech_chunks)
    
    def get_all_audio(self) -> bytes:
        """Get all buffered audio."""
        return b"".join(self._chunks)
    
    def clear_speech(self) -> None:
        """Clear speech buffer after processing."""
        self._speech_chunks.clear()
        self._is_speaking = False
        self._speech_start_time = 0.0
    
    def clear(self) -> None:
        """Clear all buffers."""
        self._chunks.clear()
        self._speech_chunks.clear()
        self._is_speaking = False
        self._speech_start_time = 0.0
        self._last_speech_time = 0.0
        self._total_duration_ms = 0
    
    @property
    def is_speaking(self) -> bool:
        return self._is_speaking
    
    @property
    def speech_duration_ms(self) -> int:
        if not self._is_speaking:
            return 0
        return int((time.time() - self._speech_start_time) * 1000)
    
    @property
    def total_duration_ms(self) -> int:
        return self._total_duration_ms
    
    def has_minimum_speech(self) -> bool:
        """Check if buffer has minimum speech duration."""
        return self.speech_duration_ms >= self.config.min_speech_duration_ms


# ============================================================
# VAD WRAPPER
# ============================================================

class VADProcessor:
    """
    Voice Activity Detection using Silero VAD.
    
    Provides:
    - Frame-level speech probability
    - Utterance boundary detection
    - Interruption detection
    """
    
    def __init__(self, config: STTConfig):
        self.config = config
        self._model = None
        self._is_loaded = False
    
    def _load_model(self):
        """Lazy load Silero VAD model."""
        if self._is_loaded:
            return
        
        try:
            import torch
            
            model, utils = torch.hub.load(
                repo_or_dir='snakers4/silero-vad',
                model='silero_vad',
                force_reload=False,
                onnx=True,  # Use ONNX for faster inference
            )
            self._model = model
            self._get_speech_timestamps = utils[0]
            self._is_loaded = True
            logger.info("✓ Silero VAD loaded (ONNX)")
            
        except Exception as e:
            logger.warning(f"Silero VAD not available: {e}, using energy-based VAD")
            self._model = None
            self._is_loaded = True
    
    def is_speech(self, audio_bytes: bytes) -> Tuple[bool, float]:
        """
        Detect if audio chunk contains speech.
        
        Returns:
            Tuple of (is_speech, confidence)
        """
        self._load_model()
        
        if self._model is None:
            # Fallback: energy-based VAD
            return self._energy_vad(audio_bytes)
        
        try:
            import torch
            
            # Convert bytes to tensor
            audio_np = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
            audio_tensor = torch.from_numpy(audio_np)
            
            # Get speech probability
            speech_prob = self._model(audio_tensor, self.config.sample_rate).item()
            is_speech = speech_prob >= self.config.vad_threshold
            
            return is_speech, speech_prob
            
        except Exception as e:
            logger.warning(f"VAD error: {e}")
            return self._energy_vad(audio_bytes)
    
    def _energy_vad(self, audio_bytes: bytes) -> Tuple[bool, float]:
        """Simple energy-based VAD as fallback."""
        audio_np = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32)
        energy = np.sqrt(np.mean(audio_np ** 2))
        
        # Normalize to 0-1 range (assuming 16-bit audio)
        normalized_energy = min(energy / 3000.0, 1.0)
        is_speech = normalized_energy > 0.1
        
        return is_speech, normalized_energy
    
    def detect_utterance_end(
        self,
        buffer: AudioBuffer,
    ) -> bool:
        """
        Detect if current utterance has ended.
        
        Based on:
        - Silence duration after speech
        - Minimum speech duration met
        """
        if not buffer.has_minimum_speech():
            return False
        
        if buffer.is_speaking:
            return False
        
        # Check silence duration
        silence_ms = (time.time() - buffer._last_speech_time) * 1000
        return silence_ms >= self.config.min_silence_duration_ms


# ============================================================
# STREAMING STT SERVICE
# ============================================================

class StreamingSTTService:
    """
    Real-time Speech-to-Text with streaming transcription.
    
    Features:
    - Partial transcripts for UI feedback
    - Final transcripts when utterance complete
    - Interruption detection
    - Optimized for low latency
    
    Usage:
        stt = StreamingSTTService()
        async for result in stt.stream_transcribe(audio_chunks):
            if result.is_partial:
                update_ui(result.text)
            elif result.is_final:
                process_utterance(result.text)
            elif result.is_interruption:
                stop_tts()
    """
    
    def __init__(self, config: Optional[STTConfig] = None):
        self.config = config or STTConfig(
            model_name=getattr(settings, "STT_MODEL_NAME", "base"),
            device=getattr(settings, "STT_DEVICE", "cuda"),
            compute_type=getattr(settings, "STT_COMPUTE_TYPE", "float16"),
        )
        self._model = None
        self._vad = VADProcessor(self.config)
        self._is_ai_speaking = False
        self._last_partial_time = 0.0
    
    def _load_model(self):
        """Lazy load Whisper model."""
        if self._model is not None:
            return self._model
        
        try:
            from faster_whisper import WhisperModel
        except ImportError:
            raise RuntimeError("faster-whisper not installed")
        
        logger.info(f"Loading Whisper: {self.config.model_name} on {self.config.device}")
        self._model = WhisperModel(
            self.config.model_name,
            device=self.config.device,
            compute_type=self.config.compute_type,
        )
        logger.info("✓ Whisper loaded")
        return self._model
    
    def set_ai_speaking(self, is_speaking: bool) -> None:
        """Update AI speaking state for interruption detection."""
        self._is_ai_speaking = is_speaking
    
    async def stream_transcribe(
        self,
        audio_chunks: AsyncGenerator[bytes, None],
        on_interruption: Optional[Callable[[], None]] = None,
    ) -> AsyncGenerator[TranscriptResult, None]:
        """
        Stream transcription from audio chunks.
        
        Args:
            audio_chunks: Async generator yielding audio bytes
            on_interruption: Callback when user interrupts AI
            
        Yields:
            TranscriptResult with partial, final, or interruption
        """
        model = self._load_model()
        buffer = AudioBuffer(self.config)
        
        async for chunk in audio_chunks:
            # Add to buffer
            buffer.add(chunk)
            
            # VAD check
            is_speech, confidence = self._vad.is_speech(chunk)
            
            if is_speech:
                buffer.add_speech_chunk(chunk)
                
                # Check for interruption
                if self._is_ai_speaking:
                    self._is_ai_speaking = False
                    if on_interruption:
                        on_interruption()
                    yield TranscriptResult.interruption()
                
                # Check if should send partial
                now = time.time()
                if (now - self._last_partial_time) * 1000 >= self.config.partial_update_interval_ms:
                    if buffer.has_minimum_speech():
                        partial_text = await self._transcribe_buffer(buffer, is_partial=True)
                        if partial_text:
                            self._last_partial_time = now
                            yield TranscriptResult.partial(partial_text, confidence)
            else:
                buffer.mark_silence()
                
                # Check for utterance end
                if self._vad.detect_utterance_end(buffer):
                    if buffer.has_minimum_speech():
                        final_text = await self._transcribe_buffer(buffer, is_partial=False)
                        if final_text:
                            yield TranscriptResult.final(
                                final_text,
                                confidence=0.9,
                            )
                    buffer.clear_speech()
    
    async def _transcribe_buffer(
        self,
        buffer: AudioBuffer,
        is_partial: bool = False,
    ) -> str:
        """Transcribe audio buffer."""
        model = self._model
        
        audio_bytes = buffer.get_speech_audio()
        if not audio_bytes:
            return ""
        
        # Convert to format Whisper expects
        audio_np = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        
        # Run in thread pool to not block
        loop = asyncio.get_event_loop()
        
        def transcribe():
            segments, _ = model.transcribe(
                audio_np,
                beam_size=self.config.beam_size if not is_partial else 1,
                language=self.config.language,
                vad_filter=False,  # We handle VAD ourselves
                without_timestamps=True,
            )
            return "".join(segment.text for segment in segments).strip()
        
        try:
            text = await loop.run_in_executor(None, transcribe)
            return text
        except Exception as e:
            logger.warning(f"Transcription error: {e}")
            return ""
    
    async def transcribe_audio(self, audio_bytes: bytes) -> TranscriptResult:
        """
        Transcribe complete audio buffer (non-streaming).
        
        For compatibility with existing code.
        """
        model = self._load_model()
        
        audio_np = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        
        loop = asyncio.get_event_loop()
        
        def transcribe():
            segments, info = model.transcribe(
                audio_np,
                beam_size=self.config.beam_size,
                language=self.config.language,
            )
            return "".join(segment.text for segment in segments).strip()
        
        text = await loop.run_in_executor(None, transcribe)
        return TranscriptResult.final(text)


# ============================================================
# SINGLETON
# ============================================================

_streaming_stt_service: Optional[StreamingSTTService] = None


def get_streaming_stt_service() -> StreamingSTTService:
    """Get or create StreamingSTTService singleton."""
    global _streaming_stt_service
    if _streaming_stt_service is None:
        _streaming_stt_service = StreamingSTTService()
    return _streaming_stt_service
