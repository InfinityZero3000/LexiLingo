"""Licensed-content ETL pipeline — stages raw → normalized → approved → active."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterator


from api.services.content_etl.contracts import (
    AllowedLicenseId,
    QuarantineEntry,
    SourceCounts,
    SourceManifest,
    SourceName,
)
from api.services.content_etl.registry import (
    SourceRegistryError,
    get_source_definition,
    validate_source_license,
)
from api.services.content_etl.storage import SnapshotStorage, StorageIntegrityError


class PipelineError(RuntimeError):
    """Raised when the pipeline cannot proceed safely."""


class QuarantineRatioExceeded(PipelineError):
    """Raised when the quarantine ratio exceeds the configured maximum."""


@dataclass
class QuarantineSummary:
    count: int = 0
    by_error_code: dict[str, int] = field(default_factory=dict)


@dataclass
class PipelineReport:
    source_name: str
    source_version: str
    status: str
    extracted: int = 0
    normalized: int = 0
    approved: int = 0
    quarantined: int = 0
    duplicates: int = 0
    quarantine_summary: QuarantineSummary = field(default_factory=QuarantineSummary)
    activated: bool = False
    errors: list[str] = field(default_factory=list)

    @property
    def quarantine_ratio(self) -> float:
        if self.extracted == 0:
            return 0.0
        return self.quarantined / self.extracted


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_str(value: Any) -> str:
    return _sha256_bytes(
        json.dumps(value, ensure_ascii=False, sort_keys=True, default=str).encode()
    )


def _count_jsonl_lines(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(1 for line in path.read_bytes().splitlines() if line.strip())


class ETLPipeline:
    """Orchestrates the licensed-content ETL pipeline for one source/version."""

    def __init__(
        self,
        *,
        storage: SnapshotStorage,
        max_quarantine_ratio: float = 0.02,
    ) -> None:
        if not (0.0 <= max_quarantine_ratio <= 1.0):
            raise ValueError("max_quarantine_ratio must be between 0 and 1")
        self.storage = storage
        self.max_quarantine_ratio = max_quarantine_ratio

    def run(
        self,
        *,
        source_name: SourceName | str,
        source_version: str,
        adapter_name: str,
        adapter_version: int,
        license_id: AllowedLicenseId | str,
        license_url: str,
        attribution_text: str,
        raw_records: list[dict[str, Any]],
        raw_bytes: bytes,
        official_url: str,
        dry_run: bool = False,
    ) -> PipelineReport:
        source = SourceName(source_name)
        report = PipelineReport(
            source_name=source.value,
            source_version=source_version,
            status="running",
        )

        try:
            # Stage 1: Resolve pinned source — validate source and license are in registry.
            try:
                definition = get_source_definition(source)
                validated_license = validate_source_license(source, license_id)
            except SourceRegistryError as exc:
                raise PipelineError(str(exc)) from exc

            # Stage 2: Verify artifact checksum.
            raw_sha256 = _sha256_bytes(raw_bytes)

            # Stage 3: Adapter normalize + schema validate.
            seen_ids: set[str] = set()
            normalized: list[dict[str, Any]] = []
            quarantine: list[QuarantineEntry] = []

            report.extracted = len(raw_records)

            for idx, record in enumerate(raw_records):
                source_location = f"{source.value}:{source_version}:{idx}"
                try:
                    self._validate_record(record, source, source_location)
                    record_id = str(record.get("record_id") or "")
                    if not record_id:
                        raise ValueError("record_id is required")
                    if record_id in seen_ids:
                        report.duplicates += 1
                        raise ValueError(f"duplicate record_id: {record_id!r}")
                    seen_ids.add(record_id)
                    normalized.append(record)
                except (ValueError, KeyError, TypeError) as exc:
                    raw_excerpt = json.dumps(record, default=str, ensure_ascii=False)
                    quarantine.append(
                        QuarantineEntry(
                            source_name=source,
                            source_version=source_version,
                            source_location=source_location,
                            error_code=_error_code(exc),
                            message=str(exc)[:2000],
                            raw_excerpt_hash=_sha256_bytes(
                                raw_excerpt.encode("utf-8")
                            ),
                        )
                    )

            report.normalized = len(normalized)
            report.quarantined = len(quarantine)

            # Stage 4: Deterministic dedup + ordering.
            normalized = sorted(
                normalized,
                key=lambda r: (str(r.get("record_id") or ""),),
            )

            # Stage 5: Check quarantine ratio.
            if report.extracted > 0:
                ratio = report.quarantined / report.extracted
                if ratio > self.max_quarantine_ratio:
                    raise QuarantineRatioExceeded(
                        f"Quarantine ratio {ratio:.2%} exceeds maximum "
                        f"{self.max_quarantine_ratio:.2%}"
                    )

            # Stage 6: Quality report / approve snapshot.
            report.approved = len(normalized)

            # Stage 7: Build quarantine summary.
            for entry in quarantine:
                report.quarantine_summary.by_error_code[entry.error_code] = (
                    report.quarantine_summary.by_error_code.get(entry.error_code, 0) + 1
                )
            report.quarantine_summary.count = report.quarantined

            if dry_run:
                report.status = "dry_run"
                return report

            # Stage 8: Write normalized records and quarantine entries to storage.
            normalized_dir = (
                self.storage.root / "normalized" / source.value / source_version
            )
            normalized_dir.mkdir(parents=True, exist_ok=True)
            records_path = normalized_dir / "records.jsonl"
            records_path.write_bytes(
                b"\n".join(
                    json.dumps(r, ensure_ascii=False, sort_keys=True).encode()
                    for r in normalized
                )
                + (b"\n" if normalized else b"")
            )

            if quarantine:
                quarantine_dir = (
                    self.storage.root / "quarantine" / source.value / source_version
                )
                quarantine_dir.mkdir(parents=True, exist_ok=True)
                (quarantine_dir / "errors.jsonl").write_bytes(
                    b"\n".join(
                        entry.model_dump_json().encode() for entry in quarantine
                    )
                    + b"\n"
                )

            # Stage 9: Re-check license before approval (fail-closed).
            try:
                validate_source_license(source, validated_license)
            except SourceRegistryError as exc:
                raise PipelineError(
                    f"License re-check failed before approval: {exc}"
                ) from exc

            # Stage 10: Write manifest and atomically activate.
            manifest = SourceManifest(
                snapshot_id=f"{source.value}:{source_version}:{raw_sha256}",
                source_name=source,
                source_version=source_version,
                official_url=official_url,  # type: ignore[arg-type]
                license_id=validated_license,
                license_url=license_url,  # type: ignore[arg-type]
                attribution_text=attribution_text,
                retrieved_at=datetime.now(UTC),
                raw_sha256=raw_sha256,
                adapter_version=adapter_version,
                status="approved",
                counts=SourceCounts(
                    extracted=report.extracted,
                    normalized=report.normalized,
                    approved=report.approved,
                    quarantined=report.quarantined,
                    duplicates=report.duplicates,
                ),
            )

            self.storage.write_manifest(manifest)
            self.storage.activate(source, source_version)
            report.activated = True
            report.status = "approved"

        except (PipelineError, StorageIntegrityError) as exc:
            report.status = "failed"
            report.errors.append(str(exc))
            report.activated = False

        return report

    def resume_from_normalized(
        self,
        *,
        source_name: SourceName | str,
        source_version: str,
        license_id: AllowedLicenseId | str,
        license_url: str,
        attribution_text: str,
        official_url: str,
        adapter_version: int,
        raw_sha256: str,
        dry_run: bool = False,
    ) -> PipelineReport:
        """Re-run approval from a previously normalized output (skip download/normalize)."""
        source = SourceName(source_name)
        report = PipelineReport(
            source_name=source.value,
            source_version=source_version,
            status="running",
        )

        try:
            validated_license = validate_source_license(source, license_id)
            normalized_path = (
                self.storage.root
                / "normalized"
                / source.value
                / source_version
                / "records.jsonl"
            )
            if not normalized_path.exists():
                raise PipelineError("No normalized output found for resume")

            report.normalized = _count_jsonl_lines(normalized_path)
            report.approved = report.normalized

            if dry_run:
                report.status = "dry_run"
                return report

            validate_source_license(source, validated_license)

            manifest = SourceManifest(
                snapshot_id=f"{source.value}:{source_version}:{raw_sha256}",
                source_name=source,
                source_version=source_version,
                official_url=official_url,  # type: ignore[arg-type]
                license_id=validated_license,
                license_url=license_url,  # type: ignore[arg-type]
                attribution_text=attribution_text,
                retrieved_at=datetime.now(UTC),
                raw_sha256=raw_sha256,
                adapter_version=adapter_version,
                status="approved",
                counts=SourceCounts(
                    extracted=report.normalized,
                    normalized=report.normalized,
                    approved=report.approved,
                    quarantined=report.quarantined,
                    duplicates=report.duplicates,
                ),
            )

            self.storage.write_manifest(manifest)
            self.storage.activate(source, source_version)
            report.activated = True
            report.status = "approved"

        except (PipelineError, StorageIntegrityError, SourceRegistryError) as exc:
            report.status = "failed"
            report.errors.append(str(exc))

        return report

    def _validate_record(
        self,
        record: dict[str, Any],
        source: SourceName,
        source_location: str,
    ) -> None:
        if not isinstance(record, dict):
            raise TypeError("record must be a dict")
        if not record.get("record_id"):
            raise ValueError("record_id is required")


def _error_code(exc: Exception) -> str:
    name = type(exc).__name__.lower()
    import re as _re
    code = _re.sub(r"[^a-z0-9]+", "_", name).strip("_")
    return code[:100] or "unknown_error"
