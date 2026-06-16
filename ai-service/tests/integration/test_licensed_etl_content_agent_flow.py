from __future__ import annotations

import asyncio
import hashlib
import json
from pathlib import Path

from api.models.content_agent import GenerationRequest, SnapshotReference
from api.services.content_agent.service import ContentAgentService
from api.services.content_agent.store import ContentAgentStore
from api.services.content_etl.pipeline import ETLPipeline
from api.services.content_etl.storage import SnapshotStorage


REPO_ROOT = Path(__file__).resolve().parents[3]
SHARED_FIXTURE = (
    REPO_ROOT
    / "contracts"
    / "content-agent"
    / "fixtures"
    / "licensed-etl-artifact-v2.json"
)


def _stage_oewn_snapshot(storage: SnapshotStorage):
    records = [
        {
            "record_id": f"oewn:2025:{index}",
            "source_record_id": f"oewn-entry-{index}",
            "source_url": f"https://en-word.net/lemma/word{index:02d}",
            "word": f"word{index:02d}",
            "part_of_speech": "noun",
            "definition": f"A licensed lexical definition for word {index}.",
            "declared_cefr": "A1",
            "topic_ids": ["daily_life"],
        }
        for index in range(8)
    ]
    raw = json.dumps(records, sort_keys=True).encode("utf-8")
    digest = hashlib.sha256(raw).hexdigest()
    temp = storage.create_temp_file()
    temp.write_bytes(raw)
    storage.promote_raw(
        temp,
        source_name="oewn",
        version="2025",
        filename="english-wordnet-2025.json",
        sha256=digest,
    )
    report = ETLPipeline(storage=storage).run(
        source_name="oewn",
        source_version="2025",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url="https://creativecommons.org/licenses/by/4.0/",
        attribution_text="Open English WordNet 2025",
        raw_records=records,
        raw_bytes=raw,
        official_url="https://en-word.net/static/english-wordnet-2025.xml.gz",
    )
    assert report.status == "approved"
    return storage.read_active_manifest("oewn")


def test_approved_snapshot_attaches_and_generates_deterministically(tmp_path):
    storage = SnapshotStorage(tmp_path)
    manifest = _stage_oewn_snapshot(storage)
    store = ContentAgentStore(ttl_seconds=60, max_records=100)
    service = ContentAgentService(store=store)
    job_id = "licensed-flow"

    attached = asyncio.run(
        service.attach_snapshots(
            job_id,
            [
                SnapshotReference(
                    source_id="oewn",
                    source_version=manifest.source_version,
                    snapshot_id=manifest.snapshot_id,
                )
            ],
            storage=storage,
        )
    )
    request = GenerationRequest(
        levels=["A1"],
        sources=["oewn"],
        units_per_course=1,
        lessons_per_unit=1,
        words_per_lesson=8,
        exercises_per_lesson=4,
        exercise_mix={"speaking": 1, "listening": 1},
    )
    first = asyncio.run(service.generate(job_id, request))
    second = asyncio.run(service.generate(job_id, request))

    assert attached.attached_snapshots == 1
    assert attached.stored_records == 8
    assert first == second
    assert first.source_manifest[0].snapshot_id == manifest.snapshot_id
    assert first.source_manifest[0].raw_checksum == manifest.raw_sha256
    vocabulary = first.courses[0].units[0].lessons[0].vocabulary
    assert len(vocabulary) == 8
    assert all(item.source_version == "2025" for item in vocabulary)
    assert all(item.license_id == "CC-BY-4.0" for item in vocabulary)
    assert all(item.record_checksum and item.lineage for item in vocabulary)

    shared = json.loads(SHARED_FIXTURE.read_text(encoding="utf-8"))
    assert set(first.model_dump(mode="json")) == set(shared)
    assert set(first.source_manifest[0].model_dump(mode="json")) == set(
        shared["source_manifest"][0]
    )
    assert set(vocabulary[0].model_dump(mode="json")) == set(
        shared["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]
    )
