"""Immutable local storage for licensed-content snapshots."""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from api.services.content_etl.contracts import (
    SourceManifest,
    SourceName,
    SourceRecordV2,
    compute_record_checksum_root,
)


class StorageIntegrityError(ValueError):
    """Raised when an immutable snapshot would be changed or misactivated."""


class SnapshotStorage:
    DIRECTORIES = (
        "raw",
        "normalized",
        "quarantine",
        "manifests",
        "active",
        "tmp",
    )

    def __init__(self, root: str | Path):
        self.root = Path(root)
        for directory in self.DIRECTORIES:
            (self.root / directory).mkdir(parents=True, exist_ok=True)

    @property
    def temp_root(self) -> Path:
        return self.root / "tmp"

    def create_temp_file(self) -> Path:
        descriptor, filename = tempfile.mkstemp(
            prefix="content-etl-",
            suffix=".part",
            dir=self.temp_root,
        )
        os.close(descriptor)
        return Path(filename)

    def promote_raw(
        self,
        temp_path: Path,
        *,
        source_name: SourceName | str,
        version: str,
        filename: str,
        sha256: str,
    ) -> Path:
        source = SourceName(source_name)
        safe_version = self._safe_segment(version, "version")
        safe_filename = self._safe_segment(filename, "filename")
        temp_path = Path(temp_path)
        self._require_temp_path(temp_path)

        actual_sha256 = self._sha256_file(temp_path)
        if actual_sha256 != sha256:
            temp_path.unlink(missing_ok=True)
            raise StorageIntegrityError("Temporary file checksum does not match")

        target_directory = self.root / "raw" / source.value / safe_version
        target = target_directory / safe_filename
        manifest_path = self.manifest_path(source, safe_version)

        if target.exists():
            if self._sha256_file(target) != sha256:
                temp_path.unlink(missing_ok=True)
                raise StorageIntegrityError(
                    "Raw snapshot versions are immutable once promoted"
                )
            temp_path.unlink(missing_ok=True)
            return target

        if manifest_path.exists():
            temp_path.unlink(missing_ok=True)
            raise StorageIntegrityError(
                "Approved snapshot versions are immutable"
            )

        target_directory.mkdir(parents=True, exist_ok=True)
        self._publish_file_no_replace(
            temp_path,
            target,
            expected_sha256=sha256,
        )
        self._fsync_directory(target_directory)
        return target

    def manifest_path(
        self,
        source_name: SourceName | str,
        version: str,
    ) -> Path:
        source = SourceName(source_name)
        safe_version = self._safe_segment(version, "version")
        return self.root / "manifests" / source.value / f"{safe_version}.json"

    def write_manifest(self, manifest: SourceManifest) -> Path:
        path = self.manifest_path(
            manifest.source_name,
            manifest.source_version,
        )
        payload = self._json_bytes(manifest.model_dump(mode="json"))
        if path.exists():
            if path.read_bytes() != payload:
                raise StorageIntegrityError(
                    "Snapshot manifests are immutable by source and version"
                )
            return path

        # Integrity gates only apply to approved manifests.
        if manifest.status == "approved":
            if manifest.counts.approved <= 0:
                raise StorageIntegrityError(
                    "Cannot write manifest: approved snapshot must be non-empty"
                )
            # Gate: raw file must exist and its checksum must match.
            raw_directory = (
                self.root / "raw" / manifest.source_name.value / manifest.source_version
            )
            raw_files = (
                [item for item in raw_directory.glob("*") if item.is_file()]
                if raw_directory.exists()
                else []
            )
            if len(raw_files) != 1:
                raise StorageIntegrityError(
                    "Cannot write manifest: exactly one raw snapshot file is required"
                )
            actual_raw_sha256 = self._sha256_file(raw_files[0])
            if actual_raw_sha256 != manifest.raw_sha256:
                raise StorageIntegrityError(
                    "Cannot write manifest: raw file checksum does not match"
                )

            # Gate: normalized bytes, schema, provenance, count, and checksum
            # root must all match the immutable manifest.
            self._verify_normalized_output(manifest)

            # Gate: quarantine file must exist when counts.quarantined > 0.
            if manifest.counts.quarantined > 0:
                quarantine_path = (
                    self.root
                    / "quarantine"
                    / manifest.source_name.value
                    / manifest.source_version
                    / "errors.jsonl"
                )
                if not quarantine_path.exists():
                    raise StorageIntegrityError(
                        "Cannot write manifest: quarantine file is missing"
                    )
                quarantine_count = sum(
                    1 for line in quarantine_path.read_bytes().splitlines() if line
                )
                if quarantine_count != manifest.counts.quarantined:
                    raise StorageIntegrityError(
                        "Cannot write manifest: quarantine record count does not match"
                    )

        path.parent.mkdir(parents=True, exist_ok=True)
        if manifest.status == "approved":
            self._make_snapshot_read_only(
                manifest.source_name,
                manifest.source_version,
            )
        self._atomic_write_no_replace(path, payload)
        return path

    def write_snapshot_file(
        self,
        *,
        kind: str,
        source_name: SourceName | str,
        version: str,
        filename: str,
        payload: bytes,
    ) -> Path:
        if kind not in {"normalized", "quarantine"}:
            raise StorageIntegrityError(
                "Snapshot files may only be written to normalized or quarantine"
            )
        source = SourceName(source_name)
        safe_version = self._safe_segment(version, "version")
        safe_filename = self._safe_segment(filename, "filename")
        if self.manifest_path(source, safe_version).exists():
            raise StorageIntegrityError(
                "Approved snapshot versions are immutable"
            )
        target = (
            self.root / kind / source.value / safe_version / safe_filename
        )
        self._atomic_write_no_replace(target, payload)
        return target

    def read_manifest(
        self,
        source_name: SourceName | str,
        version: str,
    ) -> SourceManifest:
        path = self.manifest_path(source_name, version)
        if not path.is_file():
            raise StorageIntegrityError(
                f"Snapshot manifest does not exist: {path.name}"
            )
        return SourceManifest.model_validate_json(path.read_bytes())

    def activate(
        self,
        source_name: SourceName | str,
        version: str,
    ) -> Path:
        manifest = self.read_manifest(source_name, version)
        if manifest.status != "approved":
            raise StorageIntegrityError(
                "Only approved snapshot manifests can be activated"
            )
        self._verify_approved_snapshot(manifest)

        active_path = self.root / "active" / f"{manifest.source_name.value}.json"
        payload = self._json_bytes(
            {
                "schema_version": 1,
                "snapshot_id": manifest.snapshot_id,
                "source_name": manifest.source_name.value,
                "source_version": manifest.source_version,
                "manifest_path": str(
                    self.manifest_path(
                        manifest.source_name,
                        manifest.source_version,
                    ).relative_to(self.root)
                ),
            }
        )
        self._atomic_write(active_path, payload)
        return active_path

    def _verify_approved_snapshot(self, manifest: SourceManifest) -> None:
        if manifest.counts.approved <= 0:
            raise StorageIntegrityError("Approved snapshot must be non-empty")
        raw_directory = (
            self.root
            / "raw"
            / manifest.source_name.value
            / manifest.source_version
        )
        raw_files = [path for path in raw_directory.glob("*") if path.is_file()]
        if len(raw_files) != 1:
            raise StorageIntegrityError(
                "Approved snapshot must contain exactly one raw artifact"
            )
        if self._sha256_file(raw_files[0]) != manifest.raw_sha256:
            raise StorageIntegrityError("Approved snapshot raw checksum changed")
        self._verify_normalized_output(manifest)

    def _normalized_path(self, manifest: SourceManifest) -> Path:
        return (
            self.root
            / "normalized"
            / manifest.source_name.value
            / manifest.source_version
            / "records.jsonl"
        )

    def _verify_normalized_output(
        self,
        manifest: SourceManifest,
    ) -> list[dict[str, Any]]:
        normalized_path = self._normalized_path(manifest)
        if not normalized_path.is_file():
            raise StorageIntegrityError("Approved snapshot normalized output is missing")

        payload = normalized_path.read_bytes()
        if len(payload) != manifest.normalized_bytes:
            raise StorageIntegrityError(
                "Approved snapshot normalized byte length changed"
            )
        if self._sha256_bytes(payload) != manifest.normalized_sha256:
            raise StorageIntegrityError("Approved snapshot normalized checksum changed")

        records: list[dict[str, Any]] = []
        record_checksums: list[str] = []
        for line_number, line in enumerate(payload.splitlines(), start=1):
            if not line.strip():
                continue
            try:
                record = SourceRecordV2.model_validate_json(line)
            except (ValueError, ValidationError) as exc:
                raise StorageIntegrityError(
                    f"Approved snapshot has invalid normalized record at "
                    f"line {line_number}"
                ) from exc
            if (
                record.source_name != manifest.source_name
                or record.source_version != manifest.source_version
                or record.raw_checksum != manifest.raw_sha256
            ):
                raise StorageIntegrityError(
                    "Approved snapshot normalized provenance changed"
                )
            records.append(record.model_dump(mode="json"))
            record_checksums.append(record.record_checksum)

        if not records:
            raise StorageIntegrityError(
                "Approved snapshot normalized output must be non-empty"
            )
        if len(records) != manifest.counts.normalized:
            raise StorageIntegrityError(
                "Approved snapshot normalized record count changed"
            )
        if compute_record_checksum_root(tuple(record_checksums)) != (
            manifest.record_checksum_root
        ):
            raise StorageIntegrityError(
                "Approved snapshot normalized record checksum root changed"
            )
        return records

    def read_active(self, source_name: SourceName | str) -> dict[str, Any]:
        source = SourceName(source_name)
        path = self.root / "active" / f"{source.value}.json"
        if not path.is_file():
            raise StorageIntegrityError(
                f"No active snapshot exists for {source.value}"
            )
        return json.loads(path.read_text(encoding="utf-8"))

    def read_active_manifest(
        self,
        source_name: SourceName | str,
    ) -> SourceManifest:
        active = self.read_active(source_name)
        manifest = self.read_manifest(
            active["source_name"],
            active["source_version"],
        )
        if manifest.snapshot_id != active.get("snapshot_id"):
            raise StorageIntegrityError("Active pointer snapshot_id does not match")
        self._verify_approved_snapshot(manifest)
        return manifest

    def list_active_manifests(self) -> list[SourceManifest]:
        manifests: list[SourceManifest] = []
        for pointer in sorted((self.root / "active").glob("*.json")):
            manifests.append(self.read_active_manifest(pointer.stem))
        return manifests

    def read_normalized_records(
        self,
        source_name: SourceName | str,
        version: str,
    ) -> list[dict[str, Any]]:
        source = SourceName(source_name)
        manifest = self.read_manifest(source, version)
        self._verify_approved_snapshot(manifest)
        return self._verify_normalized_output(manifest)

    def _make_snapshot_read_only(
        self,
        source_name: SourceName,
        version: str,
    ) -> None:
        for kind in ("raw", "normalized", "quarantine"):
            directory = self.root / kind / source_name.value / version
            if not directory.exists():
                continue
            for path in sorted(
                directory.rglob("*"),
                key=lambda item: len(item.parts),
                reverse=True,
            ):
                path.chmod(0o555 if path.is_dir() else 0o444)
            directory.chmod(0o555)

    def _atomic_write(self, target: Path, payload: bytes) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temp_name = tempfile.mkstemp(
            prefix=f".{target.name}.",
            suffix=".part",
            dir=target.parent,
        )
        temp_path = Path(temp_name)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(payload)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_path, target)
            self._fsync_directory(target.parent)
        finally:
            temp_path.unlink(missing_ok=True)

    def _atomic_write_no_replace(self, target: Path, payload: bytes) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            if target.read_bytes() != payload:
                raise StorageIntegrityError(
                    "Snapshot files are immutable by source and version"
                )
            return
        descriptor, temp_name = tempfile.mkstemp(
            prefix=f".{target.name}.",
            suffix=".part",
            dir=target.parent,
        )
        temp_path = Path(temp_name)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(payload)
                handle.flush()
                os.fsync(handle.fileno())
            try:
                os.link(temp_path, target)
            except FileExistsError:
                if target.read_bytes() != payload:
                    raise StorageIntegrityError(
                        "Snapshot manifests are immutable by source and version"
                    )
            self._fsync_directory(target.parent)
        finally:
            temp_path.unlink(missing_ok=True)

    def _publish_file_no_replace(
        self,
        temp_path: Path,
        target: Path,
        *,
        expected_sha256: str,
    ) -> None:
        self._fsync_file(temp_path)
        try:
            os.link(temp_path, target)
        except FileExistsError:
            if self._sha256_file(target) != expected_sha256:
                raise StorageIntegrityError(
                    "Raw snapshot versions are immutable once promoted"
                )
        finally:
            temp_path.unlink(missing_ok=True)
        self._fsync_file(target)

    def _require_temp_path(self, path: Path) -> None:
        try:
            path.resolve().relative_to(self.temp_root.resolve())
        except ValueError as exc:
            raise StorageIntegrityError(
                "Only ETL temporary files can be promoted"
            ) from exc

    @staticmethod
    def _safe_segment(value: str, label: str) -> str:
        normalized = value.strip()
        if (
            not normalized
            or normalized in {".", ".."}
            or "/" in normalized
            or "\\" in normalized
            or "\x00" in normalized
        ):
            raise StorageIntegrityError(f"Invalid snapshot {label}")
        return normalized

    @staticmethod
    def _sha256_bytes(payload: bytes) -> str:
        return hashlib.sha256(payload).hexdigest()

    @staticmethod
    def _sha256_file(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()

    @staticmethod
    def _json_bytes(payload: dict[str, Any]) -> bytes:
        return (
            json.dumps(
                payload,
                ensure_ascii=True,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
            + b"\n"
        )

    @staticmethod
    def _fsync_file(path: Path) -> None:
        with path.open("rb") as handle:
            os.fsync(handle.fileno())

    @staticmethod
    def _fsync_directory(path: Path) -> None:
        descriptor = os.open(path, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
