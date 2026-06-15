"""Tests for corpus ETL adapters: per-record license checks and quarantine behaviour."""

from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


# ---------------------------------------------------------------------------
# Tatoeba adapter
# ---------------------------------------------------------------------------

def test_tatoeba_parses_allowed_licenses():
    from api.services.content_etl.adapters.tatoeba import parse

    # tatoeba_clean.tsv contains only CC0-1.0 and CC-BY-2.0-FR rows.
    records = parse(FIXTURES / "tatoeba_clean.tsv")

    assert len(records) == 2
    assert all(r["language"] == "eng" for r in records)
    license_ids = {r["license_id"] for r in records}
    assert license_ids <= {"CC0-1.0", "CC-BY-2.0-FR"}


def test_tatoeba_incompatible_row_raises():
    from api.services.content_etl.adapters.tatoeba import parse

    # tatoeba_mini.tsv contains a CC BY-SA 3.0 row → parser must raise.
    with pytest.raises(ValueError, match="not approved"):
        parse(FIXTURES / "tatoeba_mini.tsv")


def test_tatoeba_per_record_attribution():
    from api.services.content_etl.adapters.tatoeba import parse

    # Use a fixture with only allowed rows.
    import io, csv, tempfile

    lines = [
        "1001\teng\tThe journey took three days.\tuser1\tCC0 1.0\thttps://tatoeba.org/en/sentences/show/1001",
        "1002\teng\tShe travels for work.\tuser2\tCC-BY 2.0 FR\thttps://tatoeba.org/en/sentences/show/1002",
    ]
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".tsv", encoding="utf-8", delete=False
    ) as tmp:
        tmp.write("\n".join(lines) + "\n")
        tmp_path = Path(tmp.name)

    try:
        records = parse(tmp_path)
        assert len(records) == 2
        # Each record must carry its own attribution with author info.
        for record in records:
            assert "tatoeba" in record["attribution_text"].lower()
            assert record["license_id"] in {"CC0-1.0", "CC-BY-2.0-FR"}
    finally:
        tmp_path.unlink(missing_ok=True)


def test_tatoeba_skips_non_english_rows():
    from api.services.content_etl.adapters.tatoeba import parse
    import tempfile

    lines = [
        "2001\teng\tHello world.\tuser1\tCC0 1.0\t",
        "2002\tfra\tBonjour monde.\tuser2\tCC0 1.0\t",
        "2003\tdeu\tHallo Welt.\tuser3\tCC0 1.0\t",
    ]
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".tsv", encoding="utf-8", delete=False
    ) as tmp:
        tmp.write("\n".join(lines) + "\n")
        tmp_path = Path(tmp.name)

    try:
        records = parse(tmp_path, language_filter="eng")
        assert len(records) == 1
        assert records[0]["example"] == "Hello world."
    finally:
        tmp_path.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# LibriSpeech adapter
# ---------------------------------------------------------------------------

def test_librispeech_mini_parses_transcripts():
    from api.services.content_etl.adapters.librispeech import parse

    records = parse(FIXTURES / "librispeech_mini.txt", allow_full=True)

    assert len(records) == 3
    assert records[0]["record_id"] == "librispeech:1001-134707-0000"
    assert "JOURNEY" in records[0]["example"]


def test_librispeech_large_file_rejected_without_allow_full(tmp_path):
    from api.services.content_etl.adapters.librispeech import parse

    # Write a file that exceeds the 1MB guard.
    large_file = tmp_path / "large.txt"
    large_file.write_bytes(b"1001-0 WORD\n" * 100_000)  # ~1.3 MB

    with pytest.raises(ValueError, match="disabled"):
        parse(large_file)


def test_librispeech_attribution():
    from api.services.content_etl.adapters.librispeech import parse, ATTRIBUTION_TEXT, LICENSE_ID

    records = parse(FIXTURES / "librispeech_mini.txt", allow_full=True)
    for record in records:
        assert record["attribution_text"] == ATTRIBUTION_TEXT
        assert record["license_id"] == LICENSE_ID


# ---------------------------------------------------------------------------
# Common Voice adapter
# ---------------------------------------------------------------------------

def test_common_voice_requires_release_metadata(tmp_path):
    from api.services.content_etl.adapters.common_voice import parse

    # Copy TSV to a temp dir without release_metadata.json.
    tsv = tmp_path / "validated.tsv"
    shutil.copy(FIXTURES / "common_voice_mini.tsv", tsv)

    with pytest.raises(ValueError, match="release_metadata"):
        parse(tsv)


def test_common_voice_parses_with_valid_release_metadata(tmp_path):
    from api.services.content_etl.adapters.common_voice import parse

    shutil.copy(FIXTURES / "common_voice_mini.tsv", tmp_path / "validated.tsv")
    shutil.copy(
        FIXTURES / "common_voice_release_metadata.json",
        tmp_path / "release_metadata.json",
    )

    records = parse(tmp_path / "validated.tsv")
    assert len(records) == 2
    assert all(r["license_id"] == "CC0-1.0" for r in records)


def test_common_voice_attribution():
    from api.services.content_etl.adapters.common_voice import parse, ATTRIBUTION_TEXT, LICENSE_ID
    import shutil

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        shutil.copy(FIXTURES / "common_voice_mini.tsv", tmp_path / "validated.tsv")
        shutil.copy(
            FIXTURES / "common_voice_release_metadata.json",
            tmp_path / "release_metadata.json",
        )
        records = parse(tmp_path / "validated.tsv")
        for record in records:
            assert record["attribution_text"] == ATTRIBUTION_TEXT
            assert record["license_id"] == LICENSE_ID


def test_common_voice_no_validation_flag_skips_metadata_check(tmp_path):
    from api.services.content_etl.adapters.common_voice import parse

    # Without release_metadata.json but with validate_release=False (fixture testing).
    tsv = tmp_path / "validated.tsv"
    shutil.copy(FIXTURES / "common_voice_mini.tsv", tsv)

    records = parse(tsv, validate_release=False)
    assert len(records) == 2
