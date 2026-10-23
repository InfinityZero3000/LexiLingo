"""Reference corpora (OEWN, CMUdict) enrich seed words; they never seed a course."""

from __future__ import annotations

import asyncio

import pytest

from api.models.content_agent import (
    GenerationRequest,
    SnapshotReference,
    SourceRecordBatch,
)
from api.services.content_agent.phonetics import arpabet_to_ipa
from api.services.content_agent.service import ContentAgentService
from api.services.content_agent.store import ContentAgentStore
from api.services.content_etl.storage import SnapshotStorage
from tests.content_agent_snapshots import (
    cefr_j_records,
    cmudict_records,
    oewn_senses,
    stage_snapshot,
)

SEEDS = ["house", "dog", "water", "book", "light", "open", "happy", "run"]
JOB = "enrich-job"


def _oewn() -> list[dict]:
    return [
        *oewn_senses(
            "house",
            "noun",
            [
                ("a dwelling that serves as living quarters for one or more families", "he has a house on the lake"),
                ("a building for people", None),
            ],
        ),
        *oewn_senses("dog", "noun", [("a domesticated carnivorous mammal", "the dog barked all night")]),
        *oewn_senses("water", "noun", [("a clear colorless fluid that people drink", None)]),
        *oewn_senses("book", "noun", [("a written work bound between covers", "she read a book")]),
        # the second sense is under 10 chars, so it can never be chosen
        # the most common sense is under 10 chars, so the next one is used
        *oewn_senses(
            "run", "verb", [("go", None), ("move fast by using your legs", "run to the shop")]
        ),
        *[
            record
            for index in range(40)
            for record in oewn_senses(f"filler{index}", "noun", [("a filler sense for bulk", None)])
        ],
    ]


def _cmudict() -> list[dict]:
    return cmudict_records(
        {"house": "HH AW1 S", "dog": "D AO1 G", "water": "W AO1 T ER0", "light": "L AY1 T"}
    )


def _request(sources=("cefr_j", "oewn", "cmudict")) -> GenerationRequest:
    return GenerationRequest(
        levels=["A1"],
        sources=list(sources),
        units_per_course=1,
        lessons_per_unit=1,
        words_per_lesson=8,
    )


class Job:
    def __init__(self, tmp_path, *, oewn=None, max_records=20):
        self.storage = SnapshotStorage(tmp_path)
        self.service = ContentAgentService(
            store=ContentAgentStore(ttl_seconds=60, max_records=max_records)
        )
        self.seed = stage_snapshot(self.storage, "cefr_j", cefr_j_records(SEEDS))
        self.oewn = stage_snapshot(self.storage, "oewn", oewn or _oewn())
        self.cmudict = stage_snapshot(self.storage, "cmudict", _cmudict())

    def attach(self, *manifests):
        return asyncio.run(
            self.service.attach_snapshots(
                JOB,
                [
                    SnapshotReference(
                        source_id=m.source_name.value,
                        source_version=m.source_version,
                        snapshot_id=m.snapshot_id,
                    )
                    for m in manifests
                ],
                storage=self.storage,
            )
        )

    def generate(self, request=None):
        return asyncio.run(
            self.service.generate(
                JOB, request or _request(), storage_factory=lambda: self.storage
            )
        )


def _vocab(artifact) -> dict:
    return {
        item.word: item
        for item in artifact.courses[0].units[0].lessons[0].vocabulary
    }


def test_references_are_not_loaded_into_the_job_nor_counted_against_its_limit(tmp_path):
    job = Job(tmp_path)

    attached = job.attach(job.seed, job.oewn, job.cmudict)

    assert attached.attached_snapshots == 3
    assert attached.stored_records == len(SEEDS)


def test_planned_words_gain_definition_example_and_ipa_with_provenance(tmp_path):
    job = Job(tmp_path)
    job.attach(job.seed, job.oewn, job.cmudict)

    artifact = job.generate()
    vocab = _vocab(artifact)

    house = vocab["house"]
    # the first (most common) sense, not the shortest gloss
    assert house.definition.startswith("a dwelling that serves as living quarters")
    assert house.example == "he has a house on the lake"
    assert house.pronunciation == "/haʊs/"
    assert {e["source_name"]: e["fields"] for e in house.lineage["enrichment"]} == {
        "cmudict": ["pronunciation"],
        "oewn": ["definition", "example"],
    }
    assert house.source_name == "cefr_j"
    assert house.attribution_text == "The CEFR-J Wordlist Version 1.5"

    dog = vocab["dog"]
    assert dog.example == "the dog barked all night"
    assert dog.pronunciation == "/dɔɡ/"
    oewn_entry = next(e for e in dog.lineage["enrichment"] if e["source_name"] == "oewn")
    assert oewn_entry["snapshot_id"] == job.oewn.snapshot_id
    assert oewn_entry["license_id"] == "CC-BY-4.0"
    assert oewn_entry["attribution_text"] == "Open English WordNet 2025"

    assert vocab["water"].pronunciation == "/wɔtɚ/"
    # Only a pronunciation is known for "light"; its definition stays generated.
    assert vocab["light"].pronunciation == "/laɪt/"
    assert vocab["light"].definition.startswith("An original A1-level")
    assert vocab["happy"].lineage.get("enrichment") is None
    assert vocab["run"].definition == "move fast by using your legs"


def test_manifest_lists_every_pinned_snapshot_and_metrics_report_coverage(tmp_path):
    job = Job(tmp_path)
    job.attach(job.seed, job.oewn, job.cmudict)

    artifact = job.generate()

    assert {m.source_name for m in artifact.source_manifest} == {"cefr_j", "oewn", "cmudict"}
    assert artifact.quality.metrics["enrichment"] == {
        "cmudict": {"matched": 4, "pronunciation": 4},
        "oewn": {"matched": 5, "definition": 5, "example": 4},
    }
    assert artifact.quality.warnings == []


