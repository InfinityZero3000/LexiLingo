"""Tatoeba adapter — parses sentence TSV with per-row license attribution.

Only CC0-1.0 and CC-BY-2.0-FR rows are accepted. Incompatible rows are
raised as ValueError so the pipeline can quarantine them.
"""

from __future__ import annotations

import csv
import hashlib
import io
from pathlib import Path
from typing import Any


ADAPTER_VERSION = 1
SOURCE_NAME = "tatoeba"
OFFICIAL_URL = "https://tatoeba.org/en/downloads"

# License values exactly as Tatoeba uses them in their export TSVs.
_ALLOWED_LICENSES: frozenset[str] = frozenset({"CC0 1.0", "CC-BY 2.0 FR"})

_LICENSE_MAP: dict[str, tuple[str, str]] = {
    "CC0 1.0": ("CC0-1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
    "CC-BY 2.0 FR": ("CC-BY-2.0-FR", "https://creativecommons.org/licenses/by/2.0/fr/"),
}


def _sha256_str(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse(raw_path: Path, *, language_filter: str = "eng") -> list[dict[str, Any]]:
    """Parse Tatoeba sentences.csv export (id, lang, text, author, license, url).

    Rows with unsupported licenses raise ValueError for pipeline quarantine.
    """
    content = raw_path.read_text(encoding="utf-8")
    reader = csv.reader(io.StringIO(content), delimiter="\t")

    records: list[dict[str, Any]] = []
    for row_num, row in enumerate(reader, start=1):
        if not row or row[0].startswith("#"):
            continue
        if len(row) < 3:
            raise ValueError(f"Row {row_num}: expected at least 3 columns, got {len(row)}")

        sentence_id = row[0].strip()
        lang = row[1].strip()
        text = row[2].strip()
        author = row[3].strip() if len(row) > 3 else ""
        license_raw = row[4].strip() if len(row) > 4 else ""
        sentence_url = row[5].strip() if len(row) > 5 else ""

        if lang != language_filter:
            continue
        if not text:
            continue

        if license_raw not in _ALLOWED_LICENSES:
            raise ValueError(
                f"Row {row_num}: license {license_raw!r} is not approved "
                f"(allowed: {sorted(_ALLOWED_LICENSES)})"
            )

        license_id, license_url = _LICENSE_MAP[license_raw]
        attribution_text = (
            f"Tatoeba sentence #{sentence_id}"
            + (f" by {author}" if author else "")
            + f" ({license_raw})"
        )

        record_id = f"{SOURCE_NAME}:{sentence_id}"
        records.append(
            {
                "record_id": record_id,
                "source_name": SOURCE_NAME,
                "example": text,
                "language": lang,
                "source_url": sentence_url or f"https://tatoeba.org/en/sentences/show/{sentence_id}",
                "lineage": {
                    "adapter": SOURCE_NAME,
                    "adapter_version": ADAPTER_VERSION,
                    "raw_path": raw_path.name,
                    "source_location": f"sentence:{sentence_id}",
                },
                "attribution_text": attribution_text,
                "license_id": license_id,
                "license_url": license_url,
            }
        )

    return records


class TatoebaAdapter:
    source_name: str = SOURCE_NAME
    adapter_version: int = ADAPTER_VERSION

    def parse(self, raw_path: Path) -> list[dict[str, Any]]:
        return parse(raw_path)
