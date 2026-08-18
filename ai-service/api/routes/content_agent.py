"""Service-to-service endpoints for CEFR content generation."""

from __future__ import annotations

import hmac
import logging
from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Path,
    Response,
    Security,
    status,
)
from fastapi.security import APIKeyHeader
from api.core.config import get_settings
from api.core.redis_client import RedisClient
from api.models.content_agent import (
    ContentAgentArtifact,
    GenerationRequest,
    RecordBatchResponse,
    SnapshotAttachmentRequest,
    SnapshotAttachmentResponse,
    SourceSnapshotDescriptor,
    SourceRecordBatch,
)
from api.core.groq_key_pool import get_configured_key_count
from api.services.content_agent.generator import (
    GroqMissionGenerator,
    LLMMissionGenerator,
)
from api.services.content_agent.planner import InsufficientVocabularyError
from api.services.content_agent.policies import SourcePolicyError
from api.services.content_agent.service import (
    ContentAgentService,
    JobContextNotFound,
)
from api.services.content_agent.store import (
    ContentAgentStore,
    RecordLimitExceeded,
)
from api.services.content_etl.registry import get_source_definition
from api.services.content_etl.storage import SnapshotStorage, StorageIntegrityError


router = APIRouter(prefix="/api/v1/internal/content-agent")
logger = logging.getLogger(__name__)
# auto_error=False: verify_content_agent_token returns a consistent 403 message
# for both absent and wrong tokens, preventing information leakage about which
# condition triggered the rejection.
_service_token_header = APIKeyHeader(
    name="X-Content-Agent-Token",
    auto_error=False,
)
_store: ContentAgentStore | None = None
JobId = Annotated[
    str,
    Path(
        min_length=1,
        max_length=128,
        pattern=r"^[A-Za-z0-9._:-]+$",
    ),
]


async def verify_content_agent_token(
    provided_token: str | None = Security(_service_token_header),
) -> str:
    settings = get_settings()
    expected_token = settings.CONTENT_AGENT_SERVICE_TOKEN.strip()
    if not expected_token:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Content-agent service token is not configured",
        )
    if not provided_token or not hmac.compare_digest(
        provided_token,
        expected_token,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid content-agent service token",
        )
    return provided_token


async def get_content_agent_service() -> ContentAgentService:
    global _store
    settings = get_settings()
    redis = RedisClient._instance
    if redis is None and not settings.CONTENT_AGENT_ALLOW_LOCAL_STORE:
        logger.warning(
            "Redis not yet connected and local fallback is disabled — "
            "content-agent store calls will fail until Redis is available"
        )
    if _store is None:
        _store = ContentAgentStore(
            ttl_seconds=settings.CONTENT_AGENT_TTL_SECONDS,
            max_records=settings.CONTENT_AGENT_MAX_RECORDS,
            redis_client=redis,
            allow_local_fallback=settings.CONTENT_AGENT_ALLOW_LOCAL_STORE,
        )
    else:
        _store.set_redis_client(redis)
    # Groq first: its keys are pooled and rate-limited service-wide, and an
    # unusable Gemini key degrades a job to the deterministic template without
    # any signal that the missions were never generated.
    if get_configured_key_count() > 0:
        generator = GroqMissionGenerator()
    elif settings.GEMINI_API_KEY:
        generator = LLMMissionGenerator(api_key=settings.GEMINI_API_KEY)
    else:
        generator = None
        logger.warning(
            "No Groq keys and no GEMINI_API_KEY — content-agent jobs will fall "
            "back to deterministic exercise templates"
        )
    return ContentAgentService(store=_store, generator=generator)


@router.post(
    "/jobs/{job_id}/records",
    response_model=RecordBatchResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def ingest_records(
    job_id: JobId,
    batch: SourceRecordBatch,
    _token: str = Depends(verify_content_agent_token),
    service: ContentAgentService = Depends(get_content_agent_service),
) -> RecordBatchResponse:
    settings = get_settings()
    if len(batch.records) > settings.CONTENT_AGENT_MAX_BATCH_RECORDS:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=(
                "Content-agent record batch exceeds the configured "
                f"limit ({settings.CONTENT_AGENT_MAX_BATCH_RECORDS})"
            ),
        )
    try:
        return await service.ingest_records(job_id, batch)
    except RecordLimitExceeded as exc:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=str(exc),
        ) from exc
    except (SourcePolicyError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.post(
    "/jobs/{job_id}/generate",
    response_model=ContentAgentArtifact,
)
async def generate_artifact(
    job_id: JobId,
    request: GenerationRequest,
    _token: str = Depends(verify_content_agent_token),
    service: ContentAgentService = Depends(get_content_agent_service),
) -> ContentAgentArtifact:
    try:
        return await service.generate(job_id, request)
    except JobContextNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except InsufficientVocabularyError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.delete(
    "/jobs/{job_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_job_context(
    job_id: JobId,
    _token: str = Depends(verify_content_agent_token),
    service: ContentAgentService = Depends(get_content_agent_service),
) -> Response:
    try:
        await service.delete(job_id)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/sources",
    response_model=list[SourceSnapshotDescriptor],
)
async def list_sources(
    _token: str = Depends(verify_content_agent_token),
) -> list[SourceSnapshotDescriptor]:
    """List only active, integrity-verified ETL snapshots."""
    settings = get_settings()
    storage = SnapshotStorage(
        getattr(settings, "CONTENT_ETL_STORAGE_ROOT", "/data/content-etl")
    )
    entries: list[SourceSnapshotDescriptor] = []
    for pointer in sorted((storage.root / "active").glob("*.json")):
        try:
            manifest = storage.read_active_manifest(pointer.stem)
            definition = get_source_definition(manifest.source_name)
        except (StorageIntegrityError, ValueError):
            logger.exception("Ignoring invalid active ETL pointer %s", pointer.name)
            continue
        entries.append(
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
    return entries


@router.post(
    "/jobs/{job_id}/snapshots",
    response_model=SnapshotAttachmentResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def attach_snapshots(
    job_id: JobId,
    request: SnapshotAttachmentRequest,
    _token: str = Depends(verify_content_agent_token),
    service: ContentAgentService = Depends(get_content_agent_service),
) -> SnapshotAttachmentResponse:
    """Attach exact approved snapshot records to a job context."""
    settings = get_settings()
    storage_root = getattr(settings, "CONTENT_ETL_STORAGE_ROOT", "/data/content-etl")
    try:
        storage = SnapshotStorage(storage_root)
        return await service.attach_snapshots(
            job_id,
            request.snapshots,
            storage=storage,
        )
    except RecordLimitExceeded as exc:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=str(exc),
        ) from exc
    except (StorageIntegrityError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        logger.exception("Unexpected error attaching snapshots for job %s", job_id)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Snapshot attachment failed",
        ) from exc
