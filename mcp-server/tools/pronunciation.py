"""
Pronunciation Analysis Tool

Uses a two-step approach:
1. Transcribe audio via Whisper (ai-service proxy)
2. Compare transcription with reference text via Gemini
"""

import base64
import io
import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze pronunciation accuracy.

    Args:
        audio_bytes: Base64 encoded audio
        reference_text: Expected text to pronounce
        return_phonemes: Include phoneme-level analysis

    Returns:
        accuracy_score: Overall score (0.0-1.0)
        word_scores: Per-word analysis
        overall_feedback: Summary feedback
        transcription: What was actually said
    """
    audio_b64 = args.get("audio_bytes", "")
    reference_text = args.get("reference_text", "")
    return_phonemes = args.get("return_phonemes", True)

    if not audio_b64:
        return {"error": "audio_bytes is required"}
    if not reference_text:
        return {"error": "reference_text is required"}

    logger.info(
        f"Pronunciation analysis: ref_text='{reference_text[:50]}', "
        f"phonemes={return_phonemes}"
    )

    try:
        # Step 1: Transcribe the audio
        transcription = await _transcribe_audio(audio_b64)

        if "error" in transcription:
            return {
                "error": f"Transcription failed: {transcription['error']}",
                "reference_text": reference_text,
            }

        transcribed_text = transcription.get("text", "")

        # Step 2: Compare with reference using Gemini
        from handlers.gemini import GeminiHandler

        gemini = GeminiHandler()
        analysis = await gemini.analyze_pronunciation(reference_text, transcribed_text)

        return {
            "reference_text": reference_text,
            "transcription": transcribed_text,
            "analysis": analysis,
            "method": "whisper+gemini",
        }

    except Exception as e:
        logger.error(f"Pronunciation analysis error: {e}", exc_info=True)
        return {
            "error": str(e),
            "reference_text": reference_text,
        }


async def _transcribe_audio(audio_b64: str) -> Dict[str, Any]:
    """Transcribe base64 audio using the STT tool chain"""
    try:
        audio_bytes = base64.b64decode(audio_b64)

        try:
            import numpy as np
            import soundfile as sf
            audio, sr = sf.read(io.BytesIO(audio_bytes))
        except ImportError:
            audio = audio_bytes

        from handlers.whisper import WhisperHandler

        whisper = WhisperHandler()
        await whisper.load()
        return await whisper.transcribe(audio=audio, language="en")
    except Exception as e:
        logger.error(f"Transcription step failed: {e}")
        return {"error": str(e)}
