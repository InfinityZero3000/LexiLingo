"""Golden tests for core lexical ETL adapters."""

from __future__ import annotations

from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


# ---------------------------------------------------------------------------
# OEWN adapter
# ---------------------------------------------------------------------------

def test_oewn_parses_all_entries():
    from api.services.content_etl.adapters.oewn import parse

    records = parse(FIXTURES / "oewn_mini.xml")

    assert len(records) == 3
    words = {r["word"] for r in records}
    assert "journey" in words
    assert "travel" in words
    assert "quick" in words


def test_oewn_pos_mapping():
    from api.services.content_etl.adapters.oewn import parse

    records = {r["word"]: r for r in parse(FIXTURES / "oewn_mini.xml")}

    assert records["journey"]["part_of_speech"] == "noun"
    assert records["travel"]["part_of_speech"] == "verb"
    assert records["quick"]["part_of_speech"] == "adjective"


def test_oewn_definition_is_present():
    from api.services.content_etl.adapters.oewn import parse

    records = {r["word"]: r for r in parse(FIXTURES / "oewn_mini.xml")}

    assert "travelling" in records["journey"]["definition"]


def test_oewn_example_sentence_extracted():
    from api.services.content_etl.adapters.oewn import parse

    records = {r["word"]: r for r in parse(FIXTURES / "oewn_mini.xml")}

    assert records["travel"]["example"] is not None
    assert "work" in records["travel"]["example"]


def test_oewn_attribution_and_license():
    from api.services.content_etl.adapters.oewn import parse, ATTRIBUTION_TEXT, LICENSE_ID

    records = parse(FIXTURES / "oewn_mini.xml")

    for record in records:
        assert record["attribution_text"] == ATTRIBUTION_TEXT
        assert record["license_id"] == LICENSE_ID
        assert "CC-BY-4.0" == record["license_id"]


def test_oewn_lineage_fields():
    from api.services.content_etl.adapters.oewn import parse

    records = parse(FIXTURES / "oewn_mini.xml")

    for record in records:
        lineage = record["lineage"]
        assert lineage["adapter"] == "oewn"
        assert lineage["adapter_version"] == 1
        assert lineage["raw_path"] == "oewn_mini.xml"
        assert lineage["source_location"]


def test_oewn_record_ids_are_unique():
    from api.services.content_etl.adapters.oewn import parse

    records = parse(FIXTURES / "oewn_mini.xml")
    ids = [r["record_id"] for r in records]
    assert len(ids) == len(set(ids))


# ---------------------------------------------------------------------------
# CMUdict adapter
# ---------------------------------------------------------------------------

def test_cmudict_parses_entries():
    from api.services.content_etl.adapters.cmudict import parse

    records = parse(FIXTURES / "cmudict_mini.dict")

    words = {r["word"] for r in records}
    assert "journey" in words
    assert "quick" in words
    assert "travel" in words
    assert "tomato" in words


def test_cmudict_normalises_arpabet_stress():
    from api.services.content_etl.adapters.cmudict import parse

    records = {r["word"]: r for r in parse(FIXTURES / "cmudict_mini.dict")}

    # Stress digits must be stripped.
    assert "1" not in records["journey"]["pronunciation"]
    assert "2" not in records["journey"]["pronunciation"]
    assert "0" not in records["journey"]["pronunciation"]


def test_cmudict_variant_collapses_to_single_record():
    from api.services.content_etl.adapters.cmudict import parse

    records = parse(FIXTURES / "cmudict_mini.dict")
    tomato_records = [r for r in records if r["word"] == "tomato"]
    # Variants (tomato(2)) should collapse to one record.
    assert len(tomato_records) == 1


def test_cmudict_attribution():
    from api.services.content_etl.adapters.cmudict import parse, ATTRIBUTION_TEXT, LICENSE_ID

    records = parse(FIXTURES / "cmudict_mini.dict")
    for record in records:
        assert record["attribution_text"] == ATTRIBUTION_TEXT
        assert record["license_id"] == LICENSE_ID


# ---------------------------------------------------------------------------
# CEFR-J adapter
# ---------------------------------------------------------------------------

def test_cefr_j_parses_labels():
    from api.services.content_etl.adapters.cefr_j import parse

    records = parse(FIXTURES / "cefr_j_mini.csv")

    assert len(records) == 5
    cefr_map = {r["word"]: r["declared_cefr"] for r in records}
    assert cefr_map["journey"] == "A2"
    assert cefr_map["research"] == "B2"
    assert cefr_map["sophisticated"] == "C1"


def test_cefr_j_rejects_sharealike_file():
    from api.services.content_etl.adapters.cefr_j import parse
    import tempfile

    # A path containing 'octanove' must be rejected.
    with tempfile.NamedTemporaryFile(
        suffix=".csv",
        prefix="octanove_",
        mode="w",
        encoding="utf-8",
        delete=False,
    ) as tmp:
        tmp.write("headword,CEFR\ntest,A1\n")
        tmp_path = Path(tmp.name)

    try:
        with pytest.raises(ValueError, match="license"):
            parse(tmp_path)
    finally:
        tmp_path.unlink(missing_ok=True)


def test_cefr_j_attribution():
    from api.services.content_etl.adapters.cefr_j import parse, ATTRIBUTION_TEXT, LICENSE_ID

    records = parse(FIXTURES / "cefr_j_mini.csv")
    for record in records:
        assert record["attribution_text"] == ATTRIBUTION_TEXT
        assert record["license_id"] == LICENSE_ID


# ---------------------------------------------------------------------------
# Wikidata adapter
# ---------------------------------------------------------------------------

def test_wikidata_parses_english_labels():
    from api.services.content_etl.adapters.wikidata import parse

    records = parse(FIXTURES / "wikidata_mini.json")

    # Q9999 has no English label, so only 2 records expected.
    assert len(records) == 2
    words = {r["word"] for r in records}
    assert "travel" in words
    assert "science" in words


def test_wikidata_topic_ids():
    from api.services.content_etl.adapters.wikidata import parse

    records = {r["word"]: r for r in parse(FIXTURES / "wikidata_mini.json")}

    assert records["travel"]["topic_ids"] == ["Q1345"]
    assert records["science"]["topic_ids"] == ["Q3450"]


def test_wikidata_record_ids_use_qid():
    from api.services.content_etl.adapters.wikidata import parse

    records = parse(FIXTURES / "wikidata_mini.json")
    ids = {r["record_id"] for r in records}
    assert "wikidata:Q1345" in ids
    assert "wikidata:Q3450" in ids


def test_wikidata_attribution():
    from api.services.content_etl.adapters.wikidata import parse, ATTRIBUTION_TEXT, LICENSE_ID

    records = parse(FIXTURES / "wikidata_mini.json")
    for record in records:
        assert record["attribution_text"] == ATTRIBUTION_TEXT
        assert record["license_id"] == LICENSE_ID
        assert record["license_id"] == "CC0-1.0"
