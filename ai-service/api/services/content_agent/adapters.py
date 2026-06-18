"""Pure source normalization adapters for approved content-agent inputs."""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from typing import Any, Mapping, Sequence

from api.models.content_agent import (
    CEFRLevel,
    NormalizedSourceRecord,
    PartOfSpeech,
)
from api.services.content_etl.contracts import SourceRecordV2
from api.services.content_agent.policies import apply_source_policy


_APOSTROPHES = str.maketrans({"’": "'", "‘": "'", "`": "'", "´": "'"})
_HYPHENS = str.maketrans({"‐": "-", "‑": "-", "‒": "-", "–": "-", "—": "-"})
_POS_ALIASES = {
    "n": PartOfSpeech.NOUN.value,
    "noun": PartOfSpeech.NOUN.value,
    "v": PartOfSpeech.VERB.value,
    "verb": PartOfSpeech.VERB.value,
    "adj": PartOfSpeech.ADJECTIVE.value,
    "adjective": PartOfSpeech.ADJECTIVE.value,
    "adv": PartOfSpeech.ADVERB.value,
    "adverb": PartOfSpeech.ADVERB.value,
    "pronoun": PartOfSpeech.PRONOUN.value,
    "preposition": PartOfSpeech.PREPOSITION.value,
    "conjunction": PartOfSpeech.CONJUNCTION.value,
    "interjection": PartOfSpeech.INTERJECTION.value,
    "phrase": PartOfSpeech.PHRASE.value,
}


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)


def _checksum(value: Any) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def _normalize_word(value: Any) -> str | None:
    if value is None:
        return None
    normalized = unicodedata.normalize("NFKC", str(value))
    normalized = normalized.translate(_APOSTROPHES).translate(_HYPHENS)
    normalized = " ".join(normalized.strip().split()).casefold()
    if not normalized:
        return None
    if not any(character.isalnum() for character in normalized):
        raise ValueError("word must contain a letter or number")
    return normalized


def _normalize_topic(value: Any) -> str:
    normalized = unicodedata.normalize("NFKC", str(value or "general"))
    normalized = re.sub(r"[^\w]+", "_", normalized.casefold()).strip("_")
    return normalized[:100] or "general"


def _normalize_pos(value: Any) -> str:
    return _POS_ALIASES.get(str(value or "phrase").strip().lower(), "phrase")


def _normalize_cefr(value: Any) -> str | None:
    if value is None or str(value).strip() == "":
        return None
    return CEFRLevel(str(value).strip().upper()).value


def _default_confidence(source_name: str) -> float:
    if source_name in {"existing_cefr", "cefr_j"}:
        return 1.0
    if source_name == "admin_upload":
        return 0.95
    if source_name == "oewn":
        return 0.9
    return 0.85


def _prepare_record(
    source_name: str,
    raw_record: Mapping[str, Any],
) -> dict[str, Any]:
    prepared = dict(raw_record)
    prepared["word"] = _normalize_word(prepared.get("word"))
    prepared["part_of_speech"] = _normalize_pos(
        prepared.get("part_of_speech")
        or prepared.get("pos")
    )
    prepared["declared_cefr"] = _normalize_cefr(
        prepared.get("declared_cefr")
        or prepared.get("cefr_level")
        or prepared.get("level")
    )
    prepared["declared_topic"] = _normalize_topic(
        prepared.get("declared_topic")
        or prepared.get("topic")
    )
    confidence = prepared.get("classification_confidence")
    if confidence is None:
        confidence = prepared.get("confidence")
    if confidence is None:
        confidence = _default_confidence(source_name)
    prepared["classification_confidence"] = float(confidence)
    prepared["checksum"] = prepared.get("checksum") or _checksum(raw_record)
    if not prepared.get("record_id"):
        identity = {
            "source_name": source_name,
            "source_url": prepared.get("source_url"),
            "word": prepared.get("word"),
            "title": prepared.get("title"),
            "declared_cefr": prepared.get("declared_cefr"),
            "checksum": prepared["checksum"],
        }
        prepared["record_id"] = f"{source_name}:{_checksum(identity)[:24]}"
    return prepared


def normalize_source_records(
    records: Sequence[Mapping[str, Any]],
    *,
    source_name: str | None = None,
) -> list[NormalizedSourceRecord]:
    """Normalize records and apply the registry policy before returning them."""

    normalized: list[NormalizedSourceRecord] = []
    for raw_record in records:
        record_source = (
            source_name
            or str(raw_record.get("source_name") or "").strip().lower()
        )
        if not record_source:
            raise ValueError("source_name is required for every source record")
        prepared = _prepare_record(record_source, raw_record)
        normalized.append(apply_source_policy(record_source, prepared))
    return normalized


def _load_cached_existing_cefr_mapping() -> dict[str, str]:
    """Fail closed until the licensed ETL activates a CEFR-J snapshot."""

    return {}


def normalize_existing_cefr_records(
    mapping: Mapping[str, str] | None = None,
) -> list[NormalizedSourceRecord]:
    """Convert the existing CEFR mapping into attributed label records."""

    source_mapping = dict(mapping) if mapping is not None else _load_cached_existing_cefr_mapping()
    raw_records = [
        {
            "word": word,
            "declared_cefr": level,
            "part_of_speech": "phrase",
            "declared_topic": "general",
            "source_url": "dataset:approved-cefr-j-snapshot",
            "metadata": {"resource_type": "cefr_label"},
            "classification_confidence": 1.0,
        }
        for word, level in source_mapping.items()
        if str(level).strip().upper() in CEFRLevel._value2member_map_
    ]
    records = normalize_source_records(raw_records, source_name="existing_cefr")
    return sorted(records, key=lambda record: (record.word or "", record.record_id))


def normalize_etl_records(
    records: Sequence[SourceRecordV2],
) -> list[NormalizedSourceRecord]:
    normalized: list[NormalizedSourceRecord] = []
    for record in records:
        payload = record.model_dump(mode="json")
        payload.update(
            {
                "checksum": record.record_checksum,
                "source_content_usage": record.content_usage.value,
                "declared_topic": (
                    record.topic_ids[0].casefold()
                    if record.topic_ids
                    else "general"
                ),
            }
        )
        normalized.extend(
            normalize_source_records(
                [payload],
                source_name=record.source_name.value,
            )
        )
    return normalized
