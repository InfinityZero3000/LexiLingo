"""Licensed-content ETL pipeline — stages raw → normalized → approved → active."""

from __future__ import annotations

import hashlib
import json
import re as _re
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any

from pydantic import ValidationError
from api.services.content_etl.contracts import (
    AllowedLicenseId,
    ContentUsage,
    QuarantineEntry,
    SourceCounts,
    SourceManifest,
    SourceName,
    SourceRecordV2,
    canonical_json_bytes,
    compute_record_checksum_root,
    compute_source_record_checksum,
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


def _jsonl_payload(records: list[dict[str, Any]]) -> bytes:
    return b"".join(canonical_json_bytes(record) + b"\n" for record in records)


def _deterministic_retrieved_at(
    source: SourceName,
    source_version: str,
    raw_sha256: str,
) -> datetime:
    seed = _sha256_bytes(f"{source.value}:{source_version}:{raw_sha256}".encode())
    seconds = int(seed[:12], 16) % (20 * 365 * 24 * 60 * 60)
    return datetime(2020, 1, 1, tzinfo=UTC) + timedelta(seconds=seconds)


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
                get_source_definition(source)
                validated_license = validate_source_license(source, license_id)
            except SourceRegistryError as exc:
                raise PipelineError(str(exc)) from exc

            # Stage 2: Verify artifact checksum.
            raw_sha256 = _sha256_bytes(raw_bytes)
            retrieved_at = _deterministic_retrieved_at(
                source,
                source_version,
                raw_sha256,
            )

            # Stage 3: Adapter normalize + schema validate.
            seen_ids: set[str] = set()
            normalized: list[dict[str, Any]] = []
            quarantine: list[QuarantineEntry] = []

            report.extracted = len(raw_records)

            for idx, record in enumerate(raw_records):
                source_location = f"{source.value}:{source_version}:{idx}"
                try:
                    validated = self._validate_record(
                        record,
                        source=source,
                        source_version=source_version,
                        source_location=source_location,
                        adapter_name=adapter_name,
                        adapter_version=adapter_version,
                        license_id=validated_license,
                        license_url=license_url,
                        attribution_text=attribution_text,
                        official_url=official_url,
                        raw_sha256=raw_sha256,
                        retrieved_at=retrieved_at,
                    )
                    record_id = validated.record_id
                    if record_id in seen_ids:
                        report.duplicates += 1
                        raise ValueError(f"duplicate record_id: {record_id!r}")
                    seen_ids.add(record_id)
                    normalized.append(validated.model_dump(mode="json"))
                except (ValidationError, ValueError, KeyError, TypeError) as exc:
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
            normalized_payload = _jsonl_payload(normalized)
            normalized_sha256 = _sha256_bytes(normalized_payload)
            record_checksum_root = compute_record_checksum_root(
                tuple(str(record["record_checksum"]) for record in normalized)
            )

            # Stage 7: Build quarantine summary.
            for entry in quarantine:
                report.quarantine_summary.by_error_code[entry.error_code] = (
                    report.quarantine_summary.by_error_code.get(entry.error_code, 0) + 1
                )
            report.quarantine_summary.count = report.quarantined

            if dry_run:
                report.status = "dry_run"
                return report
            if report.approved <= 0:
                raise PipelineError("No approved records to publish")

            # Stage 8: Write normalized records and quarantine entries to storage.
            self.storage.write_snapshot_file(
                kind="normalized",
                source_name=source,
                version=source_version,
                filename="records.jsonl",
                payload=normalized_payload,
            )

            if quarantine:
                self.storage.write_snapshot_file(
                    kind="quarantine",
                    source_name=source,
                    version=source_version,
                    filename="errors.jsonl",
                    payload=b"\n".join(
                        entry.model_dump_json().encode() for entry in quarantine
                    )
                    + b"\n",
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
                retrieved_at=retrieved_at,
                raw_sha256=raw_sha256,
                normalized_sha256=normalized_sha256,
                normalized_bytes=len(normalized_payload),
                record_checksum_root=record_checksum_root,
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

            normalized_payload = normalized_path.read_bytes()
            normalized_records: list[dict[str, Any]] = []
            record_checksums: list[str] = []
            for line_number, raw_line in enumerate(
                normalized_payload.decode("utf-8").splitlines(),
                start=1,
            ):
                if not raw_line.strip():
                    continue
                try:
                    payload = json.loads(raw_line)
                    record = SourceRecordV2.model_validate(payload)
                    normalized_records.append(record.model_dump(mode="json"))
                    record_checksums.append(record.record_checksum)
                except (json.JSONDecodeError, ValidationError) as exc:
                    raise PipelineError(
                        f"Invalid normalized record at line {line_number}: {exc}"
                    ) from exc
            if not normalized_records:
                raise PipelineError("Normalized output must contain approved records")
            report.normalized = len(normalized_records)
            report.approved = report.normalized
            normalized_sha256 = _sha256_bytes(normalized_payload)
            record_checksum_root = compute_record_checksum_root(tuple(record_checksums))

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
                retrieved_at=_deterministic_retrieved_at(
                    source,
                    source_version,
                    raw_sha256,
                ),
                raw_sha256=raw_sha256,
                normalized_sha256=normalized_sha256,
                normalized_bytes=len(normalized_payload),
                record_checksum_root=record_checksum_root,
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
        *,
        source: SourceName,
        source_version: str,
        source_location: str,
        adapter_name: str,
        adapter_version: int,
        license_id: AllowedLicenseId,
        license_url: str,
        attribution_text: str,
        official_url: str,
        raw_sha256: str,
        retrieved_at: datetime,
    ) -> SourceRecordV2:
        if not isinstance(record, dict):
            raise TypeError("record must be a dict")
        draft = dict(record)
        if not draft.get("record_id"):
            raise ValueError("record_id is required")
        record_source = str(draft.get("source_name") or source.value)
        if record_source != source.value:
            raise ValueError(
                f"record source_name {record_source!r} does not match "
                f"pipeline source {source.value!r}"
            )
        lineage = dict(draft.get("lineage") or {})
        lineage.setdefault("adapter", adapter_name)
        lineage.setdefault("adapter_version", adapter_version)
        lineage.setdefault("raw_path", "downloaded-artifact")
        lineage.setdefault("source_location", source_location)

        draft.update(
            {
                "schema_version": 2,
                "source_name": source.value,
                "source_version": source_version,
                "source_record_id": str(
                    draft.get("source_record_id")
                    or lineage.get("source_location")
                    or draft["record_id"]
                ),
                "source_url": str(draft.get("source_url") or official_url),
                "license_id": license_id.value,
                "license_url": license_url,
                "attribution_text": attribution_text,
                "content_usage": str(
                    draft.get("content_usage") or _infer_content_usage(draft).value
                ),
                "language": _normalize_language(draft.get("language")),
                "retrieved_at": retrieved_at,
                "raw_checksum": raw_sha256,
                "lineage": lineage,
            }
        )
        draft.pop("checksum", None)
        draft["record_checksum"] = compute_source_record_checksum(draft)
        return SourceRecordV2.model_validate(draft)


def _infer_content_usage(record: dict[str, Any]) -> ContentUsage:
    if record.get("audio"):
        return ContentUsage.AUDIO
    if record.get("pronunciation"):
        return ContentUsage.PRONUNCIATION
    if record.get("declared_cefr"):
        return ContentUsage.LABEL
    if record.get("topic_ids"):
        return ContentUsage.TOPIC
    if record.get("example") and not record.get("definition"):
        return ContentUsage.EXAMPLE
    return ContentUsage.LEXICAL


def _normalize_language(value: Any) -> str:
    normalized = str(value or "en").strip()
    return {"eng": "en"}.get(normalized, normalized)


def _error_code(exc: Exception) -> str:
    name = type(exc).__name__.lower()
    code = _re.sub(r"[^a-z0-9]+", "_", name).strip("_")
    return code[:100] or "unknown_error"
