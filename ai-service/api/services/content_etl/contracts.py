"""Strict contracts for immutable licensed-content snapshots."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime
from enum import Enum
from typing import Any, Literal

from pydantic_core import to_jsonable_python
from pydantic import (
    AnyHttpUrl,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


SHA256_PATTERN = r"^[a-f0-9]{64}$"
_CONTROL_CHARACTER_PATTERN = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

# Allowed licenses per source — inlined to avoid circular imports with registry.
_SOURCE_ALLOWED_LICENSES: dict[str, frozenset[str]] = {
    "oewn": frozenset({"CC-BY-4.0"}),
    "cmudict": frozenset({"LicenseRef-CMUdict"}),
    "cefr_j": frozenset({"LicenseRef-CEFR-J-Commercial"}),
    "wikidata": frozenset({"CC0-1.0"}),
    "tatoeba": frozenset({"CC0-1.0", "CC-BY-2.0-FR"}),
    "librispeech": frozenset({"CC-BY-4.0"}),
    "common_voice": frozenset({"CC0-1.0"}),
    "admin_upload": frozenset({"LicenseRef-Admin-Owned"}),
}

# Allowed URL hosts per source.
_SOURCE_ALLOWED_HOSTS: dict[str, frozenset[str]] = {
    "oewn": frozenset({"en-word.net", "github.com"}),
    "cmudict": frozenset({"github.com", "raw.githubusercontent.com", "codeload.github.com"}),
    "cefr_j": frozenset({"github.com", "raw.githubusercontent.com", "codeload.github.com"}),
    "wikidata": frozenset({"www.wikidata.org"}),
    "tatoeba": frozenset({"tatoeba.org", "downloads.tatoeba.org"}),
    "librispeech": frozenset({"www.openslr.org", "openslr.org"}),
    "common_voice": frozenset({"datacollective.mozillafoundation.org"}),
    "admin_upload": frozenset(),
}


class SourceName(str, Enum):
    OEWN = "oewn"
    CMUDICT = "cmudict"
    CEFR_J = "cefr_j"
    WIKIDATA = "wikidata"
    TATOEBA = "tatoeba"
    LIBRISPEECH = "librispeech"
    COMMON_VOICE = "common_voice"
    ADMIN_UPLOAD = "admin_upload"


class AllowedLicenseId(str, Enum):
    CC0_1_0 = "CC0-1.0"
    CC_BY_2_0_FR = "CC-BY-2.0-FR"
    CC_BY_4_0 = "CC-BY-4.0"
    CMUDICT = "LicenseRef-CMUdict"
    CEFR_J_COMMERCIAL = "LicenseRef-CEFR-J-Commercial"
    ADMIN_OWNED = "LicenseRef-Admin-Owned"
    GENERATED = "LicenseRef-Generated"


class ContentUsage(str, Enum):
    LEXICAL = "lexical"
    PRONUNCIATION = "pronunciation"
    LABEL = "label"
    TOPIC = "topic"
    EXAMPLE = "example"
    AUDIO = "audio"


def canonical_json_bytes(payload: dict[str, Any]) -> bytes:
    """Canonical JSON used for immutable ETL integrity checks."""
    return json.dumps(
        to_jsonable_python(payload),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


_SOURCE_RECORD_CHECKSUM_DEFAULTS: dict[str, Any] = {
    "schema_version": 2,
    "word": None,
    "lemma": None,
    "part_of_speech": None,
    "definition": None,
    "translation_vi": None,
    "example": None,
    "pronunciation": None,
    "audio": None,
    "declared_cefr": None,
    "assigned_cefr": None,
    "classification_confidence": None,
    "topic_ids": [],
    "metadata": {},
}


def compute_source_record_checksum(payload: dict[str, Any]) -> str:
    checksum_payload = {**_SOURCE_RECORD_CHECKSUM_DEFAULTS, **payload}
    checksum_payload.pop("record_checksum", None)
    return hashlib.sha256(canonical_json_bytes(checksum_payload)).hexdigest()


def compute_record_checksum_root(checksums: list[str] | tuple[str, ...]) -> str:
    return hashlib.sha256("\n".join(sorted(checksums)).encode("utf-8")).hexdigest()


class SourceLineage(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    adapter: str = Field(min_length=1, max_length=100)
    adapter_version: int = Field(ge=1)
    raw_path: str = Field(min_length=1, max_length=1000)
    source_location: str | None = Field(default=None, max_length=1000)


class AudioReference(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    url: AnyHttpUrl
    mime_type: str = Field(min_length=1, max_length=100)
    duration_seconds: float | None = Field(default=None, ge=0)
    speaker_attribution: str | None = Field(default=None, max_length=1000)

    @field_validator("url")
    @classmethod
    def require_https(cls, value: AnyHttpUrl) -> AnyHttpUrl:
        if value.scheme != "https":
            raise ValueError("audio URL must use HTTPS")
        return value


class SourceRecordV2(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    schema_version: Literal[2] = 2
    record_id: str = Field(min_length=1, max_length=500)
    source_name: SourceName
    source_version: str = Field(min_length=1, max_length=64)
    source_record_id: str = Field(min_length=1, max_length=500)
    source_url: AnyHttpUrl
    license_id: AllowedLicenseId
    license_url: AnyHttpUrl
    attribution_text: str = Field(min_length=1, max_length=2000)
    content_usage: ContentUsage
    language: str = Field(pattern=r"^[a-z]{2,3}(-[A-Z]{2})?$")
    word: str | None = Field(default=None, max_length=255)
    lemma: str | None = Field(default=None, max_length=255)
    part_of_speech: Literal[
        "noun",
        "verb",
        "adjective",
        "adverb",
        "pronoun",
        "preposition",
        "conjunction",
        "interjection",
        "phrase",
    ] | None = None
    definition: str | None = Field(default=None, max_length=10000)
    translation_vi: str | None = Field(default=None, max_length=5000)
    example: str | None = Field(default=None, max_length=10000)
    pronunciation: str | None = Field(default=None, max_length=500)
    audio: AudioReference | None = None
    declared_cefr: Literal["A1", "A2", "B1", "B2", "C1", "C2"] | None = None
    assigned_cefr: Literal["A1", "A2", "B1", "B2", "C1", "C2"] | None = None
    classification_confidence: float | None = Field(default=None, ge=0, le=1)
    topic_ids: list[str] = Field(default_factory=list, max_length=100)
    retrieved_at: datetime
    raw_checksum: str = Field(pattern=SHA256_PATTERN)
    record_checksum: str = Field(pattern=SHA256_PATTERN)
    lineage: SourceLineage
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("source_url", "license_url")
    @classmethod
    def require_https(cls, value: AnyHttpUrl) -> AnyHttpUrl:
        if value.scheme != "https":
            raise ValueError("source record URLs must use HTTPS")
        return value

    @field_validator("retrieved_at")
    @classmethod
    def require_timezone_aware(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("retrieved_at must include timezone information")
        return value

    @field_validator(
        "record_id",
        "source_version",
        "source_record_id",
        "attribution_text",
        "language",
        "word",
        "lemma",
        "definition",
        "translation_vi",
        "example",
        "pronunciation",
        mode="after",
    )
    @classmethod
    def reject_control_characters(cls, value: str | None) -> str | None:
        if value is not None and _CONTROL_CHARACTER_PATTERN.search(value):
            raise ValueError("text fields must not contain control characters")
        return value

    @model_validator(mode="after")
    def validate_source_and_payload(self) -> "SourceRecordV2":
        allowed = _SOURCE_ALLOWED_LICENSES.get(self.source_name.value, frozenset())
        if self.license_id.value not in allowed:
            raise ValueError(
                f"license {self.license_id.value!r} is not approved for source "
                f"{self.source_name.value!r}"
            )
        if self.source_name.value != "admin_upload":
            allowed_hosts = _SOURCE_ALLOWED_HOSTS.get(
                self.source_name.value,
                frozenset(),
            )
            if self.source_url.host not in allowed_hosts:
                raise ValueError(
                    f"Host {self.source_url.host!r} is not approved for source "
                    f"{self.source_name.value!r}"
                )
        required_payloads = {
            ContentUsage.LEXICAL: ("definition", self.definition),
            ContentUsage.PRONUNCIATION: ("pronunciation", self.pronunciation),
            ContentUsage.LABEL: ("declared_cefr", self.declared_cefr),
            ContentUsage.TOPIC: ("topic_ids", self.topic_ids),
            ContentUsage.EXAMPLE: ("example", self.example),
            ContentUsage.AUDIO: ("audio", self.audio),
        }
        field_name, field_value = required_payloads[self.content_usage]
        if field_value is None or field_value == "" or field_value == []:
            raise ValueError(
                f"{field_name} is required for content_usage "
                f"{self.content_usage.value!r}"
            )
        expected_checksum = compute_source_record_checksum(
            self.model_dump(mode="json")
        )
        if self.record_checksum != expected_checksum:
            raise ValueError("record_checksum does not match canonical record payload")
        return self


class SourceCounts(BaseModel):
    model_config = ConfigDict(extra="forbid")

    extracted: int = Field(ge=0)
    normalized: int = Field(ge=0)
    approved: int = Field(ge=0)
    quarantined: int = Field(ge=0)
    duplicates: int = Field(ge=0)

    @model_validator(mode="after")
    def validate_count_relationships(self) -> "SourceCounts":
        if self.normalized > self.extracted:
            raise ValueError("normalized count cannot exceed extracted count")
        if self.approved > self.normalized:
            raise ValueError("approved count cannot exceed normalized count")
        return self


class SourceManifest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    schema_version: Literal[1] = 1
    snapshot_id: str = Field(min_length=1, max_length=500)
    source_name: SourceName
    source_version: str = Field(min_length=1, max_length=64)
    official_url: AnyHttpUrl
    license_id: AllowedLicenseId
    license_url: AnyHttpUrl
    attribution_text: str = Field(min_length=1, max_length=2000)
    retrieved_at: datetime
    raw_sha256: str = Field(pattern=SHA256_PATTERN)
    expected_raw_sha256: str | None = Field(
        default=None,
        pattern=SHA256_PATTERN,
    )
    normalized_sha256: str = Field(pattern=SHA256_PATTERN)
    normalized_bytes: int = Field(gt=0)
    record_checksum_root: str = Field(pattern=SHA256_PATTERN)
    adapter_version: int = Field(ge=1)
    status: Literal["downloaded", "normalized", "approved", "rejected"]
    counts: SourceCounts

    @field_validator("official_url", "license_url")
    @classmethod
    def require_https(cls, value: AnyHttpUrl) -> AnyHttpUrl:
        if value.scheme != "https":
            raise ValueError("ETL manifest URLs must use HTTPS")
        return value

    @field_validator("retrieved_at", mode="after")
    @classmethod
    def require_timezone_aware(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("retrieved_at must include timezone information")
        return value

    @model_validator(mode="after")
    def validate_cross_fields(self) -> "SourceManifest":
        source_key = self.source_name.value

        # license must be approved for this source
        allowed_licenses = _SOURCE_ALLOWED_LICENSES.get(source_key, frozenset())
        if self.license_id.value not in allowed_licenses:
            raise ValueError(
                f"license {self.license_id.value!r} is not approved for source "
                f"{source_key!r}"
            )

        # official_url host must be on the allowlist (not applicable for admin_upload)
        if source_key != "admin_upload":
            allowed_hosts = _SOURCE_ALLOWED_HOSTS.get(source_key, frozenset())
            host = self.official_url.host
            if host not in allowed_hosts:
                raise ValueError(
                    f"Host {host!r} is not approved for source {source_key!r}"
                )

        # snapshot_id = "{source_name}:{source_version}:{raw_sha256}"
        expected_id = f"{source_key}:{self.source_version}:{self.raw_sha256}"
        if self.snapshot_id != expected_id:
            raise ValueError(
                "snapshot_id must equal '{source_name}:{source_version}:{raw_sha256}'"
            )

        return self


class QuarantineEntry(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    source_name: SourceName
    source_version: str = Field(min_length=1, max_length=64)
    source_location: str = Field(min_length=1, max_length=1000)
    error_code: str = Field(
        min_length=1,
        max_length=100,
        pattern=r"^[a-z0-9_]+$",
    )
    message: str = Field(min_length=1, max_length=2000)
    raw_excerpt_hash: str = Field(pattern=SHA256_PATTERN)
