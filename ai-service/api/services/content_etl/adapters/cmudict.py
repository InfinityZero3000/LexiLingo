"""CMUdict adapter — parses ARPAbet pronunciation entries."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any


ADAPTER_VERSION = 1
SOURCE_NAME = "cmudict"
LICENSE_ID = "LicenseRef-CMUdict"
LICENSE_URL = "https://github.com/cmusphinx/cmudict/blob/master/LICENSE"
ATTRIBUTION_TEXT = "Carnegie Mellon Pronouncing Dictionary"
OFFICIAL_URL = "https://github.com/cmusphinx/cmudict"

# CMUdict lines starting with ";;;" are comments.
_COMMENT_RE = re.compile(r"^;;;")
# Variant entries have a numeric suffix, e.g. "TOMATO(2)"
_VARIANT_RE = re.compile(r"^([A-Z'.-]+)\((\d+)\)\s+(.+)$")
_ENTRY_RE = re.compile(r"^([A-Z'.-]+)\s+(.+)$")
# Stress markers are digits 0–2 on vowel phonemes.
_STRESS_RE = re.compile(r"[012]$")


def _sha256_str(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _normalize_arpabet(phonemes: str) -> str:
    """Strip stress digits and normalise to uppercase space-separated phonemes."""
    tokens = phonemes.strip().upper().split()
    return " ".join(_STRESS_RE.sub("", t) for t in tokens)


def parse(raw_path: Path) -> list[dict[str, Any]]:
    """Parse CMUdict text file. Numbered variants share the same identity as the base word."""
    records: list[dict[str, Any]] = []
    seen_words: set[str] = set()

    for raw_line in raw_path.read_text(encoding="latin-1").splitlines():
        line = raw_line.strip()
        if not line or _COMMENT_RE.match(line):
            continue

        variant_match = _VARIANT_RE.match(line)
        if variant_match:
            word_raw, _variant_num, phonemes_raw = variant_match.groups()
        else:
            entry_match = _ENTRY_RE.match(line)
            if not entry_match:
                continue
            word_raw, phonemes_raw = entry_match.groups()

        word = word_raw.lower()
        arpabet = _normalize_arpabet(phonemes_raw)

        # Variants collapse into the same record identity as the primary.
        if word in seen_words:
            # Additional pronunciations are not a separate record; skip.
            continue
        seen_words.add(word)

        record_id = f"{SOURCE_NAME}:{_sha256_str(word)[:24]}"
        records.append(
            {
                "record_id": record_id,
                "source_name": SOURCE_NAME,
                "word": word,
                "part_of_speech": "phrase",
                "pronunciation": arpabet,
                "source_url": OFFICIAL_URL,
                "language": "en",
                "lineage": {
                    "adapter": SOURCE_NAME,
                    "adapter_version": ADAPTER_VERSION,
                    "raw_path": raw_path.name,
                    "source_location": word_raw,
                },
                "attribution_text": ATTRIBUTION_TEXT,
                "license_id": LICENSE_ID,
                "license_url": LICENSE_URL,
            }
        )

    return records


class CMUDictAdapter:
    source_name: str = SOURCE_NAME
    adapter_version: int = ADAPTER_VERSION

    def parse(self, raw_path: Path) -> list[dict[str, Any]]:
        return parse(raw_path)
