"""Bounded, privacy-safe TraceCAG service endpoint."""

from __future__ import annotations

import hashlib
import json
import time
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field

from api.core.integration_service_auth import verify_trace_cag_service_token
from api.services.trace_cag.external_request_cache import ExternalRequestCache
from service.tracecag_service.adapters.lexilingo import create_lexilingo_service
from service.tracecag_service.runtime import TraceCAGService
from service.tracecag_service.schemas import TraceCAGRequest


class Concept(BaseModel):
    model_config = ConfigDict(extra="forbid")
    code: str = Field(min_length=1, max_length=100)
    mastery: float = Field(ge=0, le=1)


class RecentError(BaseModel):
    model_config = ConfigDict(extra="forbid")
    code: str = Field(min_length=1, max_length=100)
    count: int = Field(ge=1, le=100)


class LearnerSnapshot(BaseModel):
    model_config = ConfigDict(extra="forbid")
    learning_goal: str = Field(min_length=1, max_length=300)
    cefr_level: Literal["A1", "A2", "B1", "B2", "C1", "C2"]
    concepts: list[Concept] = Field(max_length=50)
    recent_errors: list[RecentError] = Field(max_length=20)


class ExerciseContext(BaseModel):
    model_config = ConfigDict(extra="forbid")
    type: Literal["quiz", "flashcard", "pronunciation", "free_response"]
    prompt: str = Field(min_length=1, max_length=1000)
    expected_answer: str | None = Field(default=None, max_length=1000)
    concept_codes: list[str] = Field(default_factory=list, max_length=50)


class AnalyzeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    subject: str = Field(min_length=32, max_length=128, pattern=r"^[A-Za-z0-9_-]+$")
    session_id: str = Field(min_length=1, max_length=128)
    input_type: Literal["answer", "hint_request", "pronunciation", "tutor_message"]
    learner_snapshot: LearnerSnapshot
    exercise_context: ExerciseContext
    text: str = Field(min_length=1, max_length=2000)


router = APIRouter(prefix="/api/v1/integrations/trace-cag/v1", tags=["TraceCAG Integration"])
_cache = ExternalRequestCache()
_service: TraceCAGService | None = None


def get_trace_cag_service() -> TraceCAGService:
    global _service
    if _service is None:
        _service = create_lexilingo_service()
    return _service


@router.post("/analyze")
async def analyze(
    body: AnalyzeRequest,
    request: Request,
    request_id: Annotated[str, Header(alias="X-Request-ID")],
    _token: str = Depends(verify_trace_cag_service_token),
    service: TraceCAGService = Depends(get_trace_cag_service),
) -> dict:
    try:
        UUID(request_id)
    except ValueError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "X-Request-ID must be a UUID") from exc
    raw = await request.body()
    if len(raw) > 8192:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "Request body exceeds 8 KiB")

    canonical = json.dumps(body.model_dump(), sort_keys=True, separators=(",", ":")).encode()
    fingerprint = hashlib.sha256(canonical).hexdigest()
    cache_state, cached = await _cache.get(request_id, fingerprint)
    if cache_state == "conflict":
        raise HTTPException(status.HTTP_409_CONFLICT, "Request ID payload conflict")
    if cached is not None:
        return cached

    started = time.monotonic()
    result = await service.analyze(TraceCAGRequest(
        user_input=body.text,
        session_id=body.session_id,
        user_id=body.subject,
        input_type="voice" if body.input_type == "pronunciation" else "text",
        learner_profile=body.learner_snapshot.model_dump(),
        kg_seed_concepts=body.exercise_context.concept_codes,
    ))
    if result.error:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "TraceCAG pipeline unavailable")

    action = result.action.get("type") if isinstance(result.action, dict) else None
    recommended = action if action in {
        "continue", "retry", "review_prerequisite", "practice_pronunciation", "ask_teacher"
    } else "continue"
    response = {
        "schema_version": "1.0",
        "request_id": request_id,
        "diagnosis": {
            "codes": [str(item.get("type", "correction"))[:100] for item in result.corrections[:20]],
            "summary": (result.tutor_response or "Analysis complete.")[:1000],
        },
        "hints": [
            {"level": index + 1, "text": str(text)[:500]}
            for index, text in enumerate(
                [result.vietnamese_hint, result.pronunciation_tip][:3]
            ) if text
        ],
        "feedback": (result.tutor_response or "Analysis complete.")[:2000],
        "recommended_action": recommended,
        "message": (result.tutor_response or "Analysis complete.")[:2000],
        "degraded": False,
        "model": {
            "provider": str(result.metadata.get("provider", "lexilingo"))[:100],
            "model": str(result.metadata.get("model", "trace-cag"))[:100],
            "version": str(result.metadata.get("version"))[:100] if result.metadata.get("version") else None,
            "latency_ms": min(15000, int((time.monotonic() - started) * 1000)),
        },
    }
    await _cache.put(request_id, fingerprint, response)
    return response
