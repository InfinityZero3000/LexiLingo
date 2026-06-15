"""LibriSpeech adapter — Mini LibriSpeech for dev/fixtures; full corpus disabled by default.

Full LibriSpeech download is disabled. Only the mini fixture subset can be
parsed in dev/test mode (enabled=False in the registry).
"""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any


ADAPTER_VERSION = 1
SOURCE_NAME = "librispeech"
LICENSE_ID = "CC-BY-4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
ATTRIBUTION_TEXT = "LibriSpeech ASR corpus"
OFFICIAL_URL = "https://www.openslr.org/12"

# Full corpus is disabled by default; only fixture/mini data allowed.
FULL_CORPUS_ENABLED = False


def _sha256_str(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse(raw_path: Path, *, allow_full: bool = False) -> list[dict[str, Any]]:
    """Parse a LibriSpeech text transcript file (chapter.txt format).

    Each line: ``<utterance_id> <transcription>``.
    Full corpus is disabled unless ``allow_full=True`` (for testing only).
    """
    if not allow_full and not FULL_CORPUS_ENABLED:
        file_size = raw_path.stat().st_size
        if file_size > 1024 * 1024:  # > 1 MB implies real dataset
            raise ValueError(
                "Full LibriSpeech corpus is disabled. "
                "Use a mini fixture file for dev/test."
            )

    records: list[dict[str, Any]] = []
    for raw_line in raw_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        parts = line.split(maxsplit=1)
        if len(parts) < 2:
            continue

        utterance_id = parts[0].strip()
        transcription = parts[1].strip()
        if not utterance_id or not transcription:
            continue

        record_id = f"{SOURCE_NAME}:{utterance_id}"
        records.append(
            {
                "record_id": record_id,
                "source_name": SOURCE_NAME,
                "example": transcription,
                "language": "en",
                "source_url": OFFICIAL_URL,
                "lineage": {
                    "adapter": SOURCE_NAME,
                    "adapter_version": ADAPTER_VERSION,
                    "raw_path": raw_path.name,
                    "source_location": utterance_id,
                },
                "attribution_text": ATTRIBUTION_TEXT,
                "license_id": LICENSE_ID,
                "license_url": LICENSE_URL,
            }
        )

    return records


class LibriSpeechAdapter:
    source_name: str = SOURCE_NAME
    adapter_version: int = ADAPTER_VERSION

    def parse(self, raw_path: Path) -> list[dict[str, Any]]:
        return parse(raw_path)
