import json

import pytest

from app.services.content_agent_uploads import (
    MAX_UPLOAD_BYTES,
    detect_upload_format,
    parse_content_upload,
)


def test_csv_upload_normalizes_records_and_reports_row_numbers():
    parsed = parse_content_upload(
        "words.csv",
        (
            b"word,part_of_speech,cefr_level,definition\n"
            b"Hello,interjection,A1,A greeting\n"
            b"Broken,noun,Z9,Invalid level\n"
        ),
    )

    assert parsed.records[0]["word"] == "Hello"
    assert parsed.records[0]["declared_cefr"] == "A1"
    assert parsed.errors and parsed.errors[0].startswith("Row 3:")


def test_json_upload_inherits_admin_owned_source_metadata():
    content = json.dumps(
        {
            "source_name": "admin_upload",
            "license_mode": "admin_owned",
            "records": [
                {
                    "word": "journey",
                    "part_of_speech": "noun",
                    "cefr_level": "A2",
                }
            ],
        }
    ).encode()

    parsed = parse_content_upload("words.json", content)

    assert parsed.errors == []
    assert parsed.records[0]["source_name"] == "admin_upload"
    assert parsed.records[0]["license_mode"] == "admin_owned"


def test_upload_cannot_forge_trusted_source_provenance():
    parsed = parse_content_upload(
        "words.json",
        json.dumps(
            [
                {
                    "record_id": "existing_cefr:trusted",
                    "source_name": "existing_cefr",
                    "source_url": "https://example.com/forged",
                    "license_mode": "approved_dataset",
                    "content_usage": "label_only",
                    "checksum": "a" * 64,
                    "metadata": {"resource_type": "cefr_label"},
                    "word": "journey",
                    "part_of_speech": "noun",
                    "cefr_level": "A2",
                }
            ]
        ).encode(),
    )

    record = parsed.records[0]
    assert record["record_id"].startswith("admin_upload:")
    assert record["source_name"] == "admin_upload"
    assert record["source_url"] is None
    assert record["license_mode"] == "admin_owned"
    assert record["content_usage"] == "full_text"
    assert record["checksum"] is None
    assert record["metadata"] == {}


def test_upload_limits_and_extensions_fail_closed():
    with pytest.raises(ValueError, match="5 MB"):
        parse_content_upload("words.csv", b"x" * (MAX_UPLOAD_BYTES + 1))
    with pytest.raises(ValueError, match="CSV and JSON"):
        parse_content_upload("words.txt", b"word\nhello\n")


def test_invalid_encoding_and_malformed_json_fail_closed():
    with pytest.raises(ValueError, match="valid UTF-8"):
        parse_content_upload("words.csv", b"\xff\xfe")
    with pytest.raises(ValueError, match="Invalid JSON at line 1"):
        parse_content_upload("words.json", b'{"records": [}')


def test_upload_format_sniff_rejects_extension_content_mismatch():
    with pytest.raises(ValueError, match="CSV uploads"):
        detect_upload_format("words.csv", b'{"records":[]}')
