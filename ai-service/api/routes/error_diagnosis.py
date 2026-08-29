"""Internal endpoint for standalone learner-error diagnosis."""

from fastapi import APIRouter, Security
from pydantic import BaseModel

from api.core.auth import verify_internal_admin_key
from api.services.trace_cag.nodes_v2 import diagnose_node

router = APIRouter(prefix="/api/v1/internal/diagnose")


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
    dependencies=[Security(verify_internal_admin_key)],
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
