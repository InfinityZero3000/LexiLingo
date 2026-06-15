import pytest

from api.models.content_agent import ContentUsage, LicenseMode
from api.services.content_agent.adapters import (
    normalize_existing_cefr_records,
    normalize_source_records,
)
from api.services.content_agent.policies import SourcePolicyError


def test_existing_cefr_mapping_becomes_label_only_records():
    records = normalize_existing_cefr_records(
        {" Apple ": "A1", "journey": "A2"},
    )

    assert [(record.word, record.declared_cefr.value) for record in records] == [
        ("apple", "A1"),
        ("journey", "A2"),
    ]
    assert all(record.source_name == "existing_cefr" for record in records)
    assert all(record.license_mode == LicenseMode.APPROVED_DATASET for record in records)
    assert all(record.content_usage == ContentUsage.LABEL_ONLY for record in records)
    assert all(record.classification_confidence == 1.0 for record in records)


def test_admin_upload_preserves_owned_fields_and_normalizes_identity():
    records = normalize_source_records(
        [
            {
                "word": "  Mother’s-in-law  ",
                "part_of_speech": "noun",
                "cefr_level": "B1",
                "definition": "A family relationship.",
                "translation_vi": "mẹ chồng hoặc mẹ vợ",
                "example": "Her mother-in-law called.",
                "topic": "family life",
            }
        ],
        source_name="admin_upload",
    )

    record = records[0]
    assert record.word == "mother's-in-law"
    assert record.declared_cefr.value == "B1"
    assert record.declared_topic == "family_life"
    assert record.definition == "A family relationship."
    assert record.license_mode == LicenseMode.ADMIN_OWNED
    assert record.content_usage == ContentUsage.FULL_TEXT
    assert record.record_id.startswith("admin_upload:")


def test_mixed_records_use_each_record_source_name():
    records = normalize_source_records(
        [
            {
                "source_name": "existing_cefr",
                "record_id": "existing:1",
                "word": "book",
                "declared_cefr": "A1",
            },
            {
                "source_name": "admin_upload",
                "record_id": "upload:1",
                "word": "research",
                "declared_cefr": "B1",
            },
        ],
    )

    assert [record.source_name for record in records] == [
        "existing_cefr",
        "admin_upload",
    ]


def test_approved_dataset_source_normalizes_lexical_records():
    records = normalize_source_records(
        [
            {
                "record_id": "oewn:2025:journey-n",
                "word": " Journey ",
                "part_of_speech": "noun",
                "definition": "An act of travelling.",
                "declared_cefr": "A2",
            }
        ],
        source_name="oewn",
    )

    assert records[0].source_name == "oewn"
    assert records[0].word == "journey"
    assert records[0].definition == "An act of travelling."
    assert records[0].license_mode == LicenseMode.APPROVED_DATASET
    assert records[0].content_usage == ContentUsage.FULL_TEXT


def test_adapter_rejects_unsupported_source():
    with pytest.raises(SourcePolicyError):
        normalize_source_records(
            [{"record_id": "bad:1", "word": "bad", "declared_cefr": "A1"}],
            source_name="arbitrary_web",
        )
