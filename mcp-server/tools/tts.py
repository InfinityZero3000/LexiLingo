"""
TTS Tool - Text-to-Speech using Piper
"""

import logging
import base64
from typing import Any, Dict

logger = logging.getLogger(__name__)

_piper_handler = None


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute TTS (Text-to-Speech)
    
    Args:
        text: Text to convert to speech
        voice_id: Voice identifier
        speed: Speech speed (0.5 to 2.0)
    
    Returns:
        audio_bytes: Base64 encoded audio
        duration: Audio duration in seconds
        voice_id: Voice used
    """
    global _piper_handler
    
    text = args.get("text", "")
    voice_id = args.get("voice_id", "en_US-lessac-medium")
    speed = args.get("speed", 1.0)
    
    if not text:
        return {"error": "text is required"}
    
    logger.info(f"TTS request: text_len={len(text)}, voice={voice_id}, speed={speed}")
    
    try:
        # Load Piper handler
        if _piper_handler is None:
            logger.info("Loading Piper handler...")
            from handlers.piper import PiperHandler
            _piper_handler = PiperHandler()
            await _piper_handler.load()
        
        # Generate speech
        result = await _piper_handler.synthesize(
            text=text,
            voice_id=voice_id,
            speed=speed,
        )
        
        # Encode audio to base64
        audio_b64 = base64.b64encode(result["audio_bytes"]).decode("utf-8")
        
        return {
            "audio_bytes": audio_b64,
            "duration": result.get("duration", 0.0),
            "voice_id": voice_id,
            "sample_rate": result.get("sample_rate", 22050),
        }
    
    except Exception as e:
        logger.error(f"TTS execution error: {e}", exc_info=True)
        return {
            "error": str(e),
            "voice_id": voice_id,
        }


async def cleanup():
    """Cleanup resources"""
    global _piper_handler
    
    if _piper_handler:
        await _piper_handler.unload()
        _piper_handler = None
    
    logger.info("TTS tool cleaned up")
