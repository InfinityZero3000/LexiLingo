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


def test_oewn_parses_the_published_gzipped_release(tmp_path):
    """The pinned artifact is gzipped and namespace-free; parsing it as plain,
    namespaced XML is why the OEWN sync produced 0 records."""
    import gzip

    from api.services.content_etl.adapters.oewn import parse

    source = (FIXTURES / "oewn_mini_release.xml").read_bytes()
    gzipped = tmp_path / "english-wordnet-2025.xml.gz"
    gzipped.write_bytes(gzip.compress(source))

    records = parse(gzipped)

    assert [r["word"] for r in records] == ["journey", "journey"]
    assert records[0]["definition"] == "An act of travelling from one place to another."
    # the first synset example; the real release has no SenseExample at all
    assert records[0]["example"] == "Their journey took three days."
    assert records[1]["example"] is None
    assert [r["metadata"]["sense_rank"] for r in records] == [1, 2]


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
        assert lineage["adapter_version"] == 2
        assert lineage["raw_path"] == "oewn_mini.xml"
        assert lineage["source_location"]


def test_oewn_records_the_rank_of_each_sense_within_its_entry():
    from collections import defaultdict

    from api.services.content_etl.adapters.oewn import parse

    ranks = defaultdict(list)
    for record in parse(FIXTURES / "oewn_mini.xml"):
        ranks[(record["word"], record["part_of_speech"])].append(
            record["metadata"]["sense_rank"]
        )

    assert ranks and all(r == list(range(1, len(r) + 1)) for r in ranks.values())


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
    # The pinned cmudict.dict is lowercase with inline "#" notes; an
    # uppercase-only fixture hid that the adapter parsed 0 of its 135k lines.
    assert "aalborg" in words
    pronunciation = next(r for r in records if r["word"] == "aalborg")["pronunciation"]
    assert pronunciation == "AO1 L B AO0 R G"


def test_cmudict_keeps_stress_digits_the_ipa_conversion_needs():
    from api.services.content_etl.adapters.cmudict import parse

    records = {r["word"]: r for r in parse(FIXTURES / "cmudict_mini.dict")}

    assert records["journey"]["pronunciation"] == "JH ER1 N IY0"


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


def test_cefr_j_reads_the_published_file_layout():
    """Rows copied from the real profile: one headword per part of speech,
    full pos names, and spelling variants sharing a row."""
    from api.services.content_etl.adapters.cefr_j import parse

    records = parse(FIXTURES / "cefr_j_real_sample.csv")

    assert len({r["record_id"] for r in records}) == len(records) == 17
    pos = {(r["word"], r["part_of_speech"]): r["declared_cefr"] for r in records}
    assert pos[("about", "adverb")] == pos[("about", "preposition")] == "A1"
    assert pos[("can", "noun")] == "A2"
    assert pos[("be", "verb")] == "A1"  # be-verb
    # classes the lexicon has no slot for map to the nearest WordNet class
    assert pos[("eight", "noun")] == "A1" and pos[("a", "adjective")] == "A1"
    # a modal "can", the infinitive marker "to" (the preposition stays) and the
    # contraction "'m" have no lexical meaning to teach
    assert ("can", "verb") not in pos
    assert ("to", "preposition") in pos and len([w for w, _ in pos if w == "to"]) == 1
    assert "'m" not in {word for word, _ in pos}
    # first spelling of a variant row, which is the American one
    assert ("color", "noun") in pos and ("colour", "noun") not in pos
    assert ("a.m.", "adverb") in pos
    assert ("internet", "noun") in pos


def test_cefr_j_real_layout_clears_the_pipeline_without_quarantine(tmp_path):
    from api.services.content_etl.adapters.cefr_j import (
        ATTRIBUTION_TEXT,
        LICENSE_ID,
        LICENSE_URL,
        OFFICIAL_URL,
        parse,
    )
    from api.services.content_etl.pipeline import ETLPipeline
    from api.services.content_etl.storage import SnapshotStorage

    raw_path = FIXTURES / "cefr_j_real_sample.csv"
    storage = SnapshotStorage(tmp_path)
    temp = storage.create_temp_file()
    temp.write_bytes(raw_path.read_bytes())
    import hashlib

    storage.promote_raw(
        temp,
        source_name="cefr_j",
        version="1" * 40,
        filename=raw_path.name,
        sha256=hashlib.sha256(raw_path.read_bytes()).hexdigest(),
    )

    report = ETLPipeline(storage=storage).run(
        source_name="cefr_j",
        source_version="1" * 40,
        adapter_name="cefr_j",
        adapter_version=1,
        license_id=LICENSE_ID,
        license_url=LICENSE_URL,
        attribution_text=ATTRIBUTION_TEXT,
        raw_records=parse(raw_path),
        raw_bytes=raw_path.read_bytes(),
        official_url=OFFICIAL_URL,
    )

    assert (report.status, report.approved, report.quarantined) == ("approved", 17, 0)


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
