"""Internal endpoint for AI grading of IELTS Writing and Speaking."""

import hmac
import logging
import os

from fastapi import APIRouter, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field

from api.services.ielts_grader import grade_submission

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/internal/ielts")

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


class GradeRequest(BaseModel):
    skill: str = Field(description="writing or speaking")
    part_key: str = Field(description="e.g. writing_task_2, speaking_part_2")
    task_prompt: str
    answer_text: str
    test_type: str = "academic"


class GradeResponse(BaseModel):
    criteria: dict[str, float]
    band: float
    feedback: dict
    word_count: int
    grader_version: str
    model: str


@router.post("/grade", response_model=GradeResponse, dependencies=[Security(_verify_admin_key)])
async def grade(body: GradeRequest) -> GradeResponse:
    try:
        result = await grade_submission(
            skill=body.skill,
            part_key=body.part_key,
            task_prompt=body.task_prompt,
            answer_text=body.answer_text,
            test_type=body.test_type,
        )
    except ValueError as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from exc
    except Exception as exc:
        logger.exception("IELTS grading failed")
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, f"Grading failed: {exc}"
        ) from exc
    return GradeResponse(**result)
