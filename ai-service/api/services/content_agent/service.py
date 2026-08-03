"""Content-agent ingestion and generation orchestration."""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from datetime import UTC, datetime, timedelta

from api.models.content_agent import (
    ArtifactSourceManifest,
    ContentAgentArtifact,
    GenerationRequest,
    QualityArtifact,
    RecordBatchResponse,
    SnapshotAttachmentResponse,
    SnapshotReference,
    SourceSnapshotDescriptor,
    SourceRecordBatch,
)
from api.services.content_agent.adapters import (
    normalize_etl_records,
    normalize_source_records,
)
from api.services.content_agent.generator import (
    CourseGenerator,
    DeterministicCourseGenerator,
)
from api.services.content_agent.planner import plan_curriculum
from api.services.content_agent.policies import find_missing_production_exercise_lessons
from api.services.content_agent.store import ContentAgentStore
from api.services.content_etl.contracts import SourceRecordV2
from api.services.content_etl.registry import get_source_definition
from api.services.content_etl.storage import SnapshotStorage, StorageIntegrityError


class JobContextNotFound(LookupError):
    """Raised when a job context is absent or expired."""


class ContentAgentService:
    def __init__(
        self,
        *,
        store: ContentAgentStore,
        generator: CourseGenerator | None = None,
    ) -> None:
        self.store = store
        self.generator = generator or DeterministicCourseGenerator()

    async def ingest_records(
        self,
        job_id: str,
        batch: SourceRecordBatch,
    ) -> RecordBatchResponse:
        # existing_cefr records may only be loaded from an approved ETL snapshot,
        # never ingested directly through the batch API.
        effective_source = batch.source_name or ""
        record_sources = {
            str(rec.get("source_name") or effective_source).strip().lower()
            for rec in batch.records
        }
        if effective_source.strip().lower() != "admin_upload" or record_sources != {
            "admin_upload"
        }:
            raise ValueError(
                "Licensed dataset records must be loaded from an approved snapshot; "
                "only admin_upload may use direct ingestion"
            )
        normalized = normalize_source_records(
            batch.records,
            source_name=batch.source_name,
        )
        stored_records = await self.store.append(job_id, normalized)
        return RecordBatchResponse(
            accepted_records=len(normalized),
            stored_records=stored_records,
        )

    async def generate(
        self,
        job_id: str,
        request: GenerationRequest,
    ) -> ContentAgentArtifact:
        records = await self.store.get(job_id) or []
        if request.sources is not None:
            selected_sources = set(request.sources)
            records = [
                record for record in records if record.source_name in selected_sources
            ]
        if not records:
            raise JobContextNotFound(
                f"Content-agent job context not found or expired: {job_id}"
            )

        records = [
            record.model_copy(
                update={
                    "source_version": record.source_version or "job-upload-v1",
                    "source_record_id": record.source_record_id or record.record_id,
                    "license_id": record.license_id or "LicenseRef-Admin-Owned",
                    "license_url": (
                        record.license_url
                        or "https://lexilingo.me/legal/content-upload-rights"
                    ),
                    "attribution_text": (
                        record.attribution_text
                        or "Administrator-owned or licensed upload"
                    ),
                    "raw_checksum": record.raw_checksum or record.checksum,
                    "lineage": record.lineage
                    or {
                        "adapter": "admin_upload",
                        "adapter_version": 1,
                        "raw_path": f"content-agent-upload/{job_id}",
                        "source_location": record.record_id,
                    },
                    "source_content_usage": (
                        record.source_content_usage or record.content_usage.value
                    ),
                }
            )
            if record.source_name == "admin_upload"
            else record
            for record in records
        ]

        plan = plan_curriculum(records, request)
        courses = await self.generator.generate_courses(plan, request)
        source_counts = Counter(record.source_name for record in records)
        attached_snapshots = await self.store.get_snapshots(job_id)
        attached_by_source = {
            snapshot.source_name: snapshot for snapshot in attached_snapshots
        }
        source_manifest: list[ArtifactSourceManifest] = []
        for source_name in sorted(source_counts):
            snapshot = attached_by_source.get(source_name)
            if snapshot is not None:
                source_manifest.append(
                    ArtifactSourceManifest(
                        snapshot_id=snapshot.snapshot_id,
                        source_name=snapshot.source_name,
                        source_version=snapshot.source_version,
                        official_url=snapshot.official_url,
                        license_id=snapshot.license_id,
                        license_url=snapshot.license_url,
                        attribution_text=snapshot.attribution_text,
                        retrieved_at=snapshot.retrieved_at,
                        raw_checksum=snapshot.raw_checksum,
                        normalized_sha256=snapshot.normalized_sha256,
                        normalized_bytes=snapshot.normalized_bytes,
                        record_checksum_root=snapshot.record_checksum_root,
                        adapter_version=snapshot.adapter_version,
                        record_count=snapshot.record_count,
                    )
                )
                continue

            source_records = [
                record for record in records if record.source_name == source_name
            ]
            checksum_values = sorted(
                record.checksum or record.record_id for record in source_records
            )
            record_checksum_root = hashlib.sha256(
                "\n".join(checksum_values).encode("utf-8")
            ).hexdigest()
            normalized_payload = json.dumps(
                checksum_values,
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8")
            raw_checksums = {
                record.raw_checksum
                for record in source_records
                if record.raw_checksum is not None
            }
            aggregate_checksum = (
                next(iter(raw_checksums))
                if len(raw_checksums) == 1
                else hashlib.sha256(
                    "\n".join(checksum_values).encode("utf-8")
                ).hexdigest()
            )
            snapshot_checksum = hashlib.sha256(
                "\n".join(
                    checksum_values
                ).encode("utf-8")
            ).hexdigest()
            source_manifest.append(
                ArtifactSourceManifest(
                    snapshot_id=f"{source_name}:job:{job_id}:{snapshot_checksum}",
                    source_name=source_name,
                    source_version="job-upload-v1",
                    official_url="https://lexilingo.me/admin/content-agent/uploads",
                    license_id="LicenseRef-Admin-Owned",
                    license_url="https://lexilingo.me/legal/content-upload-rights",
                    attribution_text="Administrator-owned or licensed upload",
                    retrieved_at=_stable_manifest_time(
                        source_name,
                        job_id,
                        snapshot_checksum,
                    ),
                    raw_checksum=aggregate_checksum,
                    normalized_sha256=hashlib.sha256(normalized_payload).hexdigest(),
                    normalized_bytes=len(normalized_payload),
                    record_checksum_root=record_checksum_root,
                    adapter_version=1,
                    record_count=source_counts[source_name],
                )
            )

        generation_payload = {
            "request": request.model_dump(mode="json"),
            "records": [
                {
                    "record_id": record.record_id,
                    "checksum": record.checksum,
                    "content_usage": record.content_usage.value,
                }
                for record in sorted(records, key=lambda item: item.record_id)
            ],
        }
        generation_key = hashlib.sha256(
            json.dumps(
                generation_payload,
                ensure_ascii=False,
                sort_keys=True,
            ).encode("utf-8")
        ).hexdigest()
        warnings = []
        if plan.rejected_low_confidence:
            warnings.append(
                f"Rejected {plan.rejected_low_confidence} low-confidence records"
            )
        blocking_errors = find_missing_production_exercise_lessons(courses)

        return ContentAgentArtifact(
            generation_key=generation_key,
            source_manifest=source_manifest,
            courses=courses,
            quality=QualityArtifact(
                warnings=warnings,
                blocking_errors=blocking_errors,
                metrics={
                    "input_records": len(records),
                    "catalog_size": plan.catalog_size,
                    "rejected_low_confidence": plan.rejected_low_confidence,
                    "courses": len(courses),
                    "lessons": sum(
                        len(unit.lessons)
                        for course in courses
                        for unit in course.units
                    ),
                },
            ),
        )

    async def attach_snapshots(
        self,
        job_id: str,
        snapshots: list[SnapshotReference],
        *,
        storage: SnapshotStorage,
    ) -> SnapshotAttachmentResponse:
        existing = await self.store.get_snapshots(job_id)
        if existing:
            existing_refs = {
                (item.source_id, item.source_version, item.snapshot_id)
                for item in existing
            }
            requested_refs = {
                (item.source_id, item.source_version, item.snapshot_id)
                for item in snapshots
            }
            if existing_refs != requested_refs:
                raise ValueError(
                    "Job already has a different set of attached snapshots"
                )
            records = await self.store.get(job_id) or []
            return SnapshotAttachmentResponse(
                attached_snapshots=len(existing),
                stored_records=len(records),
            )

        if len({item.source_id for item in snapshots}) != len(snapshots):
            raise ValueError("Snapshot source IDs must be unique")

        descriptors: list[SourceSnapshotDescriptor] = []
        normalized_records = []
        for reference in snapshots:
            manifest = storage.read_manifest(
                reference.source_id,
                reference.source_version,
            )
            if manifest.status != "approved":
                raise StorageIntegrityError(
                    f"Snapshot {reference.snapshot_id} is not approved"
                )
            if manifest.snapshot_id != reference.snapshot_id:
                raise StorageIntegrityError(
                    "Requested snapshot_id does not match the stored manifest"
                )
            raw_records = storage.read_normalized_records(
                reference.source_id,
                reference.source_version,
            )
            source_records = [
                SourceRecordV2.model_validate(record) for record in raw_records
            ]
            for record in source_records:
                if (
                    record.source_name != manifest.source_name
                    or record.source_version != manifest.source_version
                    or record.raw_checksum != manifest.raw_sha256
                ):
                    raise StorageIntegrityError(
                        "Normalized record provenance does not match its manifest"
                    )
            normalized_records.extend(normalize_etl_records(source_records))
            definition = get_source_definition(manifest.source_name)
            descriptors.append(
                SourceSnapshotDescriptor(
                    source_id=manifest.source_name.value,
                    source_name=manifest.source_name.value,
                    source_version=manifest.source_version,
                    snapshot_id=manifest.snapshot_id,
                    official_url=str(manifest.official_url),
                    license_id=manifest.license_id.value,
                    license_url=str(manifest.license_url),
                    attribution_text=manifest.attribution_text,
                    retrieved_at=manifest.retrieved_at,
                    raw_checksum=manifest.raw_sha256,
                    normalized_sha256=manifest.normalized_sha256,
                    normalized_bytes=manifest.normalized_bytes,
                    record_checksum_root=manifest.record_checksum_root,
                    adapter_version=manifest.adapter_version,
                    record_count=manifest.counts.approved,
                    enabled=definition.default_enabled,
                )
            )

        stored_records = await self.store.attach_snapshot_records(
            job_id,
            normalized_records,
            descriptors,
        )
        return SnapshotAttachmentResponse(
            attached_snapshots=len(descriptors),
            stored_records=stored_records,
        )

    async def delete(self, job_id: str) -> None:
        await self.store.delete(job_id)


def _stable_manifest_time(source_name: str, job_id: str, checksum: str) -> datetime:
    seed = hashlib.sha256(f"{source_name}:{job_id}:{checksum}".encode()).hexdigest()
    seconds = int(seed[:12], 16) % (20 * 365 * 24 * 60 * 60)
    return datetime(2020, 1, 1, tzinfo=UTC) + timedelta(seconds=seconds)
