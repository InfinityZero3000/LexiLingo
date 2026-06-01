"""
Streaming Text-to-Speech Service

Chunked TTS output for real-time speech generation with:
- Sentence-level chunking for fast first output
- Interruptible playback
- Pre-caching common phrases
- Smooth audio concatenation

Uses Piper TTS with optimizations for streaming.
"""

from __future__ import annotations

import asyncio
import io
import logging
import re
import time
import wave
from dataclasses import dataclass, field
from typing import AsyncGenerator, List, Optional, Callable

from api.core.config import settings
from api.services.dual_stream.dual_stream_state import AudioChunk

logger = logging.getLogger(__name__)


# ============================================================
# CONFIGURATION
# ============================================================

@dataclass
class TTSConfig:
    """Configuration for Streaming TTS."""
    # Audio format
    sample_rate: int = 22050
    channels: int = 1
    sample_width: int = 2  # 16-bit
    
    # Piper settings
    model_path: str = ""
    config_path: str = ""
    speaker_id: int = 0
    
    # Streaming settings
    speed: float = 0.95           # Slightly slower for learners
    min_chunk_chars: int = 10     # Minimum chars per chunk
    max_chunk_chars: int = 200    # Maximum chars per chunk
    sentence_pause_ms: int = 300  # Pause between sentences
    
    # Caching
    enable_cache: bool = True
    cache_size: int = 100


# ============================================================
# TEXT CHUNKER
# ============================================================

class TextChunker:
    """
    Split text into speakable chunks for streaming.
    
    Strategies:
    1. Split on sentence boundaries (. ! ?)
    2. Split on clause boundaries (, ; :)
    3. Fallback: split on word boundaries
    
    Prioritizes natural speech flow over equal chunk sizes.
    """
    
    # Sentence ending patterns
    SENTENCE_END = re.compile(r'([.!?]+)\s*')
    CLAUSE_END = re.compile(r'([,;:]+)\s*')
    
    @classmethod
    def chunk(
        cls,
        text: str,
        min_chars: int = 10,
        max_chars: int = 200,
    ) -> List[str]:
        """
        Split text into chunks for TTS.
        
        Returns list of text chunks optimized for natural speech.
        """
        if not text:
            return []
        
        text = text.strip()
        if len(text) <= min_chars:
            return [text]
        
        chunks = []
        remaining = text
        
        while remaining:
            remaining = remaining.strip()
            if not remaining:
                break
            
            if len(remaining) <= max_chars:
                chunks.append(remaining)
                break
            
            # Try sentence boundary first
            chunk, remaining = cls._split_at_boundary(
                remaining, cls.SENTENCE_END, max_chars
            )
            
            if not chunk:
                # Try clause boundary
                chunk, remaining = cls._split_at_boundary(
                    remaining, cls.CLAUSE_END, max_chars
                )
            
            if not chunk:
                # Fallback: split at word boundary
                chunk, remaining = cls._split_at_word(remaining, max_chars)
            
            if chunk:
                chunks.append(chunk.strip())
        
        return [c for c in chunks if c]
    
    @classmethod
    def _split_at_boundary(
        cls,
        text: str,
        pattern: re.Pattern,
        max_chars: int,
    ) -> tuple:
        """Split at regex boundary within max_chars."""
        # Find all matches within range
        matches = list(pattern.finditer(text[:max_chars]))
        
        if matches:
            # Use last match
            match = matches[-1]
            split_pos = match.end()
            return text[:split_pos], text[split_pos:]
        
        return None, text
    
    @classmethod
    def _split_at_word(
        cls,
        text: str,
        max_chars: int,
    ) -> tuple:
        """Split at word boundary."""
        # Find last space before max_chars
        sub = text[:max_chars]
        last_space = sub.rfind(' ')
        
        if last_space > 0:
            return text[:last_space], text[last_space:]
        
        # No space found - hard split
        return text[:max_chars], text[max_chars:]


# ============================================================
# AUDIO CACHE
# ============================================================

