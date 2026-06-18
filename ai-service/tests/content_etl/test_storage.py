from __future__ import annotations

import hashlib
import stat
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime

import pytest

from api.services.content_etl.contracts import (
    SourceManifest,
    canonical_json_bytes,
    compute_record_checksum_root,
    compute_source_record_checksum,
)
from api.services.content_etl.storage import SnapshotStorage, StorageIntegrityError


def _manifest(
    *,
    version: str = "2025",
    status: str = "approved",
    digest: str = "a" * 64,
    normalized_sha256: str = "b" * 64,
    normalized_bytes: int = 1,
    record_checksum_root: str = "c" * 64,
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
        normalized_sha256=normalized_sha256,
        normalized_bytes=normalized_bytes,
        record_checksum_root=record_checksum_root,
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


def _record_payload(
    *,
    version: str,
    raw_checksum: str,
    record_id: str = "oewn:2025:one",
    word: str = "journey",
) -> dict:
    payload = {
        "schema_version": 2,
        "record_id": record_id,
        "source_name": "oewn",
        "source_version": version,
        "source_record_id": record_id,
        "source_url": "https://en-word.net/lemma/journey",
        "license_id": "CC-BY-4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "attribution_text": "Open English WordNet 2025",
        "content_usage": "lexical",
        "language": "en",
        "word": word,
        "part_of_speech": "noun",
        "definition": "A trip from one place to another.",
        "retrieved_at": "2026-06-15T00:00:00Z",
        "raw_checksum": raw_checksum,
        "lineage": {
            "adapter": "oewn",
            "adapter_version": 1,
            "raw_path": "dataset.xml.gz",
            "source_location": record_id,
        },
    }
    payload["record_checksum"] = compute_source_record_checksum(payload)
    return payload


def _stage_complete_snapshot(
    storage: SnapshotStorage,
    *,
    version: str = "2025",
    records: tuple[bytes, ...] | None = None,
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

    normalized_directory = (
        storage.root / "normalized" / "oewn" / version
    )
    normalized_directory.mkdir(parents=True)
    if records is None:
        record_payload = _record_payload(version=version, raw_checksum=digest)
        records = (canonical_json_bytes(record_payload) + b"\n",)
        record_checksums = [record_payload["record_checksum"]]
    else:
        record_checksums = []
    normalized_payload = b"".join(records)
    (normalized_directory / "records.jsonl").write_bytes(normalized_payload)
    if quarantine:
        quarantine_directory = storage.root / "quarantine" / "oewn" / version
        quarantine_directory.mkdir(parents=True)
        (quarantine_directory / "errors.jsonl").write_bytes(
            b"".join(quarantine)
        )
    return _manifest(
        version=version,
        digest=digest,
        normalized_sha256=hashlib.sha256(normalized_payload).hexdigest(),
        normalized_bytes=len(normalized_payload),
        record_checksum_root=compute_record_checksum_root(tuple(record_checksums)),
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


def test_concurrent_manifest_publication_never_replaces_the_winner(tmp_path):
    storage = SnapshotStorage(tmp_path)
    manifest = _stage_complete_snapshot(storage)
    changed = manifest.model_copy(
        update={"attribution_text": "A conflicting concurrent manifest"}
    )

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(storage.write_manifest, candidate)
            for candidate in (manifest, changed)
        ]

    outcomes = []
    for future in futures:
        try:
            outcomes.append(future.result())
        except StorageIntegrityError:
            outcomes.append(None)

    assert sum(outcome is not None for outcome in outcomes) == 1
    stored = storage.read_manifest("oewn", "2025")
    assert stored.attribution_text in {
        manifest.attribution_text,
        changed.attribution_text,
    }


def test_normalized_snapshot_file_cannot_be_replaced(tmp_path):
    storage = SnapshotStorage(tmp_path)
    target = storage.write_snapshot_file(
        kind="normalized",
        source_name="oewn",
        version="2025",
        filename="records.jsonl",
        payload=b'{"record_id":"one"}\n',
    )

    assert target.read_bytes() == b'{"record_id":"one"}\n'
    assert (
        storage.write_snapshot_file(
            kind="normalized",
            source_name="oewn",
            version="2025",
            filename="records.jsonl",
            payload=b'{"record_id":"one"}\n',
        )
        == target
    )
    with pytest.raises(StorageIntegrityError, match="immutable"):
        storage.write_snapshot_file(
            kind="normalized",
            source_name="oewn",
            version="2025",
            filename="records.jsonl",
            payload=b'{"record_id":"changed"}\n',
        )


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
    with pytest.raises(StorageIntegrityError, match="normalized"):
        storage.write_manifest(manifest)

    manifest = _stage_complete_snapshot(storage, version="hash-mismatch")
    bad_hash_manifest = manifest.model_copy(update={"raw_sha256": "b" * 64})
    with pytest.raises(StorageIntegrityError, match="checksum"):
        storage.write_manifest(bad_hash_manifest)


def test_activation_rejects_tampered_normalized_bytes_with_same_line_count(tmp_path):
    storage = SnapshotStorage(tmp_path)
    manifest = _stage_complete_snapshot(storage, version="tamper")
    storage.write_manifest(manifest)
    records_path = tmp_path / "normalized" / "oewn" / "tamper" / "records.jsonl"
    records_path.chmod(0o644)
    records_path.write_bytes(
        records_path.read_bytes().replace(b"journey", b"travelx")
    )

    with pytest.raises(StorageIntegrityError, match="normalized"):
        storage.activate("oewn", "tamper")


def test_approved_manifest_requires_nonempty_normalized_output(tmp_path):
    storage = SnapshotStorage(tmp_path)
    raw_bytes = b"licensed raw dataset"
    digest = hashlib.sha256(raw_bytes).hexdigest()
    temp = storage.create_temp_file()
    temp.write_bytes(raw_bytes)
    storage.promote_raw(
        temp,
        source_name="oewn",
        version="missing-normalized",
        filename="dataset.xml.gz",
        sha256=digest,
    )

    with pytest.raises(StorageIntegrityError, match="normalized"):
        storage.write_manifest(
            _manifest(
                version="missing-normalized",
                digest=digest,
                normalized=1,
            )
        )

    empty_directory = tmp_path / "normalized" / "oewn" / "empty"
    empty_directory.mkdir(parents=True)
    (empty_directory / "records.jsonl").write_bytes(b"")
    temp = storage.create_temp_file()
    temp.write_bytes(raw_bytes)
    storage.promote_raw(
        temp,
        source_name="oewn",
        version="empty",
        filename="dataset.xml.gz",
        sha256=digest,
    )
    with pytest.raises(StorageIntegrityError, match="non-empty"):
        storage.write_manifest(
            _manifest(version="empty", digest=digest, normalized=0)
        )


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
