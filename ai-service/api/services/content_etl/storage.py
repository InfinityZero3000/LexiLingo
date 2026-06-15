"""Immutable local storage for licensed-content snapshots."""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from api.services.content_etl.contracts import SourceManifest, SourceName


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
        os.replace(temp_path, target)
        self._fsync_file(target)
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

        path.parent.mkdir(parents=True, exist_ok=True)
        if manifest.status == "approved":
            self._make_snapshot_read_only(
                manifest.source_name,
                manifest.source_version,
            )
        self._atomic_write(path, payload)
        return path

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

    def read_active(self, source_name: SourceName | str) -> dict[str, Any]:
        source = SourceName(source_name)
        path = self.root / "active" / f"{source.value}.json"
        if not path.is_file():
            raise StorageIntegrityError(
                f"No active snapshot exists for {source.value}"
            )
        return json.loads(path.read_text(encoding="utf-8"))

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
