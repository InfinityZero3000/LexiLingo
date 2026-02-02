"""
STT Tool - Speech-to-Text using Whisper
"""

import logging
import base64
import io
from typing import Any, Dict
import numpy as np
import soundfile as sf

logger = logging.getLogger(__name__)

_whisper_handler = None


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute STT (Speech-to-Text)
    
    Args:
        audio_bytes: Base64 encoded audio
        language: Language code (en, vi, etc.)
        return_timestamps: Include word-level timestamps
    
    Returns:
        text: Transcribed text
        segments: Word-level segments with timestamps
        language: Detected language
        confidence: Average confidence score
    """
    global _whisper_handler
    
    audio_b64 = args.get("audio_bytes", "")
    language = args.get("language", "en")
    return_timestamps = args.get("return_timestamps", True)
    
    if not audio_b64:
        return {"error": "audio_bytes is required"}
    
    logger.info(f"STT request: language={language}, timestamps={return_timestamps}")
    
    try:
        # Decode audio
        audio_bytes = base64.b64decode(audio_b64)
        audio, sr = sf.read(io.BytesIO(audio_bytes))
        
        # Load Whisper handler
        if _whisper_handler is None:
            logger.info("Loading Whisper handler...")
            from handlers.whisper import WhisperHandler
            _whisper_handler = WhisperHandler()
            await _whisper_handler.load()
        
        # Transcribe
        result = await _whisper_handler.transcribe(
            audio=audio,
            language=language,
            word_timestamps=return_timestamps,
        )
        
        return {
            "text": result.get("text", ""),
            "segments": result.get("segments", []) if return_timestamps else [],
            "language": result.get("language", language),
            "confidence": result.get("confidence", 0.0),
        }
    
    except Exception as e:
        logger.error(f"STT execution error: {e}", exc_info=True)
        return {
            "error": str(e),
            "language": language,
        }


async def cleanup():
    """Cleanup resources"""
    global _whisper_handler
    
    if _whisper_handler:
        await _whisper_handler.unload()
        _whisper_handler = None
    
    logger.info("STT tool cleaned up")
