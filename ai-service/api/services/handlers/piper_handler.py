"""
Piper Handler - Text-to-Speech

Manages Piper TTS for speech synthesis.
"""

import logging
import asyncio
from typing import Optional, Dict, Any, Union
from dataclasses import dataclass
import os
import tempfile
import subprocess
import shutil

logger = logging.getLogger(__name__)


@dataclass
class PiperConfig:
    """Configuration for Piper TTS."""
    model_path: str = "models/piper/en_US-lessac-medium.onnx"
    voice: str = "en_US-lessac-medium"
    speaker_id: Optional[int] = None
    length_scale: float = 1.0  # Speaking speed (1.0 = normal)
    noise_scale: float = 0.667
    noise_w: float = 0.8
    sentence_silence: float = 0.2
    output_format: str = "wav"  # wav, mp3, ogg
    sample_rate: int = 22050


class PiperHandler:
    """
    Handler for Piper text-to-speech.
    
    Uses piper-tts for fast neural TTS.
    """
    
    def __init__(self, config: Optional[PiperConfig] = None):
        self.config = config or PiperConfig()
        self._piper_path: Optional[str] = None
        self._model_path: Optional[str] = None
        self._loaded = False
        self._loading = False
        self._lock = asyncio.Lock()
        
    @property
    def is_loaded(self) -> bool:
        return self._loaded
    
    @property
    def memory_usage_mb(self) -> float:
        """Piper models are typically small."""
        if not self._loaded:
            return 0.0
        return 100.0  # ~100MB for medium model
    
    async def load(self) -> bool:
        """Load/verify Piper installation."""
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
                logger.info("[PiperHandler] Initializing Piper TTS...")
                
                # Try to find piper executable
                self._piper_path = await self._find_piper()
                
                if not self._piper_path:
                    # Try using piper-tts Python package
                    try:
                        from piper import PiperVoice
                        self._use_python = True
                        logger.info("[PiperHandler] Using piper-tts Python package")
                    except ImportError:
                        logger.error("[PiperHandler] Piper not found. Install with: pip install piper-tts")
                        return False
                else:
                    self._use_python = False
                
                # Verify model exists
                if os.path.exists(self.config.model_path):
                    self._model_path = self.config.model_path
                else:
                    # Try to find model in common locations
                    model_locations = [
                        f"models/piper/{self.config.voice}.onnx",
                        f"/usr/share/piper-voices/{self.config.voice}.onnx",
                        os.path.expanduser(f"~/.local/share/piper-voices/{self.config.voice}.onnx"),
                    ]
                    for loc in model_locations:
                        if os.path.exists(loc):
                            self._model_path = loc
                            break
                    
                    if not self._model_path:
                        logger.warning(f"[PiperHandler] Model not found at {self.config.model_path}")
                        # Will download on first use
                        self._model_path = self.config.model_path
                
                self._loaded = True
                logger.info(f"[PiperHandler] ✓ Piper initialized")
                return True
                
            except Exception as e:
                logger.error(f"[PiperHandler] Failed to initialize: {e}")
                self._loaded = False
                return False
            finally:
                self._loading = False
    
    async def _find_piper(self) -> Optional[str]:
        """Find piper executable."""
        # Check PATH
        piper = shutil.which("piper")
        if piper:
            return piper
            
        # Check common locations
        locations = [
            "/usr/local/bin/piper",
            "/usr/bin/piper",
            os.path.expanduser("~/.local/bin/piper"),
            "piper/piper",
        ]
        
        for loc in locations:
            if os.path.exists(loc) and os.access(loc, os.X_OK):
                return loc
                
        return None
    
    async def unload(self) -> None:
        """Unload/cleanup resources."""
        self._loaded = False
        self._piper_path = None
        logger.info("[PiperHandler] Handler unloaded")
    
    async def synthesize(
        self,
        text: str,
        output_format: Optional[str] = None,
        speed: Optional[float] = None,
    ) -> Dict[str, Any]:
        """
        Synthesize speech from text.
        
        Args:
            text: Text to synthesize
            output_format: wav, mp3, or ogg
            speed: Speaking speed multiplier
            
        Returns:
            {
                "audio_bytes": bytes,
                "format": "wav",
                "sample_rate": 22050,
                "duration": 2.5
            }
        """
        if not await self.load():
            raise RuntimeError("Failed to load Piper")
        
        output_format = output_format or self.config.output_format
        length_scale = 1.0 / (speed or 1.0)  # Invert for piper
        
        # Generate audio
        loop = asyncio.get_event_loop()
        
        if hasattr(self, "_use_python") and self._use_python:
            audio_bytes, duration = await loop.run_in_executor(
                None,
                self._synthesize_python,
                text,
                length_scale,
            )
        else:
            audio_bytes, duration = await loop.run_in_executor(
                None,
                self._synthesize_cli,
                text,
                length_scale,
            )
        
        # Convert format if needed
        if output_format != "wav":
            audio_bytes = await self._convert_audio(
                audio_bytes,
                "wav",
                output_format,
            )
        
        return {
            "audio_bytes": audio_bytes,
            "format": output_format,
            "sample_rate": self.config.sample_rate,
            "duration": duration,
        }
    
    def _synthesize_python(
        self,
        text: str,
        length_scale: float,
    ) -> tuple:
        """Synthesize using Python package."""
        from piper import PiperVoice
        import wave
        import io
        
        # Load voice
        voice = PiperVoice.load(self._model_path)
        
        # Generate audio
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as wav_file:
            voice.synthesize(
                text,
                wav_file,
                length_scale=length_scale,
                noise_scale=self.config.noise_scale,
                noise_w=self.config.noise_w,
                sentence_silence=self.config.sentence_silence,
            )
        
        audio_bytes = buffer.getvalue()
        
        # Calculate duration
        duration = len(audio_bytes) / (self.config.sample_rate * 2)  # 16-bit
        
        return audio_bytes, duration
    
    def _synthesize_cli(
        self,
        text: str,
        length_scale: float,
    ) -> tuple:
        """Synthesize using CLI."""
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            output_path = f.name
        
        try:
            cmd = [
                self._piper_path,
                "--model", self._model_path,
                "--output_file", output_path,
                "--length_scale", str(length_scale),
                "--noise_scale", str(self.config.noise_scale),
                "--noise_w", str(self.config.noise_w),
                "--sentence_silence", str(self.config.sentence_silence),
            ]
            
            if self.config.speaker_id is not None:
                cmd.extend(["--speaker", str(self.config.speaker_id)])
            
            # Run piper
            process = subprocess.run(
                cmd,
                input=text.encode("utf-8"),
                capture_output=True,
                check=True,
            )
            
            # Read output
            with open(output_path, "rb") as f:
                audio_bytes = f.read()
            
            # Calculate duration
            duration = len(audio_bytes) / (self.config.sample_rate * 2)
            
            return audio_bytes, duration
            
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)
    
    async def _convert_audio(
        self,
        audio_bytes: bytes,
        from_format: str,
        to_format: str,
    ) -> bytes:
        """Convert audio format using ffmpeg."""
        with tempfile.NamedTemporaryFile(suffix=f".{from_format}", delete=False) as f:
            f.write(audio_bytes)
            input_path = f.name
        
        output_path = input_path.replace(f".{from_format}", f".{to_format}")
        
        try:
            cmd = ["ffmpeg", "-y", "-i", input_path, output_path]
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await process.wait()
            
            if os.path.exists(output_path):
                with open(output_path, "rb") as f:
                    return f.read()
            return audio_bytes
            
        finally:
            for path in [input_path, output_path]:
                if os.path.exists(path):
                    try:
                        os.remove(path)
                    except:
                        pass
    
    async def invoke(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Unified invoke interface for ModelGateway.
        
        Args:
            params: {
                "text": "text to synthesize",
                "format": "wav" | "mp3" | "ogg",
                "speed": 1.0
            }
            
        Returns:
            Synthesis result
        """
        text = params.get("text")
        if not text:
            raise ValueError("Missing 'text' parameter")
            
        return await self.synthesize(
            text=text,
            output_format=params.get("format"),
            speed=params.get("speed"),
        )


# Singleton instance
_handler: Optional[PiperHandler] = None


def get_piper_handler(config: Optional[PiperConfig] = None) -> PiperHandler:
    """Get or create Piper handler singleton."""
    global _handler
    if _handler is None:
        _handler = PiperHandler(config)
    return _handler
