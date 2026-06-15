from __future__ import annotations

import hashlib
import stat
from datetime import UTC, datetime

import pytest

from api.services.content_etl.contracts import SourceManifest
from api.services.content_etl.storage import SnapshotStorage, StorageIntegrityError


def _manifest(
    *,
    version: str = "2025",
    status: str = "approved",
    digest: str = "a" * 64,
    normalized: int = 1,
    quarantined: int = 0,
) -> SourceManifest:
    return SourceManifest(
        snapshot_id=f"oewn:{version}:{digest}",
        source_name="oewn",
        source_version=version,
        official_url="https://en-word.net/static/english-wordnet-2025.xml.gz",
        license_id="CC-BY-4.0",
        license_url="https://creativecommons.org/licenses/by/4.0/",
        attribution_text="Open English WordNet 2025",
        retrieved_at=datetime(2026, 6, 15, tzinfo=UTC),
        raw_sha256=digest,
        adapter_version=1,
        status=status,
        counts={
            "extracted": normalized + quarantined,
            "normalized": normalized,
            "approved": normalized if status == "approved" else 0,
            "quarantined": quarantined,
            "duplicates": 0,
        },
    )


def _stage_complete_snapshot(
    storage: SnapshotStorage,
    *,
    version: str = "2025",
    records: tuple[bytes, ...] = (b'{"record_id":"one"}\n',),
    quarantine: tuple[bytes, ...] = (),
) -> SourceManifest:
    raw_bytes = b"licensed raw dataset"
    digest = hashlib.sha256(raw_bytes).hexdigest()
    temp = storage.create_temp_file()
    temp.write_bytes(raw_bytes)
    storage.promote_raw(
        temp,
        source_name="oewn",
        version=version,
        filename="dataset.xml.gz",
        sha256=digest,
    )

    normalized_directory = tmp_path = (
        storage.root / "normalized" / "oewn" / version
    )
    normalized_directory.mkdir(parents=True)
    (normalized_directory / "records.jsonl").write_bytes(b"".join(records))
    if quarantine:
        quarantine_directory = storage.root / "quarantine" / "oewn" / version
        quarantine_directory.mkdir(parents=True)
        (quarantine_directory / "errors.jsonl").write_bytes(
            b"".join(quarantine)
        )
    return _manifest(
        version=version,
        digest=digest,
        normalized=len(records),
        quarantined=len(quarantine),
    )


def test_storage_creates_expected_snapshot_layout(tmp_path):
    SnapshotStorage(tmp_path)

    for directory in (
        "raw",
        "normalized",
        "quarantine",
        "manifests",
        "active",
        "tmp",
    ):
        assert (tmp_path / directory).is_dir()


def test_raw_promotion_is_idempotent_but_rejects_changed_bytes(tmp_path):
    storage = SnapshotStorage(tmp_path)
    first = storage.create_temp_file()
    first.write_bytes(b"same")
    digest = hashlib.sha256(b"same").hexdigest()

    target = storage.promote_raw(
        first,
        source_name="oewn",
        version="2025",
        filename="dataset.xml.gz",
        sha256=digest,
    )
    assert target.read_bytes() == b"same"

    duplicate = storage.create_temp_file()
    duplicate.write_bytes(b"same")
    assert (
        storage.promote_raw(
            duplicate,
            source_name="oewn",
            version="2025",
            filename="dataset.xml.gz",
            sha256=digest,
        )
        == target
    )
    assert not duplicate.exists()

    changed = storage.create_temp_file()
    changed.write_bytes(b"changed")
    with pytest.raises(StorageIntegrityError, match="immutable"):
        storage.promote_raw(
            changed,
            source_name="oewn",
            version="2025",
            filename="dataset.xml.gz",
            sha256=hashlib.sha256(b"changed").hexdigest(),
        )
    assert target.read_bytes() == b"same"


def test_manifest_is_written_last_and_activation_requires_approved_status(tmp_path):
    storage = SnapshotStorage(tmp_path)
    approved = _stage_complete_snapshot(storage)
    manifest_path = storage.write_manifest(approved)

    active_path = storage.activate("oewn", "2025")
    assert active_path == tmp_path / "active" / "oewn.json"
    assert storage.read_active("oewn")["snapshot_id"] == approved.snapshot_id
    assert manifest_path.is_file()
    assert list((tmp_path / "active").glob("*.part")) == []

    rejected = _manifest(version="rejected", status="rejected")
    storage.write_manifest(rejected)
    with pytest.raises(StorageIntegrityError, match="approved"):
        storage.activate("oewn", "rejected")


def test_manifest_version_is_immutable(tmp_path):
    storage = SnapshotStorage(tmp_path)
    manifest = _stage_complete_snapshot(storage)
    storage.write_manifest(manifest)

    changed = manifest.model_copy(
        update={"attribution_text": "Changed attribution"}
    )
    with pytest.raises(StorageIntegrityError, match="immutable"):
        storage.write_manifest(changed)


def test_approved_manifest_is_written_after_snapshot_becomes_read_only(tmp_path):
    storage = SnapshotStorage(tmp_path)
    manifest = _stage_complete_snapshot(storage)
    raw_directory = tmp_path / "raw" / "oewn" / "2025"
    raw_file = raw_directory / "dataset.xml.gz"

    manifest_path = storage.write_manifest(manifest)

    assert manifest_path.exists()
    assert raw_file.stat().st_mode & stat.S_IWUSR == 0
    assert raw_directory.stat().st_mode & stat.S_IWUSR == 0


def test_approved_manifest_requires_complete_checksum_matched_snapshot(tmp_path):
    storage = SnapshotStorage(tmp_path)
    with pytest.raises(StorageIntegrityError, match="raw"):
        storage.write_manifest(_manifest())

    manifest = _stage_complete_snapshot(storage, version="count-mismatch")
    records_path = (
        tmp_path / "normalized" / "oewn" / "count-mismatch" / "records.jsonl"
    )
    records_path.write_bytes(b"")
    with pytest.raises(StorageIntegrityError, match="record count"):
        storage.write_manifest(manifest)

    manifest = _stage_complete_snapshot(storage, version="hash-mismatch")
    bad_hash_manifest = manifest.model_copy(update={"raw_sha256": "b" * 64})
    with pytest.raises(StorageIntegrityError, match="checksum"):
        storage.write_manifest(bad_hash_manifest)


def test_quarantined_count_requires_matching_error_records(tmp_path):
    storage = SnapshotStorage(tmp_path)
    manifest = _stage_complete_snapshot(
        storage,
        version="quarantine",
        quarantine=(b'{"error_code":"invalid"}\n',),
    )
    (tmp_path / "quarantine" / "oewn" / "quarantine" / "errors.jsonl").unlink()

    with pytest.raises(StorageIntegrityError, match="quarantine"):
        storage.write_manifest(manifest)
