"""Tests for the ETLPipeline: state transitions, quarantine, dedup, and resume."""

from __future__ import annotations

import hashlib
import json

from api.services.content_etl.contracts import (
    SourceRecordV2,
    compute_source_record_checksum,
)
from api.services.content_etl.pipeline import (
    ETLPipeline,
    PipelineReport,
)
from api.services.content_etl.storage import SnapshotStorage


_OEWN_OFFICIAL_URL = "https://en-word.net/static/english-wordnet-2025.xml.gz"
_OEWN_LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"


def _raw_bytes(*records: dict) -> bytes:
    return json.dumps(records, ensure_ascii=False, default=str).encode()


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _make_record(record_id: str, word: str = "test") -> dict:
    return {"record_id": record_id, "word": word, "declared_cefr": "A1"}


def _run_pipeline(storage: SnapshotStorage, records: list[dict], **kwargs) -> PipelineReport:
    raw = _raw_bytes(*records)
    pipeline = ETLPipeline(storage=storage, **kwargs)
    return pipeline.run(
        source_name="oewn",
        source_version="2025",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        raw_records=records,
        raw_bytes=raw,
        official_url=_OEWN_OFFICIAL_URL,
    )


def test_successful_run_transitions_to_approved_and_activates(tmp_path):
    storage = SnapshotStorage(tmp_path)
    records = [_make_record("oewn:2025:1", "journey"), _make_record("oewn:2025:2", "travel")]

    # Stage raw file so write_manifest validation passes.
    raw = _raw_bytes(*records)
    sha = _sha256(raw)
    temp = storage.create_temp_file()
    temp.write_bytes(raw)
    storage.promote_raw(temp, source_name="oewn", version="2025", filename="dataset.xml.gz", sha256=sha)

    pipeline = ETLPipeline(storage=storage)
    report = pipeline.run(
        source_name="oewn",
        source_version="2025",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        raw_records=records,
        raw_bytes=raw,
        official_url=_OEWN_OFFICIAL_URL,
    )

    assert report.status == "approved"
    assert report.extracted == 2
    assert report.normalized == 2
    assert report.approved == 2
    assert report.quarantined == 0
    assert report.activated is True
    assert report.errors == []


def test_dry_run_does_not_write_files(tmp_path):
    storage = SnapshotStorage(tmp_path)
    records = [_make_record("oewn:2025:dry1")]
    raw = _raw_bytes(*records)

    pipeline = ETLPipeline(storage=storage)
    report = pipeline.run(
        source_name="oewn",
        source_version="2025-dry",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        raw_records=records,
        raw_bytes=raw,
        official_url=_OEWN_OFFICIAL_URL,
        dry_run=True,
    )

    assert report.status == "dry_run"
    assert report.activated is False
    assert not (tmp_path / "normalized" / "oewn" / "2025-dry").exists()


def test_quarantine_max_ratio_rejection(tmp_path):
    storage = SnapshotStorage(tmp_path)
    # 5 records, all invalid (no record_id) => quarantine ratio = 100% > 2%
    bad_records = [{"word": f"bad{i}"} for i in range(5)]
    raw = _raw_bytes(*bad_records)

    pipeline = ETLPipeline(storage=storage, max_quarantine_ratio=0.02)
    report = pipeline.run(
        source_name="oewn",
        source_version="2025-q",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        raw_records=bad_records,
        raw_bytes=raw,
        official_url=_OEWN_OFFICIAL_URL,
    )

    assert report.status == "failed"
    assert report.activated is False
    assert any("quarantine" in err.lower() or "ratio" in err.lower() for err in report.errors)


def test_duplicate_record_ids_are_quarantined(tmp_path):
    storage = SnapshotStorage(tmp_path)
    records = [
        _make_record("oewn:dup:1"),
        _make_record("oewn:dup:1"),  # duplicate
        _make_record("oewn:dup:2"),
    ]
    raw = _raw_bytes(*records)
    sha = _sha256(raw)
    temp = storage.create_temp_file()
    temp.write_bytes(raw)
    storage.promote_raw(temp, source_name="oewn", version="2025-dup", filename="dataset.xml.gz", sha256=sha)

    pipeline = ETLPipeline(storage=storage, max_quarantine_ratio=0.5)
    report = pipeline.run(
        source_name="oewn",
        source_version="2025-dup",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        raw_records=records,
        raw_bytes=raw,
        official_url=_OEWN_OFFICIAL_URL,
    )

    assert report.duplicates >= 1
    assert report.quarantined >= 1