def test_generation_is_deterministic_and_keyed_on_the_enrichment(tmp_path):
    job = Job(tmp_path / "a")
    job.attach(job.seed, job.oewn, job.cmudict)
    first, second = job.generate(), job.generate()

    changed = Job(
        tmp_path / "b",
        oewn=[
            *(r for r in _oewn() if r["word"] != "house"),
            *oewn_senses("house", "noun", [("a home for a family", None)]),
        ],
    )
    changed.attach(changed.seed, changed.oewn, changed.cmudict)

    assert first == second
    assert changed.generate().generation_key != first.generation_key


def test_admin_owned_content_is_never_overwritten_or_mixed_with_a_foreign_example(tmp_path):
    job = Job(tmp_path)
    job.attach(job.oewn, job.cmudict)
    rows = [
        {
            "record_id": f"upload:{word}",
            "word": word,
            "part_of_speech": "noun",
            "declared_cefr": "A1",
            **({"definition": "the place where my family lives"} if word == "house" else {}),
        }
        for word in SEEDS
    ]
    asyncio.run(
        job.service.ingest_records(JOB, SourceRecordBatch(source_name="admin_upload", records=rows))
    )

    artifact = job.generate(_request(sources=["admin_upload", "oewn", "cmudict"]))
    house = _vocab(artifact)["house"]

    assert house.definition == "the place where my family lives"
    assert house.example != "he has a house on the lake"
    assert house.pronunciation == "/haʊs/"
    assert [e["fields"] for e in house.lineage["enrichment"]] == [["pronunciation"]]
    assert {m.source_name for m in artifact.source_manifest} == {"admin_upload", "oewn", "cmudict"}


def test_a_nouns_definition_never_lands_on_a_verb(tmp_path):
    job = Job(tmp_path)
    job.attach(job.oewn)
    rows = [
        {"record_id": f"upload:{w}", "word": w, "part_of_speech": "verb", "declared_cefr": "A1"}
        for w in SEEDS
    ]
    asyncio.run(
        job.service.ingest_records(JOB, SourceRecordBatch(source_name="admin_upload", records=rows))
    )

    artifact = job.generate(_request(sources=["admin_upload", "oewn"]))

    vocab = _vocab(artifact)
    assert vocab["house"].definition.startswith("An original A1-level")
    assert vocab["run"].definition == "move fast by using your legs"
    assert any("matched 1 of 8" in w for w in artifact.quality.warnings)


def test_a_reference_that_matches_nothing_is_flagged_not_silent(tmp_path):
    job = Job(tmp_path, oewn=oewn_senses("zebra", "noun", [("a striped african equine", None)]))
    job.attach(job.seed, job.oewn)

    artifact = job.generate(_request(sources=["cefr_j", "oewn"]))

    assert "oewn matched none of the 8 planned words" in artifact.quality.warnings
    assert "oewn" in {m.source_name for m in artifact.source_manifest}


def test_an_unranked_snapshot_is_not_guessed_from(tmp_path):
    unranked = [
        *oewn_senses("house", "noun", [("a dwelling that serves as living quarters", None)], ranked=False),
        *oewn_senses("dog", "noun", [("informal term for a man", None)], ranked=False),
    ]
    job = Job(tmp_path, oewn=unranked)
    job.attach(job.seed, job.oewn)

    artifact = job.generate(_request(sources=["cefr_j", "oewn"]))

    assert _vocab(artifact)["house"].definition.startswith("An original A1-level")
    assert "oewn matched none of the 8 planned words" in artifact.quality.warnings


def test_without_a_part_of_speech_the_noun_sense_wins_a_tie(tmp_path):
    both = [
        *oewn_senses("run", "verb", [("move fast by using your legs", None)]),
        *oewn_senses("run", "noun", [("a score in baseball made by a runner", None)]),
    ]
    job = Job(tmp_path, oewn=both)
    job.attach(job.seed, job.oewn)

    artifact = job.generate(_request(sources=["cefr_j", "oewn"]))

    assert _vocab(artifact)["run"].definition == "a score in baseball made by a runner"


def test_reference_snapshots_need_storage_to_be_searched(tmp_path):
    job = Job(tmp_path)
    job.attach(job.seed, job.oewn)

    with pytest.raises(RuntimeError, match="ETL storage"):
        asyncio.run(job.service.generate(JOB, _request(sources=["cefr_j", "oewn"])))


def test_find_records_streams_only_requested_words(tmp_path):
    job = Job(tmp_path)

    found = job.storage.find_records("oewn", "2025", {"house", "nothing-here"})

    assert sorted(found) == ["house"]
    assert [r.definition for r in found["house"]].count("a building for people") == 1
    assert job.storage.find_records("oewn", "2025", set()) == {}


@pytest.mark.parametrize(
    ("arpabet", "ipa"),
    [
        ("HH AH0 L OW1", "/həloʊ/"),
        ("R AH1 N", "/rʌn/"),
        ("B ER1 D", "/bɝd/"),
        ("W AO1 T ER0", "/wɔtɚ/"),
        ("CH IY1 Z", "/tʃiz/"),
        ("HH AH L OW", "/həloʊ/"),
    ],
)
def test_arpabet_converts_to_ipa(arpabet, ipa):
    assert arpabet_to_ipa(arpabet) == ipa


@pytest.mark.parametrize("bad", ["", "HH XX L", "hh ah", "HH AH3"])
def test_unknown_or_malformed_arpabet_yields_nothing(bad):
    assert arpabet_to_ipa(bad) is None
