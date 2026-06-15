"""Service-to-service endpoints for CEFR content generation."""

from __future__ import annotations

import hmac
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
    SourceRecordBatch,
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


router = APIRouter(prefix="/api/v1/internal/content-agent")
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
    if _store is None:
        _store = ContentAgentStore(
            ttl_seconds=settings.CONTENT_AGENT_TTL_SECONDS,
            max_records=settings.CONTENT_AGENT_MAX_RECORDS,
            redis_client=RedisClient._instance,
            allow_local_fallback=settings.CONTENT_AGENT_ALLOW_LOCAL_STORE,
        )
    else:
        _store.set_redis_client(RedisClient._instance)
    return ContentAgentService(store=_store)


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
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
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
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
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
