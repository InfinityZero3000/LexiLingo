"""OEWN XML adapter — parses Open English WordNet XML into ETL records."""

from __future__ import annotations

import gzip
import hashlib
import json
from pathlib import Path
from typing import Any
from urllib.parse import quote

import defusedxml.ElementTree as ET


_OEWN_NS = "https://globalwordnet.github.io/schemas/WN-LMF-1.3.dtd"

# Maps WordNet syntactic category codes to our PartOfSpeech values.
_POS_MAP: dict[str, str] = {
    "n": "noun",
    "v": "verb",
    "a": "adjective",
    "r": "adverb",
    "s": "adjective",  # adjective satellite
}

ADAPTER_VERSION = 1
SOURCE_NAME = "oewn"
LICENSE_ID = "CC-BY-4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
ATTRIBUTION_TEXT = "Open English WordNet 2025"
OFFICIAL_URL = "https://en-word.net/static/english-wordnet-2025.xml.gz"


def _sha256_str(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _tag(local: str) -> str:
    return f"{{{_OEWN_NS}}}{local}"


def _is_gzip(raw_path: Path) -> bool:
    with raw_path.open("rb") as handle:
        return handle.read(2) == b"\x1f\x8b"


def parse(raw_path: Path) -> list[dict[str, Any]]:
    """Parse OEWN XML file. Returns one record per lemma/POS/sense combination."""
    # The pinned artifact is english-wordnet-<version>.xml.gz; an .xml-only
    # fixture is what hid that this parsed nothing at all in production.
    if _is_gzip(raw_path):
        with gzip.open(raw_path, "rb") as handle:
            root = ET.fromstring(handle.read())
    else:
        root = ET.parse(str(raw_path)).getroot()

    # The published release declares WN-LMF only as a DOCTYPE, so its elements
    # carry no namespace; other exports do namespace them. Follow the document.
    tag = _tag if root.tag.startswith("{") else (lambda local: local)

    # Build synset definition index: synset_id → definition text
    synset_defs: dict[str, str] = {}
    for lexicon in root.iter(tag("Lexicon")):
        for synset in lexicon.iter(tag("Synset")):
            ss_id = synset.get("id", "")
            def_elem = synset.find(tag("Definition"))
            if def_elem is not None and def_elem.text:
                synset_defs[ss_id] = def_elem.text.strip()

    records: list[dict[str, Any]] = []

    for lexicon in root.iter(tag("Lexicon")):
        lang = lexicon.get("language", "en")
        for entry in lexicon.iter(tag("LexicalEntry")):
            entry_id = entry.get("id", "")
            lemma_elem = entry.find(tag("Lemma"))
            if lemma_elem is None:
                continue
            written_form = (lemma_elem.get("writtenForm") or "").strip()
            pos_code = (lemma_elem.get("partOfSpeech") or "").strip()
            if not written_form or not pos_code:
                continue

            pos = _POS_MAP.get(pos_code, "phrase")

            for sense in entry.iter(tag("Sense")):
                sense_id = sense.get("id", "")
                synset_id = sense.get("synset", "")
                definition = synset_defs.get(synset_id, "")

                # Example sentences from SenseExample elements.
                examples = [
                    ex.text.strip()
                    for ex in sense.iter(tag("SenseExample"))
                    if ex.text and ex.text.strip()
                ]

                identity = f"{SOURCE_NAME}:{written_form}:{pos}:{sense_id}"
                record_id = f"{SOURCE_NAME}:{_sha256_str(identity)[:24]}"

                record: dict[str, Any] = {
                    "record_id": record_id,
                    "source_name": SOURCE_NAME,
                    "word": written_form.lower(),
                    "part_of_speech": pos,
                    "definition": definition or None,
                    "example": examples[0] if examples else None,
                    # Multi-word lemmas ("'tween decks") must be escaped: the URL
                    # validator rewrites the space, the rewritten value no longer
                    # matches the record checksum, and the record is quarantined.
                    "source_url": (
                        f"https://en-word.net/lemma/{quote(written_form, safe='')}"
                    ),
                    "language": lang,
                    "lineage": {
                        "adapter": SOURCE_NAME,
                        "adapter_version": ADAPTER_VERSION,
                        "raw_path": str(raw_path.name),
                        "source_location": sense_id or entry_id,
                    },
                    "attribution_text": ATTRIBUTION_TEXT,
                    "license_id": LICENSE_ID,
                    "license_url": LICENSE_URL,
                }
                records.append(record)

    return records


class OEWNAdapter:
    source_name: str = SOURCE_NAME
    adapter_version: int = ADAPTER_VERSION

    def parse(self, raw_path: Path) -> list[dict[str, Any]]:
        return parse(raw_path)
