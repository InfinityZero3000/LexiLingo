"""Pure helpers for the Lexi chat pipeline (TTS, STT, response sanitization)."""

import asyncio
import base64
import io
import logging
import re
from typing import List, Optional

logger = logging.getLogger(__name__)


def _normalize_markdown_for_lexi(text: str) -> str:
    """Normalize malformed markdown emphasis markers produced by model output."""
    if "**" not in text:
        return text

    out: List[str] = []
    in_bold = False
    open_idx: Optional[int] = None
    i = 0
    n = len(text)

    while i < n:
        is_double_star = text[i:i + 2] == "**"
        is_exact_pair = (
            is_double_star
            and (i == 0 or text[i - 1] != "*")
            and (i + 2 >= n or text[i + 2] != "*")
        )

        if not is_exact_pair:
            out.append(text[i])
            i += 1
            continue

        prev_ch = text[i - 1] if i > 0 else ""
        next_ch = text[i + 2] if i + 2 < n else ""
        can_open = bool(next_ch) and not next_ch.isspace()
        can_close = bool(prev_ch) and not prev_ch.isspace()

        if not in_bold:
            if can_open:
                open_idx = len(out)
                out.append("**")
                in_bold = True
        else:
            if can_close:
                out.append("**")
                in_bold = False
                open_idx = None

        i += 2

    if in_bold and open_idx is not None:
        out.pop(open_idx)

    return "".join(out)


def sanitize_lexi_response(text: str) -> str:
    """Remove internal TraceCAG debug payloads from user-facing Lexi output."""
    cleaned = str(text or "").strip()
    if not cleaned:
        return "Squawk! I lost my words for a second. Could you ask that again?"

    cleaned = re.sub(r"<think\b[^>]*>[\s\S]*?</think>", "", cleaned, flags=re.IGNORECASE)

    cleaned = re.sub(
        r"\[JIT_SOFT_GRAPH\]\s*(?:\n|\r\n?)?\s*\{[\s\S]*?\}\s*",
        "",
        cleaned,
        flags=re.IGNORECASE,
    )

    cleaned = re.sub(
        r"^\s*\{(?:\\?\"v\\?\"|\"v\")[\s\S]*?(?:\\?\"e\\?\"|\"e\")[\s\S]*?\}\s*$",
        "",
        cleaned,
        flags=re.IGNORECASE | re.MULTILINE,
    )

    cleaned = cleaned.replace("\\*", "*")
    cleaned = cleaned.replace("\\_", "_")

    cleaned = _normalize_markdown_for_lexi(cleaned)

    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()

    if not cleaned:
        return "Squawk! I lost my words for a second. Could you ask that again?"

    return cleaned


def _generate_gtts_b64(clean_text: str) -> str:
    from gtts import gTTS

    tts = gTTS(text=clean_text, lang='en', slow=False)
    buf = io.BytesIO()
    tts.write_to_fp(buf)
    buf.seek(0)
    return base64.b64encode(buf.read()).decode('utf-8')


async def synthesize_tts(text: str) -> Optional[str]:
    """Generate TTS audio and return base64-encoded MP3."""
    try:
        clean = re.sub(r'[*_~`#]', '', text)
        clean = re.sub(r'[\U00010000-\U0010ffff]', '', clean, flags=re.UNICODE)
        clean = clean.strip()
        if not clean:
            return None

        audio_b64 = await asyncio.to_thread(_generate_gtts_b64, clean)
        logger.info(f" Lexi TTS: {len(audio_b64)} bytes base64")
        return audio_b64
    except Exception as e:
        logger.warning(f"TTS failed: {e}")
        return None


async def transcribe_audio(audio_base64: str) -> Optional[str]:
    """Compatibility path for short clips while clients migrate to WebSocket STT."""
    try:
        from api.services.handlers.whisper_handler import get_whisper_handler

        audio_bytes = base64.b64decode(audio_base64, validate=True)
        result = await get_whisper_handler().transcribe(audio=audio_bytes, language="en")
        text = result.get("text", "")
        logger.info(f" Lexi STT: '{text[:50]}...'")
        return text if text else None
    except Exception as e:
        logger.warning(f"STT failed: {e}")
        return None
