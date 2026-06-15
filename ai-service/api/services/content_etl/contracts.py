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
    def validate_count_relationships(self):
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