def test_deterministic_record_ordering(tmp_path):
    storage = SnapshotStorage(tmp_path)
    records = [
        _make_record("oewn:2025:zzz"),
        _make_record("oewn:2025:aaa"),
        _make_record("oewn:2025:mmm"),
    ]
    raw = _raw_bytes(*records)
    sha = _sha256(raw)
    temp = storage.create_temp_file()
    temp.write_bytes(raw)
    storage.promote_raw(temp, source_name="oewn", version="2025-ord", filename="dataset.xml.gz", sha256=sha)

    pipeline = ETLPipeline(storage=storage)
    report = pipeline.run(
        source_name="oewn",
        source_version="2025-ord",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        raw_records=records,
        raw_bytes=raw,
        official_url=_OEWN_OFFICIAL_URL,
    )

    assert report.status == "approved"
    normalized_path = tmp_path / "normalized" / "oewn" / "2025-ord" / "records.jsonl"
    lines = [json.loads(line) for line in normalized_path.read_bytes().splitlines() if line.strip()]
    ids = [r["record_id"] for r in lines]
    assert ids == sorted(ids)


def test_resume_from_normalized_output(tmp_path):
    storage = SnapshotStorage(tmp_path)
    version = "2025-resume"

    # Manually write normalized output as if a previous run completed normalize stage.
    normalized_dir = tmp_path / "normalized" / "oewn" / version
    normalized_dir.mkdir(parents=True)
    record_payload = {
        "schema_version": 2,
        "record_id": "oewn:resume:1",
        "source_name": "oewn",
        "source_version": version,
        "source_record_id": "oewn:resume:1",
        "source_url": _OEWN_OFFICIAL_URL,
        "license_id": "CC-BY-4.0",
        "license_url": _OEWN_LICENSE_URL,
        "attribution_text": "Open English WordNet 2025",
        "content_usage": "label",
        "language": "en",
        "word": "resume",
        "declared_cefr": "A1",
        "retrieved_at": "2026-06-15T00:00:00Z",
        "raw_checksum": _sha256(b"fake raw dataset"),
        "lineage": {
            "adapter": "oewn",
            "adapter_version": 1,
            "raw_path": "dataset.xml.gz",
            "source_location": "oewn:resume:1",
        },
    }
    record_payload["record_checksum"] = compute_source_record_checksum(record_payload)
    record = SourceRecordV2.model_validate(record_payload).model_dump(mode="json")
    (normalized_dir / "records.jsonl").write_bytes(
        json.dumps(record, ensure_ascii=False, sort_keys=True).encode() + b"\n"
    )

    # Also stage a raw file (needed for manifest validation).
    raw_bytes = b"fake raw dataset"
    raw_sha256 = _sha256(raw_bytes)
    temp = storage.create_temp_file()
    temp.write_bytes(raw_bytes)
    storage.promote_raw(temp, source_name="oewn", version=version, filename="dataset.xml.gz", sha256=raw_sha256)

    pipeline = ETLPipeline(storage=storage)
    report = pipeline.resume_from_normalized(
        source_name="oewn",
        source_version=version,
        license_id="CC-BY-4.0",
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        official_url=_OEWN_OFFICIAL_URL,
        adapter_version=1,
        raw_sha256=raw_sha256,
    )

    assert report.status == "approved"
    assert report.activated is True
    assert report.normalized == 1


def test_failed_run_does_not_activate(tmp_path):
    storage = SnapshotStorage(tmp_path)
    # Pass invalid source to trigger failure.
    pipeline = ETLPipeline(storage=storage)
    report = pipeline.run(
        source_name="oewn",
        source_version="2025-fail",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC0-1.0",  # wrong license for OEWN
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        raw_records=[_make_record("oewn:fail:1")],
        raw_bytes=b"raw",
        official_url=_OEWN_OFFICIAL_URL,
    )

    assert report.status == "failed"
    assert report.activated is False
    assert report.errors


def test_quarantine_ratio_zero_records_does_not_divide_by_zero(tmp_path):
    storage = SnapshotStorage(tmp_path)
    raw = b""
    sha = _sha256(raw)
    temp = storage.create_temp_file()
    temp.write_bytes(raw)
    storage.promote_raw(temp, source_name="oewn", version="2025-empty", filename="dataset.xml.gz", sha256=sha)

    pipeline = ETLPipeline(storage=storage)
    report = pipeline.run(
        source_name="oewn",
        source_version="2025-empty",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url=_OEWN_LICENSE_URL,
        attribution_text="Open English WordNet 2025",
        raw_records=[],
        raw_bytes=raw,
        official_url=_OEWN_OFFICIAL_URL,
    )

    assert report.quarantine_ratio == 0.0
