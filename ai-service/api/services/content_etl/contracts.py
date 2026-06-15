"""Strict contracts for immutable licensed-content snapshots."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Literal

from pydantic import (
    AnyHttpUrl,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


SHA256_PATTERN = r"^[a-f0-9]{64}$"

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
    source_version: str = Field(min_length=1, max_length=255)
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
    source_version: str = Field(min_length=1, max_length=255)
    source_location: str = Field(min_length=1, max_length=1000)
    error_code: str = Field(
        min_length=1,
        max_length=100,
        pattern=r"^[a-z0-9_]+$",
    )
    message: str = Field(min_length=1, max_length=2000)
    raw_excerpt_hash: str = Field(pattern=SHA256_PATTERN)
