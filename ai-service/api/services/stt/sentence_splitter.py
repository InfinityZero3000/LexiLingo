"""Small speakable fragments for low-latency TTS."""

from __future__ import annotations

import re
from collections.abc import Iterator


def split_speakable_fragments(text: str, max_chars: int = 24) -> Iterator[str]:
    if max_chars < 8:
        raise ValueError("max_chars must be at least 8")

    remaining = re.sub(r"\s+", " ", text).strip()
    while remaining:
        if len(remaining) <= max_chars:
            yield remaining
            return

        window = remaining[:max_chars]
        cut = max_chars if remaining[max_chars].isspace() else max(
            window.rfind(mark) + 1 for mark in ".?!,;:"
        )
        if cut < 8:
            cut = window.rfind(" ", 8)
        if cut < 8:
            cut = max_chars

        yield remaining[:cut].strip()
        remaining = remaining[cut:].strip()
