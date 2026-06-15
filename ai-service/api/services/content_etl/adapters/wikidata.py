"""Wikidata adapter — fetches configured QIDs and extracts English labels as topic records."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


ADAPTER_VERSION = 1
SOURCE_NAME = "wikidata"
LICENSE_ID = "CC0-1.0"
LICENSE_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
ATTRIBUTION_TEXT = "Wikidata contributors"
OFFICIAL_URL = "https://www.wikidata.org/wiki/Special:EntityData"


def _sha256_str(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse(raw_path: Path) -> list[dict[str, Any]]:
    """Parse a Wikidata entity JSON file (single entity or entity-list).

    Expected format: the JSON returned by
    ``https://www.wikidata.org/wiki/Special:EntityData/{QID}.json``
    """
    payload = json.loads(raw_path.read_text(encoding="utf-8"))

    entities: dict[str, Any]
    if "entities" in payload:
        entities = payload["entities"]
    elif "id" in payload:
        # Single entity dict.
        entities = {payload["id"]: payload}
    else:
        raise ValueError(f"Unexpected Wikidata JSON shape in {raw_path.name}")

    records: list[dict[str, Any]] = []

    for qid, entity in entities.items():
        labels = entity.get("labels", {})
        en_label_entry = labels.get("en", {})
        en_label = (en_label_entry.get("value") or "").strip()
        if not en_label:
            continue

        record_id = f"{SOURCE_NAME}:{qid}"
        records.append(
            {
                "record_id": record_id,
                "source_name": SOURCE_NAME,
                "word": en_label.lower(),
                "topic_ids": [qid],
                "source_url": f"https://www.wikidata.org/wiki/{qid}",
                "language": "en",
                "lineage": {
                    "adapter": SOURCE_NAME,
                    "adapter_version": ADAPTER_VERSION,
                    "raw_path": raw_path.name,
                    "source_location": qid,
                },
                "attribution_text": ATTRIBUTION_TEXT,
                "license_id": LICENSE_ID,
                "license_url": LICENSE_URL,
            }
        )

    return records


class WikidataAdapter:
    source_name: str = SOURCE_NAME
    adapter_version: int = ADAPTER_VERSION

    def parse(self, raw_path: Path) -> list[dict[str, Any]]:
        return parse(raw_path)
