"""CEFR-J adapter — parses CEFR-J wordlist CSV into label-only records."""

from __future__ import annotations

import csv
import hashlib
import io
from pathlib import Path
from typing import Any


ADAPTER_VERSION = 1
SOURCE_NAME = "cefr_j"
LICENSE_ID = "LicenseRef-CEFR-J-Commercial"
LICENSE_URL = "https://github.com/openlanguageprofiles/olp-en-cefrj"
ATTRIBUTION_TEXT = (
    "The CEFR-J Wordlist Version 1.5, compiled by Yukio Tono, "
    "Tokyo University of Foreign Studies"
)
OFFICIAL_URL = "https://github.com/openlanguageprofiles/olp-en-cefrj"

# ShareAlike files from Octanove are excluded by license.
_FORBIDDEN_PATH_MARKERS = ("octanove",)

_VALID_CEFR_LABELS = frozenset({"A1", "A2", "B1", "B2", "C1", "C2", "A2+", "B1+", "B2+"})


def _sha256_str(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _reject_sharealike(raw_path: Path) -> None:
    lowered = str(raw_path).lower()
    for marker in _FORBIDDEN_PATH_MARKERS:
        if marker in lowered:
            raise ValueError(
                f"File {raw_path.name!r} is excluded by the source license policy "
                f"(ShareAlike restriction: {marker!r})"
            )


def _normalise_cefr(raw: str) -> str | None:
    normalised = raw.strip().upper()
    # Map A2+/B1+/B2+ to base level for storage.
    if normalised.endswith("+"):
        normalised = normalised[:-1]
    if normalised in _VALID_CEFR_LABELS - {"A2+", "B1+", "B2+"}:
        return normalised
    return None


def parse(raw_path: Path) -> list[dict[str, Any]]:
    """Parse a CEFR-J CSV file. Rejects ShareAlike files by path."""
    _reject_sharealike(raw_path)

    content = raw_path.read_text(encoding="utf-8-sig")
    reader = csv.DictReader(io.StringIO(content))

    records: list[dict[str, Any]] = []
    for row_num, row in enumerate(reader, start=2):
        word = (row.get("headword") or row.get("word") or "").strip().lower()
        cefr_raw = (row.get("CEFR") or row.get("cefr") or row.get("level") or "").strip()
        cefr = _normalise_cefr(cefr_raw)

        if not word:
            continue
        if cefr is None:
            raise ValueError(
                f"Row {row_num}: unrecognised CEFR label {cefr_raw!r} for word {word!r}"
            )

        record_id = f"{SOURCE_NAME}:{_sha256_str(word)[:24]}"
        records.append(
            {
                "record_id": record_id,
                "source_name": SOURCE_NAME,
                "word": word,
                "part_of_speech": "phrase",
                "declared_cefr": cefr,
                "source_url": OFFICIAL_URL,
                "language": "en",
                "lineage": {
                    "adapter": SOURCE_NAME,
                    "adapter_version": ADAPTER_VERSION,
                    "raw_path": raw_path.name,
                    "source_location": f"row:{row_num}",
                },
                "attribution_text": ATTRIBUTION_TEXT,
                "license_id": LICENSE_ID,
                "license_url": LICENSE_URL,
            }
        )

    return records


class CEFRJAdapter:
    source_name: str = SOURCE_NAME
    adapter_version: int = ADAPTER_VERSION

    def parse(self, raw_path: Path) -> list[dict[str, Any]]:
        return parse(raw_path)
