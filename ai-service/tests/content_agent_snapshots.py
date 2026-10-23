"""Stage approved ETL snapshots shaped like the real adapters' output."""

from __future__ import annotations

import hashlib
import json
from typing import Any

from api.services.content_etl.contracts import SourceManifest
from api.services.content_etl.pipeline import ETLPipeline
from api.services.content_etl.storage import SnapshotStorage

_SOURCES: dict[str, dict[str, str]] = {
    "cefr_j": {
        "license_id": "LicenseRef-CEFR-J-Commercial",
        "license_url": "https://github.com/openlanguageprofiles/olp-en-cefrj",
        "attribution_text": "The CEFR-J Wordlist Version 1.5",
        "official_url": "https://github.com/openlanguageprofiles/olp-en-cefrj",
    },
    "oewn": {
        "license_id": "CC-BY-4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "attribution_text": "Open English WordNet 2025",
        "official_url": "https://en-word.net/static/english-wordnet-2025.xml.gz",
    },
    "cmudict": {
        "license_id": "LicenseRef-CMUdict",
        "license_url": "https://github.com/cmusphinx/cmudict/blob/master/LICENSE",
        "attribution_text": "Carnegie Mellon Pronouncing Dictionary",
        "official_url": "https://github.com/cmusphinx/cmudict",
    },
}


def stage_snapshot(
    storage: SnapshotStorage,
    source: str,
    records: list[dict[str, Any]],
    *,
    version: str = "2025",
) -> SourceManifest:
    meta = _SOURCES[source]
    raw = json.dumps(records, sort_keys=True).encode("utf-8")
    temp = storage.create_temp_file()
    temp.write_bytes(raw)
    storage.promote_raw(
        temp,
        source_name=source,
        version=version,
        filename=f"{source}-{version}.json",
        sha256=hashlib.sha256(raw).hexdigest(),
    )
    report = ETLPipeline(storage=storage).run(
        source_name=source,
        source_version=version,
        adapter_name=source,
        adapter_version=1,
        license_id=meta["license_id"],
        license_url=meta["license_url"],
        attribution_text=meta["attribution_text"],
        raw_records=records,
        raw_bytes=raw,
        official_url=meta["official_url"],
    )
    assert report.status == "approved", report.errors
    return storage.read_active_manifest(source)


def cefr_j_records(words: list[str], level: str = "A1") -> list[dict[str, Any]]:
    """CEFR-J gives a word and a level, nothing else; pos is always `phrase`."""
    return [
        {
            "record_id": f"cefr_j:{word}",
            "word": word,
            "part_of_speech": "phrase",
            "declared_cefr": level,
        }
        for word in words
    ]


def oewn_senses(
    word: str,
    pos: str,
    senses: list[tuple[str, str | None]],
    *,
    ranked: bool = True,
) -> list[dict[str, Any]]:
    """One record per (definition, example) sense, most common first; no CEFR level.

    `ranked=False` is what a snapshot from before OEWN adapter v2 looks like.
    """
    return [
        {
            "record_id": f"oewn:{word}:{pos}:{index}",
            "word": word,
            "part_of_speech": pos,
            "definition": definition,
            "example": example,
            **({"metadata": {"sense_rank": index + 1}} if ranked else {}),
        }
        for index, (definition, example) in enumerate(senses)
    ]


def cmudict_records(entries: dict[str, str]) -> list[dict[str, Any]]:
    """CMUdict gives word and stress-marked ARPAbet; pos is always `phrase`."""
    return [
        {
            "record_id": f"cmudict:{word}",
            "word": word,
            "part_of_speech": "phrase",
            "pronunciation": arpabet,
        }
        for word, arpabet in entries.items()
    ]
