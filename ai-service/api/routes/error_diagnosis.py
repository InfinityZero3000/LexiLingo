"""Internal endpoint for standalone learner-error diagnosis."""

import hmac
import os

from fastapi import APIRouter, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel

from api.services.trace_cag.nodes_v2 import diagnose_node

router = APIRouter(prefix="/api/v1/internal/diagnose")

_admin_key_header = APIKeyHeader(name="X-Admin-Api-Key", auto_error=False)


async def _verify_admin_key(
    provided: str | None = Security(_admin_key_header),
) -> None:
    expected = os.getenv("AI_ADMIN_API_KEY", "").strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI_ADMIN_API_KEY is not configured",
        )
    if not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin API key",
        )


class DiagnosisRequest(BaseModel):
    text: str
    level: str | None = "B1"


class DiagnosisErrorResponse(BaseModel):
    span: str
    type: str
    correction: str
    explanation: str


class DiagnosisResponse(BaseModel):
    errors: list[DiagnosisErrorResponse]
    intent: str
    confidence: float


@router.post(
    "",
    response_model=DiagnosisResponse,
    dependencies=[Security(_verify_admin_key)],
)
async def diagnose_error(body: DiagnosisRequest) -> DiagnosisResponse:
    result = await diagnose_node(
        {
            "user_input": body.text,
            "learner_profile": {"level": body.level or "B1"},
        }
    )
    return DiagnosisResponse(
        errors=result["diagnosis_errors"],
        intent=result["diagnosis_intent"],
        confidence=result["diagnosis_confidence"],
    )
