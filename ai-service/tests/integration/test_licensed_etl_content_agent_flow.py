from __future__ import annotations

import asyncio
import hashlib
import json
from pathlib import Path

import pytest

from api.models.content_agent import GenerationRequest, SnapshotReference
from api.services.content_agent.service import ContentAgentService
from api.services.content_agent.store import ContentAgentStore, RecordLimitExceeded
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


def _stage_cefr_j_snapshot(storage: SnapshotStorage):
    records = [
        {
            "record_id": f"cefr_j:word{index:02d}",
            "word": f"word{index:02d}",
            "part_of_speech": "phrase",
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
        source_name="cefr_j",
        version="2025",
        filename="cefrj-vocabulary-profile-1.5.csv",
        sha256=digest,
    )
    report = ETLPipeline(storage=storage).run(
        source_name="cefr_j",
        source_version="2025",
        adapter_name="cefr_j",
        adapter_version=1,
        license_id="LicenseRef-CEFR-J-Commercial",
        license_url="https://github.com/openlanguageprofiles/olp-en-cefrj",
        attribution_text="The CEFR-J Wordlist Version 1.5",
        raw_records=records,
        raw_bytes=raw,
        official_url="https://github.com/openlanguageprofiles/olp-en-cefrj",
    )
    assert report.status == "approved", report.errors
    return storage.read_active_manifest("cefr_j")


def test_approved_snapshot_attaches_and_generates_deterministically(tmp_path):
    storage = SnapshotStorage(tmp_path)
    manifest = _stage_cefr_j_snapshot(storage)
    store = ContentAgentStore(ttl_seconds=60, max_records=100)
    service = ContentAgentService(store=store)
    job_id = "licensed-flow"

    attached = asyncio.run(
        service.attach_snapshots(
            job_id,
            [
                SnapshotReference(
                    source_id="cefr_j",
                    source_version=manifest.source_version,
                    snapshot_id=manifest.snapshot_id,
                )
            ],
            storage=storage,
        )
    )
    request = GenerationRequest(
        levels=["A1"],
        sources=["cefr_j"],
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
    assert all(item.license_id == "LicenseRef-CEFR-J-Commercial" for item in vocabulary)
    assert all(item.record_checksum and item.lineage for item in vocabulary)

    shared = json.loads(SHARED_FIXTURE.read_text(encoding="utf-8"))
    assert set(first.model_dump(mode="json")) == set(shared)
    assert set(first.source_manifest[0].model_dump(mode="json")) == set(
        shared["source_manifest"][0]
    )
    assert set(vocabulary[0].model_dump(mode="json")) == set(
        shared["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]
    )


def test_snapshot_over_the_job_limit_is_refused_before_reading_any_record(
    tmp_path, monkeypatch
):
    storage = SnapshotStorage(tmp_path)
    manifest = _stage_cefr_j_snapshot(storage)
    service = ContentAgentService(
        store=ContentAgentStore(ttl_seconds=60, max_records=3)
    )

    def unread(*_args, **_kwargs):
        raise AssertionError("records must not be loaded for an oversized snapshot")

    monkeypatch.setattr(SnapshotStorage, "read_normalized_records", unread)

    with pytest.raises(RecordLimitExceeded):
        asyncio.run(
            service.attach_snapshots(
                "too-big",
                [
                    SnapshotReference(
                        source_id="cefr_j",
                        source_version=manifest.source_version,
                        snapshot_id=manifest.snapshot_id,
                    )
                ],
                storage=storage,
            )
        )
