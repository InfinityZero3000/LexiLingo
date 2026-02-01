"""
Whisper Handler - Speech-to-Text

Manages faster-whisper for speech recognition.
"""

import logging
import asyncio
from typing import Optional, Dict, Any, Union
from dataclasses import dataclass
import os
import tempfile
import base64

logger = logging.getLogger(__name__)


@dataclass
class WhisperConfig:
    """Configuration for Whisper model."""
    model_size: str = "base"  # tiny, base, small, medium, large-v3
    model_path: Optional[str] = None  # Local path override
    device: str = "auto"  # cpu, cuda, auto
    compute_type: str = "int8"  # float16, int8, int8_float16
    beam_size: int = 5
    language: str = "en"
    task: str = "transcribe"  # transcribe or translate


class WhisperHandler:
    """
    Handler for Whisper speech-to-text.
    
    Uses faster-whisper for optimized inference.
    """
    
    def __init__(self, config: Optional[WhisperConfig] = None):
        self.config = config or WhisperConfig()
        self.model = None
        self._loaded = False
        self._loading = False
        self._lock = asyncio.Lock()
        
    @property
    def is_loaded(self) -> bool:
        return self._loaded
    
    @property
    def memory_usage_mb(self) -> float:
        """Estimate memory usage based on model size."""
        if not self._loaded:
            return 0.0
        size_map = {
            "tiny": 150,
            "base": 300,
            "small": 500,
            "medium": 1500,
            "large-v3": 3000,
        }
        return float(size_map.get(self.config.model_size, 500))
    
    async def load(self) -> bool:
        """Load the Whisper model."""
        if self._loaded:
            return True
            
        async with self._lock:
            if self._loaded:
                return True
                
            if self._loading:
                while self._loading:
                    await asyncio.sleep(0.1)
                return self._loaded
            
            self._loading = True
            try:
                logger.info(f"[WhisperHandler] Loading Whisper {self.config.model_size}...")
                
                from faster_whisper import WhisperModel
                
                # Detect device
                device = self._detect_device()
                compute_type = self.config.compute_type
                
                # Adjust compute type for CPU
                if device == "cpu" and compute_type == "float16":
                    compute_type = "int8"
                
                # Load model
                model_path = self.config.model_path or self.config.model_size
                
                self.model = WhisperModel(
                    model_path,
                    device=device,
                    compute_type=compute_type,
                )
                
                self._loaded = True
                logger.info(f"[WhisperHandler] ✓ Whisper loaded on {device}")
                return True
                
            except Exception as e:
                logger.error(f"[WhisperHandler] Failed to load: {e}")
                self._loaded = False
                return False
            finally:
                self._loading = False
    
    def _detect_device(self) -> str:
        """Detect best available device."""
        if self.config.device != "auto":
            return self.config.device
            
        try:
            import torch
            if torch.cuda.is_available():
                return "cuda"
        except:
            pass
        return "cpu"
    
    async def unload(self) -> None:
        """Unload model to free memory."""
        if self.model is not None:
            del self.model
            self.model = None
            
        self._loaded = False
        
        import gc
        gc.collect()
        
        logger.info("[WhisperHandler] Model unloaded")
    
    async def transcribe(
        self,
        audio: Union[str, bytes],
        language: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Transcribe audio to text.
        
        Args:
            audio: File path, URL, or base64-encoded audio bytes
            language: Override language detection
            
        Returns:
            {
                "text": "transcribed text",
                "segments": [...],
                "language": "en",
                "duration": 5.2,
                "confidence": 0.95
            }
        """
        if not await self.load():
            raise RuntimeError("Failed to load Whisper model")
        
        # Handle different audio input types
        audio_path = await self._prepare_audio(audio)
        
        try:
            # Run transcription in executor to not block
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                self._transcribe_sync,
                audio_path,
                language,
            )
            return result
            
        finally:
            # Clean up temp file if created
            if audio_path.startswith(tempfile.gettempdir()):
                try:
                    os.remove(audio_path)
                except:
                    pass
    
    def _transcribe_sync(
        self,
        audio_path: str,
        language: Optional[str],
    ) -> Dict[str, Any]:
        """Synchronous transcription."""
        segments, info = self.model.transcribe(
            audio_path,
            beam_size=self.config.beam_size,
            language=language or self.config.language,
            task=self.config.task,
        )
        
        # Collect segments
        segment_list = []
        full_text_parts = []
        total_confidence = 0.0
        segment_count = 0
        
        for segment in segments:
            segment_list.append({
                "start": segment.start,
                "end": segment.end,
                "text": segment.text.strip(),
                "confidence": segment.avg_logprob,
            })
            full_text_parts.append(segment.text.strip())
            total_confidence += segment.avg_logprob
            segment_count += 1
        
        avg_confidence = total_confidence / max(segment_count, 1)
        # Convert log prob to 0-1 confidence
        confidence = min(1.0, max(0.0, 1.0 + avg_confidence))
        
        return {
            "text": " ".join(full_text_parts),
            "segments": segment_list,
            "language": info.language,
            "duration": info.duration,
            "confidence": confidence,
        }
    
    async def _prepare_audio(self, audio: Union[str, bytes]) -> str:
        """Prepare audio input for transcription."""
        if isinstance(audio, str):
            # Check if it's base64
            if audio.startswith("data:audio") or len(audio) > 500:
                try:
                    # Try to decode as base64
                    if "base64," in audio:
                        audio = audio.split("base64,")[1]
                    audio_bytes = base64.b64decode(audio)
                    return await self._save_temp_audio(audio_bytes)
                except:
                    pass
            # Assume it's a file path
            return audio
            
        elif isinstance(audio, bytes):
            return await self._save_temp_audio(audio)
            
        else:
            raise ValueError(f"Unsupported audio type: {type(audio)}")
    
    async def _save_temp_audio(self, audio_bytes: bytes) -> str:
        """Save audio bytes to temp file."""
        # Detect format from magic bytes
        ext = ".wav"
        if audio_bytes[:4] == b"OggS":
            ext = ".ogg"
        elif audio_bytes[:3] == b"ID3" or audio_bytes[:2] == b"\xff\xfb":
            ext = ".mp3"
        elif audio_bytes[:4] == b"fLaC":
            ext = ".flac"
        
        with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as f:
            f.write(audio_bytes)
            return f.name
    
    async def invoke(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Unified invoke interface for ModelGateway.
        
        Args:
            params: {
                "audio": file path, bytes, or base64,
                "language": optional language code
            }
            
        Returns:
            Transcription result
        """
        audio = params.get("audio")
        if not audio:
            raise ValueError("Missing 'audio' parameter")
            
        return await self.transcribe(
            audio=audio,
            language=params.get("language"),
        )


# Singleton instance
_handler: Optional[WhisperHandler] = None


def get_whisper_handler(config: Optional[WhisperConfig] = None) -> WhisperHandler:
    """Get or create Whisper handler singleton."""
    global _handler
    if _handler is None:
        _handler = WhisperHandler(config)
    return _handler
