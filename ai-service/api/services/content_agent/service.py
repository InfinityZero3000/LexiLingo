"""Content-agent ingestion and generation orchestration."""

from __future__ import annotations

import hashlib
import json
from collections import Counter

from api.models.content_agent import (
    ContentAgentArtifact,
    GenerationRequest,
    QualityArtifact,
    RecordBatchResponse,
    SourceRecordBatch,
)
from api.services.content_agent.adapters import (
    normalize_existing_cefr_records,
    normalize_source_records,
)
from api.services.content_agent.generator import (
    CourseGenerator,
    DeterministicCourseGenerator,
)
from api.services.content_agent.planner import plan_curriculum
from api.services.content_agent.policies import get_source_policy
from api.services.content_agent.store import ContentAgentStore


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
        if effective_source.strip().lower() == "existing_cefr" or any(
            str(rec.get("source_name") or "").strip().lower() == "existing_cefr"
            for rec in batch.records
        ):
            raise ValueError(
                "existing_cefr records must be loaded from an approved snapshot; "
                "direct ingestion is not permitted"
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
        if request.sources and "existing_cefr" in request.sources:
            existing_ids = {
                record.record_id
                for record in records
                if record.source_name == "existing_cefr"
            }
            records.extend(
                record
                for record in normalize_existing_cefr_records()
                if record.record_id not in existing_ids
            )
        if not records:
            raise JobContextNotFound(
                f"Content-agent job context not found or expired: {job_id}"
            )

        plan = plan_curriculum(records, request)
        courses = self.generator.generate_courses(plan, request)
        source_counts = Counter(record.source_name for record in records)
        source_manifest = []
        for source_name in sorted(source_counts):
            policy = get_source_policy(source_name)
            source_records = [
                record for record in records if record.source_name == source_name
            ]
            source_manifest.append(
                {
                    "source_name": source_name,
                    "record_count": source_counts[source_name],
                    "license_mode": policy.license_mode.value,
                    "content_usage": sorted(
                        {record.content_usage.value for record in source_records}
                    ),
                    "policy_reviewed_at": policy.reviewed_at.isoformat(),
                    "policy_expires_at": policy.expires_at.isoformat(),
                    "checksums": sorted(
                        {
                            record.checksum
                            for record in source_records
                            if record.checksum
                        }
                    ),
                }
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

        return ContentAgentArtifact(
            generation_key=generation_key,
            source_manifest=source_manifest,
            courses=courses,
            quality=QualityArtifact(
                warnings=warnings,
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

    async def delete(self, job_id: str) -> None:
        await self.store.delete(job_id)
