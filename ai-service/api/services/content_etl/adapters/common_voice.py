"""Common Voice adapter — operator-provided download, validates release metadata.

Common Voice requires accepting the dataset license on the Mozilla Data
Collective portal before downloading. This adapter validates that release
metadata is present before reading any sentences.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
from pathlib import Path
from typing import Any


ADAPTER_VERSION = 1
SOURCE_NAME = "common_voice"
LICENSE_ID = "CC0-1.0"
LICENSE_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
ATTRIBUTION_TEXT = "Mozilla Common Voice contributors"
OFFICIAL_URL = "https://datacollective.mozillafoundation.org/organization/cmfh0j9o10006ns07jq45h7xk"

_RELEASE_METADATA_FILENAME = "release_metadata.json"


def _sha256_str(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _validate_release_metadata(dataset_dir: Path) -> dict[str, Any]:
    """Require a release_metadata.json in the dataset directory before reading."""
    metadata_path = dataset_dir / _RELEASE_METADATA_FILENAME
    if not metadata_path.exists():
        raise ValueError(
            f"Common Voice release metadata not found at {metadata_path}. "
            "Download must include release_metadata.json from the Mozilla "
            "Data Collective portal."
        )
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if not metadata.get("release"):
        raise ValueError(
            "release_metadata.json is missing the 'release' field"
        )
    return metadata


def parse(raw_path: Path, *, validate_release: bool = True) -> list[dict[str, Any]]:
    """Parse a Common Voice validated.tsv (or train/test/dev TSV).

    Requires release_metadata.json to be present in the same directory
    unless ``validate_release=False`` (for fixture testing only).
    """
    if validate_release:
        _validate_release_metadata(raw_path.parent)

    content = raw_path.read_text(encoding="utf-8")
    reader = csv.DictReader(io.StringIO(content), delimiter="\t")

    records: list[dict[str, Any]] = []
    for row_num, row in enumerate(reader, start=2):
        client_id = (row.get("client_id") or "").strip()
        sentence = (row.get("sentence") or "").strip()
        path_val = (row.get("path") or "").strip()

        if not sentence:
            continue

        utterance_id = path_val or f"cv-{_sha256_str(client_id + sentence)[:16]}"
        record_id = f"{SOURCE_NAME}:{utterance_id}"

        records.append(
            {
                "record_id": record_id,
                "source_name": SOURCE_NAME,
                "example": sentence,
                "language": "en",
                "source_url": OFFICIAL_URL,
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


class CommonVoiceAdapter:
    source_name: str = SOURCE_NAME
    adapter_version: int = ADAPTER_VERSION

    def parse(self, raw_path: Path) -> list[dict[str, Any]]:
        return parse(raw_path)
