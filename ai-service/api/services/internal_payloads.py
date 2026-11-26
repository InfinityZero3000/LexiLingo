"""Remove marked internal JSON without leaking nested or truncated payloads."""

import json
import re

_MARKER = re.compile(r"\[JIT_SOFT_GRAPH\]", re.IGNORECASE)
_DECODER = json.JSONDecoder()


def strip_jit_graph_blocks(text: str | None) -> str:
    """Preserve prose around complete blocks; discard unsafe truncated tails.

    A malformed `{...}`/`[...]` block has no trustworthy end boundary. Keep only the
    prose before it rather than attempting to recover internal JSON fragments.
    A marker followed by anything else is just dropped.
    raw_decode handles nested arrays, strings containing braces and escapes.
    """
    remaining = str(text or "")
    parts: list[str] = []
    while match := _MARKER.search(remaining):
        parts.append(remaining[:match.start()])
        payload = remaining[match.end():].lstrip()
        if not payload.startswith(("{", "[")):
            remaining = payload
            continue
        try:
            value, end = _DECODER.raw_decode(payload)
        except ValueError:
            return "".join(parts).strip()
        if not isinstance(value, dict):
            return "".join(parts).strip()
        remaining = payload[end:]
    parts.append(remaining)
    return "".join(parts).strip()
