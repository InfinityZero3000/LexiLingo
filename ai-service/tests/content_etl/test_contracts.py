from __future__ import annotations

from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from api.core.config import Settings
from api.services.content_etl.contracts import (
    AllowedLicenseId,
    QuarantineEntry,
    SourceRecordV2,
    SourceCounts,
    SourceManifest,
    SourceName,
    compute_source_record_checksum,
)


def _manifest_payload() -> dict:
    return {
        "snapshot_id": "oewn:2025:" + ("a" * 64),
        "source_name": "oewn",
        "source_version": "2025",
        "official_url": "https://en-word.net/static/english-wordnet-2025.xml.gz",
        "license_id": "CC-BY-4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "attribution_text": "Open English WordNet 2025",
        "retrieved_at": datetime(2026, 6, 15, tzinfo=UTC),
        "raw_sha256": "a" * 64,
        "normalized_sha256": "c" * 64,
        "normalized_bytes": 1234,
        "record_checksum_root": "d" * 64,
        "adapter_version": 1,
        "status": "approved",
        "counts": {
            "extracted": 10,
            "normalized": 9,
            "approved": 8,
            "quarantined": 1,
            "duplicates": 1,
        },
    }


def _record_payload() -> dict:
    payload = {
        "schema_version": 2,
        "record_id": "oewn:lemma-bank-n-1",
        "source_name": "oewn",
        "source_version": "2025",
        "source_record_id": "oewn-bank-n-1",
        "source_url": "https://en-word.net/lemma/bank",
        "license_id": "CC-BY-4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "attribution_text": "Open English WordNet 2025",
        "content_usage": "lexical",
        "language": "en",
        "word": "bank",
        "part_of_speech": "noun",
        "definition": "A financial institution.",
        "retrieved_at": datetime(2026, 6, 15, tzinfo=UTC),
        "raw_checksum": "a" * 64,
        "lineage": {
            "adapter": "oewn",
            "adapter_version": 1,
            "raw_path": "english-wordnet-2025.xml",
            "source_location": "oewn-bank-n-1",
        },
    }
    payload["record_checksum"] = compute_source_record_checksum(payload)
    return payload


def test_source_record_v2_requires_complete_licensed_lineage():
    record = SourceRecordV2.model_validate(_record_payload())

    assert record.schema_version == 2
    assert record.source_name == SourceName.OEWN
    assert record.license_id == AllowedLicenseId.CC_BY_4_0

    for required_field in (
        "source_version",
        "source_record_id",
        "license_id",
        "retrieved_at",
        "raw_checksum",
        "record_checksum",
        "lineage",
    ):
        payload = _record_payload()
        payload.pop(required_field)
        with pytest.raises(ValidationError):
            SourceRecordV2.model_validate(payload)

    with pytest.raises(ValidationError):
        SourceRecordV2.model_validate({**_record_payload(), "unexpected": True})
    with pytest.raises(ValidationError, match="license"):
        SourceRecordV2.model_validate(
            {**_record_payload(), "license_id": "CC0-1.0"}
        )
    with pytest.raises(ValidationError, match="control"):
        SourceRecordV2.model_validate(
            {**_record_payload(), "definition": "unsafe\u0000text"}
        )


@pytest.mark.parametrize(
    ("content_usage", "missing_field"),
    [
        ("lexical", "definition"),
        ("pronunciation", "pronunciation"),
        ("label", "declared_cefr"),
        ("topic", "topic_ids"),
        ("example", "example"),
        ("audio", "audio"),
    ],
)
def test_source_record_v2_requires_payload_for_content_usage(
    content_usage,
    missing_field,
):
    payload = {
        **_record_payload(),
        "content_usage": content_usage,
        "pronunciation": "B AE NG K",
        "declared_cefr": "B1",
        "topic_ids": ["Q1"],
        "example": "The bank closes at five.",
        "audio": {
            "url": "https://example.com/bank.mp3",
            "mime_type": "audio/mpeg",
        },
    }
    payload.pop(missing_field, None)

    with pytest.raises(ValidationError, match=missing_field):
        SourceRecordV2.model_validate(payload)


def test_source_manifest_is_strict_and_validates_integrity_fields():
    manifest = SourceManifest.model_validate(_manifest_payload())

    assert manifest.schema_version == 1
    assert manifest.source_name == SourceName.OEWN
    assert manifest.license_id == AllowedLicenseId.CC_BY_4_0
    assert manifest.counts.approved == 8

    with pytest.raises(ValidationError):
        SourceManifest.model_validate({**_manifest_payload(), "unexpected": True})
    with pytest.raises(ValidationError):
        SourceManifest.model_validate({**_manifest_payload(), "raw_sha256": "bad"})
    with pytest.raises(ValidationError):
        SourceManifest.model_validate({**_manifest_payload(), "attribution_text": ""})
    with pytest.raises(ValidationError):
        SourceManifest.model_validate(
            {**_manifest_payload(), "official_url": "http://en-word.net/file"}
        )
    with pytest.raises(ValidationError, match="license"):
        SourceManifest.model_validate(
            {**_manifest_payload(), "license_id": "CC0-1.0"}
        )
    with pytest.raises(ValidationError, match="Host"):
        SourceManifest.model_validate(
            {
                **_manifest_payload(),
                "official_url": "https://evil.example/oewn.xml.gz",
            }
        )
    with pytest.raises(ValidationError, match="snapshot_id"):
        SourceManifest.model_validate(
            {**_manifest_payload(), "snapshot_id": "oewn:2025:" + ("b" * 64)}
        )
    with pytest.raises(ValidationError, match="timezone"):
        SourceManifest.model_validate(
            {
                **_manifest_payload(),
                "retrieved_at": datetime(2026, 6, 15),
            }
        )


