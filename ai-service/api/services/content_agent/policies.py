"""Allowlisted source policies and pre-persistence content filtering."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Any

from api.models.content_agent import (
    ContentUsage,
    LicenseMode,
    NormalizedSourceRecord,
)


class SourcePolicyError(ValueError):
    """Raised when a source is unsupported, expired, or not licensed."""


@dataclass(frozen=True)
class SourcePolicy:
    source_name: str
    license_mode: LicenseMode
    content_usage: ContentUsage
    reviewed_at: date
    expires_at: date
    rate_limit_per_minute: int
    content_storage_allowed: bool
    enabled: bool = True
    ownership_verification_required: bool = False
    metadata_fields: tuple[str, ...] = ()


_REVIEWED_AT = date(2026, 6, 14)
_EXPIRES_AT = date(2027, 6, 14)
_SAFE_METADATA_FIELDS = (
    "author",
    "category",
    "duration_seconds",
    "language",
    "resource_type",
)


def _policy(
    source_name: str,
    license_mode: LicenseMode,
    content_usage: ContentUsage,
    *,
    rate_limit: int,
    content_storage_allowed: bool,
    enabled: bool = True,
    ownership_verification_required: bool = False,
) -> SourcePolicy:
    return SourcePolicy(
        source_name=source_name,
        license_mode=license_mode,
        content_usage=content_usage,
        reviewed_at=_REVIEWED_AT,
        expires_at=_EXPIRES_AT,
        rate_limit_per_minute=rate_limit,
        content_storage_allowed=content_storage_allowed,
        enabled=enabled,
        ownership_verification_required=ownership_verification_required,
        metadata_fields=_SAFE_METADATA_FIELDS,
    )


SOURCE_POLICIES: dict[str, SourcePolicy] = {
    "existing_cefr": _policy(
        "existing_cefr",
        LicenseMode.APPROVED_DATASET,
        ContentUsage.LABEL_ONLY,
        rate_limit=0,
        content_storage_allowed=True,
    ),
    "admin_upload": _policy(
        "admin_upload",
        LicenseMode.ADMIN_OWNED,
        ContentUsage.FULL_TEXT,
        rate_limit=0,
        content_storage_allowed=True,
    ),
    "oewn": _policy(
        "oewn",
        LicenseMode.APPROVED_DATASET,
        ContentUsage.FULL_TEXT,
        rate_limit=0,
        content_storage_allowed=True,
    ),
    "cmudict": _policy(
        "cmudict",
        LicenseMode.APPROVED_DATASET,
        ContentUsage.LABEL_ONLY,
        rate_limit=0,
        content_storage_allowed=True,
    ),
    "cefr_j": _policy(
        "cefr_j",
        LicenseMode.APPROVED_DATASET,
        ContentUsage.LABEL_ONLY,
        rate_limit=0,
        content_storage_allowed=True,
    ),
    "wikidata": _policy(
        "wikidata",
        LicenseMode.APPROVED_DATASET,
        ContentUsage.METADATA_ONLY,
        rate_limit=0,
        content_storage_allowed=True,
    ),
    "tatoeba": _policy(
        "tatoeba",
        LicenseMode.APPROVED_DATASET,
        ContentUsage.FULL_TEXT,
        rate_limit=0,
        content_storage_allowed=True,
    ),
    "librispeech": _policy(
        "librispeech",
        LicenseMode.APPROVED_DATASET,
        ContentUsage.FULL_TEXT,
        rate_limit=0,
        content_storage_allowed=True,
    ),
    "common_voice": _policy(
        "common_voice",
        LicenseMode.APPROVED_DATASET,
        ContentUsage.FULL_TEXT,
        rate_limit=0,
        content_storage_allowed=True,
    ),
}


def get_source_policy(
    source_name: str,
    *,
    as_of: date | None = None,
) -> SourcePolicy:
    normalized_name = source_name.strip().lower()
    policy = SOURCE_POLICIES.get(normalized_name)
    if policy is None:
        raise SourcePolicyError(f"Unsupported content source: {normalized_name}")
    if not policy.enabled:
        raise SourcePolicyError(
            f"Content source is disabled pending license approval: {normalized_name}"
        )
    if (as_of or date.today()) > policy.expires_at:
        raise SourcePolicyError(
            f"Content source policy review has expired: {normalized_name}"
        )
    return policy


def _filtered_metadata(
    metadata: Any,
    allowed_fields: tuple[str, ...],
) -> dict[str, Any]:
    if not isinstance(metadata, dict):
        return {}
    return {
        key: metadata[key]
        for key in allowed_fields
        if key in metadata
        and isinstance(metadata[key], (str, int, float, bool, type(None)))
    }


def apply_source_policy(
    source_name: str,
    record: dict[str, Any],
    *,
    as_of: date | None = None,
) -> NormalizedSourceRecord:
    """Return the only record shape allowed to enter the temporary store."""

    policy = get_source_policy(source_name, as_of=as_of)
    content_usage = policy.content_usage
    if (
        policy.ownership_verification_required
        and not record.get("ownership_verified", False)
    ):
        content_usage = ContentUsage.METADATA_ONLY

    common = {
        "record_id": record.get("record_id"),
        "source_name": policy.source_name,
        "source_url": record.get("source_url"),
        "license_mode": policy.license_mode,
        "content_usage": content_usage,
        "title": record.get("title"),
        "declared_cefr": record.get("declared_cefr"),
        "declared_topic": record.get("declared_topic") or "general",
        "published_at": record.get("published_at"),
        "checksum": record.get("checksum"),
        "source_version": record.get("source_version"),
        "source_record_id": record.get("source_record_id"),
        "license_id": record.get("license_id"),
        "license_url": record.get("license_url"),
        "attribution_text": record.get("attribution_text"),
        "raw_checksum": record.get("raw_checksum"),
        "lineage": record.get("lineage"),
        "source_content_usage": record.get("source_content_usage"),
        "metadata": _filtered_metadata(
            record.get("metadata"),
            policy.metadata_fields,
        ),
        "classification_confidence": record.get(
            "classification_confidence",
            1.0,
        ),
    }

    if content_usage == ContentUsage.FULL_TEXT:
        common.update(
            {
                "word": record.get("word"),
                "part_of_speech": record.get("part_of_speech") or "phrase",
                "definition": record.get("definition"),
                "translation_vi": record.get("translation_vi"),
                "example": record.get("example"),
            }
        )
    elif content_usage == ContentUsage.LABEL_ONLY:
        common.update(
            {
                "word": record.get("word"),
                "part_of_speech": record.get("part_of_speech") or "phrase",
            }
        )

    return NormalizedSourceRecord.model_validate(common)