class AudioCache:
    """
    LRU cache for common TTS phrases.
    
    Caches audio for phrases like:
    - "Great job!"
    - "Let me help you..."
    - Common corrections
    """
    
    def __init__(self, max_size: int = 100):
        self._cache: dict = {}
        self._max_size = max_size
        self._access_order: List[str] = []
    
    def get(self, text: str) -> Optional[bytes]:
        """Get cached audio for text."""
        key = text.strip().lower()
        if key in self._cache:
            # Move to end (most recently used)
            self._access_order.remove(key)
            self._access_order.append(key)
            return self._cache[key]
        return None
    
    def put(self, text: str, audio: bytes) -> None:
        """Cache audio for text."""
        key = text.strip().lower()
        
        # Evict if full
        while len(self._cache) >= self._max_size and self._access_order:
            oldest = self._access_order.pop(0)
            self._cache.pop(oldest, None)
        
        self._cache[key] = audio
        self._access_order.append(key)
    
    def clear(self) -> None:
        """Clear cache."""
        self._cache.clear()
        self._access_order.clear()


# ============================================================
# STREAMING TTS SERVICE
# ============================================================

class StreamingTTSService:
    """
    Streaming Text-to-Speech with chunk-based output.
    
    Features:
    - Sentence-level chunking for fast first audio
    - Interruptible: can stop mid-stream
    - Pre-caching common phrases
    - Smooth audio concatenation
    - Optimized for English learning (slightly slower)
    
    Usage:
        tts = StreamingTTSService()
        
        async for chunk in tts.stream_speak(text_generator):
            send_audio(chunk.audio_bytes)
            if interrupted:
                tts.stop()
                break
    """
    
    def __init__(self, config: Optional[TTSConfig] = None):
        self.config = config or TTSConfig(
            model_path=getattr(settings, "TTS_MODEL_PATH", ""),
            config_path=getattr(settings, "TTS_CONFIG_PATH", ""),
            speaker_id=getattr(settings, "TTS_SPEAKER_ID", 0),
        )
        
        self._voice = None
        self._cache = AudioCache(self.config.cache_size) if self.config.enable_cache else None
        self._is_speaking = False
        self._should_stop = False
        self._current_chunk_index = 0
    
    def _load_voice(self):
        """Lazy load Piper voice."""
        if self._voice is not None:
            return self._voice
        
        try:
            from piper import PiperVoice
        except ImportError:
            raise RuntimeError("piper-tts not installed")
        
        if not self.config.model_path:
            raise RuntimeError("TTS_MODEL_PATH not configured")
        
        logger.info(f"Loading Piper TTS: {self.config.model_path}")
        self._voice = PiperVoice.load(
            self.config.model_path,
            config_path=self.config.config_path or None,
        )
        logger.info("✓ Piper TTS loaded")
        return self._voice
    
    @property
    def is_speaking(self) -> bool:
        return self._is_speaking
    
    def stop(self) -> None:
        """Stop current TTS output immediately."""
        self._should_stop = True
        self._is_speaking = False
        logger.info("[TTS] Stop requested")
    
    async def stream_speak(
        self,
        text: str,
        on_chunk: Optional[Callable[[AudioChunk], None]] = None,
    ) -> AsyncGenerator[AudioChunk, None]:
        """
        Stream audio chunks from text.
        
        Args:
            text: Text to synthesize
            on_chunk: Optional callback for each chunk
            
        Yields:
            AudioChunk objects with audio data
        """
        self._is_speaking = True
        self._should_stop = False
        self._current_chunk_index = 0
        
        voice = self._load_voice()
        
        # Split text into chunks
        chunks = TextChunker.chunk(
            text,
            min_chars=self.config.min_chunk_chars,
            max_chars=self.config.max_chunk_chars,
        )
        
        total_chunks = len(chunks)
        
        for i, text_chunk in enumerate(chunks):
            if self._should_stop:
                logger.info(f"[TTS] Stopped at chunk {i}/{total_chunks}")
                break
            
            # Check cache
            cached_audio = None
            if self._cache:
                cached_audio = self._cache.get(text_chunk)
            
            if cached_audio:
                audio_bytes = cached_audio
            else:
                # Synthesize
                audio_bytes = await self._synthesize(voice, text_chunk)
                
                # Cache short phrases
                if self._cache and len(text_chunk) < 50:
                    self._cache.put(text_chunk, audio_bytes)
            
            # Calculate duration
            duration_ms = self._calculate_duration_ms(audio_bytes)
            
            # Create chunk
            chunk = AudioChunk(
                audio_bytes=audio_bytes,
                chunk_index=i,
                is_final=(i == total_chunks - 1),
                text_spoken=text_chunk,
                duration_ms=duration_ms,
                sample_rate=self.config.sample_rate,
            )
            
            self._current_chunk_index = i
            
            if on_chunk:
                on_chunk(chunk)
            
            yield chunk
            
            # Small pause between chunks for natural speech
            if not chunk.is_final and not self._should_stop:
                await asyncio.sleep(self.config.sentence_pause_ms / 1000)
        
        self._is_speaking = False
    
    async def stream_speak_generator(
        self,
        text_generator: AsyncGenerator[str, None],
    ) -> AsyncGenerator[AudioChunk, None]:
        """
        Stream audio from text generator.
        
        Useful when LLM is generating text progressively.
        """
        text_buffer = ""
        
        async for text_chunk in text_generator:
            if self._should_stop:
                break
            
            text_buffer += text_chunk
            
            # Check if we have enough for a sentence
            chunks = TextChunker.chunk(text_buffer, min_chars=20)
            
            if len(chunks) > 1:
                # Speak complete chunks, keep last partial
                for chunk_text in chunks[:-1]:
                    async for audio_chunk in self.stream_speak(chunk_text):
                        yield audio_chunk
                text_buffer = chunks[-1]
        
        # Speak remaining text
        if text_buffer and not self._should_stop:
            async for audio_chunk in self.stream_speak(text_buffer):
                yield audio_chunk
    
    async def _synthesize(self, voice, text: str) -> bytes:
        """Synthesize text to audio bytes."""
        loop = asyncio.get_event_loop()
        
        def do_synthesize():
            wav_io = io.BytesIO()
            voice.synthesize(
                text,
                wav_io,
                speaker_id=self.config.speaker_id,
            )
            return wav_io.getvalue()
        
        return await loop.run_in_executor(None, do_synthesize)
    
    def _calculate_duration_ms(self, audio_bytes: bytes) -> int:
        """Calculate audio duration from WAV bytes."""
        try:
            with io.BytesIO(audio_bytes) as wav_io:
                with wave.open(wav_io, 'rb') as wav:
                    frames = wav.getnframes()
                    rate = wav.getframerate()
                    return int((frames / rate) * 1000)
        except Exception:
            # Estimate from byte size
            bytes_per_second = (
                self.config.sample_rate * 
                self.config.channels * 
                self.config.sample_width
            )
            return int((len(audio_bytes) / bytes_per_second) * 1000)
    
    async def synthesize_text(self, text: str) -> bytes:
        """
        Synthesize complete text (non-streaming).
        
        For compatibility with existing code.
        """
        voice = self._load_voice()
        return await self._synthesize(voice, text)
    
    def preload_phrases(self, phrases: List[str]) -> None:
        """
        Mark phrases for preloading.
        
        Note: Actual preloading happens when preload_async() is called
        from an async context (e.g., during app startup).
        """
        self._phrases_to_preload = phrases
    
    async def preload_async(self) -> None:
        """Preload common phrases into cache (call from async context)."""
        if not self._cache:
            return
        
        phrases = getattr(self, '_phrases_to_preload', TUTOR_PHRASES)
        voice = self._load_voice()
        
        for phrase in phrases:
            if not self._cache.get(phrase):
                audio = await self._synthesize(voice, phrase)
                self._cache.put(phrase, audio)
        
        logger.info(f"[TTS] Preloaded {len(phrases)} phrases")


# ============================================================
# COMMON PHRASES FOR ENGLISH TUTOR
# ============================================================

TUTOR_PHRASES = [
    "Great job!",
    "Well done!",
    "That's correct!",
    "Let me help you.",
    "Try again.",
    "Almost there!",
    "Good effort!",
    "Keep going!",
    "Let's practice together.",
    "Can you try that again?",
]


# ============================================================
# SINGLETON
# ============================================================

_streaming_tts_service: Optional[StreamingTTSService] = None


def get_streaming_tts_service() -> StreamingTTSService:
    """Get or create StreamingTTSService singleton."""
    global _streaming_tts_service
    if _streaming_tts_service is None:
        _streaming_tts_service = StreamingTTSService()
        # Mark phrases for preloading (actual preload happens in async startup)
        _streaming_tts_service.preload_phrases(TUTOR_PHRASES)
    return _streaming_tts_service