def test_source_counts_cannot_claim_more_approved_rows_than_normalized():
    with pytest.raises(ValidationError):
        SourceCounts(
            extracted=1,
            normalized=1,
            approved=2,
            quarantined=0,
            duplicates=0,
        )


def test_quarantine_entry_is_strict_and_hashes_raw_excerpt():
    entry = QuarantineEntry(
        source_name="cefr_j",
        source_version="0123456789abcdef0123456789abcdef01234567",
        source_location="cefrj-vocabulary-profile.csv:12",
        error_code="unsupported_license",
        message="Octanove ShareAlike rows are not approved",
        raw_excerpt_hash="b" * 64,
    )
    assert entry.raw_excerpt_hash == "b" * 64

    with pytest.raises(ValidationError):
        QuarantineEntry.model_validate(
            {**entry.model_dump(), "raw_excerpt": "must never be persisted"}
        )


def test_development_settings_keep_etl_disabled_and_allow_empty_pins():
    settings = Settings(
        _env_file=None,
        ENVIRONMENT="development",
        CONTENT_ETL_ENABLED=False,
        CONTENT_ETL_CMU_REF="",
        CONTENT_ETL_CEFR_J_REF="",
        CONTENT_ETL_WIKIDATA_SNAPSHOT="",
    )

    assert settings.CONTENT_ETL_ENABLED is False
    assert settings.CONTENT_ETL_STORAGE_ROOT == "/data/content-etl"
    assert settings.CONTENT_ETL_MAX_QUARANTINE_RATIO == 0.02


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("CONTENT_ETL_HTTP_TIMEOUT_SECONDS", 0),
        ("CONTENT_ETL_MAX_DOWNLOAD_BYTES", 0),
        ("CONTENT_ETL_MAX_QUARANTINE_RATIO", -0.01),
        ("CONTENT_ETL_MAX_QUARANTINE_RATIO", 1.01),
        ("CONTENT_ETL_USER_AGENT", ""),
    ],
)
def test_etl_settings_reject_invalid_security_limits(field, value):
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **{field: value})


@pytest.mark.parametrize("moving_ref", ["main", "master", "latest", "HEAD"])
def test_production_etl_rejects_empty_or_moving_pins(moving_ref):
    base = {
        "_env_file": None,
        "ENVIRONMENT": "production",
        "DEBUG": False,
        "SECRET_KEY": "x" * 32,
        "CONTENT_ETL_ENABLED": True,
        "CONTENT_ETL_CMU_REF": "1" * 40,
        "CONTENT_ETL_CEFR_J_REF": "2" * 40,
        "CONTENT_ETL_OEWN_SHA256": "a" * 64,
        "CONTENT_ETL_CMU_SHA256": "b" * 64,
        "CONTENT_ETL_CEFR_J_SHA256": "c" * 64,
        "CONTENT_ETL_WIKIDATA_SNAPSHOT": "2026-06-15",
    }

    with pytest.raises(ValidationError, match="pinned"):
        Settings(**{**base, "CONTENT_ETL_CMU_REF": moving_ref})
    with pytest.raises(ValidationError, match="pinned"):
        Settings(**{**base, "CONTENT_ETL_CEFR_J_REF": ""})
    with pytest.raises(ValidationError, match="pinned"):
        Settings(**{**base, "CONTENT_ETL_WIKIDATA_SNAPSHOT": "latest"})


def test_production_etl_accepts_immutable_core_pins():
    settings = Settings(
        _env_file=None,
        ENVIRONMENT="production",
        DEBUG=False,
        SECRET_KEY="x" * 32,
        CONTENT_ETL_ENABLED=True,
        CONTENT_ETL_OEWN_VERSION="2025",
        CONTENT_ETL_CMU_REF="1" * 40,
        CONTENT_ETL_CEFR_J_REF="2" * 40,
        CONTENT_ETL_OEWN_SHA256="a" * 64,
        CONTENT_ETL_CMU_SHA256="b" * 64,
        CONTENT_ETL_CEFR_J_SHA256="c" * 64,
        CONTENT_ETL_WIKIDATA_SNAPSHOT="2026-06-15",
    )

    assert settings.CONTENT_ETL_ENABLED is True


def test_production_etl_rejects_missing_dataset_checksum():
    with pytest.raises(ValidationError, match="SHA-256"):
        Settings(
            _env_file=None,
            ENVIRONMENT="production",
            DEBUG=False,
            SECRET_KEY="x" * 32,
            CONTENT_ETL_ENABLED=True,
            CONTENT_ETL_OEWN_VERSION="2025",
            CONTENT_ETL_CMU_REF="1" * 40,
            CONTENT_ETL_CEFR_J_REF="2" * 40,
            CONTENT_ETL_OEWN_SHA256="",
            CONTENT_ETL_CMU_SHA256="b" * 64,
            CONTENT_ETL_CEFR_J_SHA256="c" * 64,
        )
