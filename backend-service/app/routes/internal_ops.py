"""Error events pushed by ai-service (service token, never exposed through the gateway)."""
from datetime import datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.routes.internal_entitlements import require_internal_service
from app.schemas.response import ApiResponse
from app.services.ops_errors import is_skipped_path, record_error, redact

router = APIRouter(prefix="/internal/ops", tags=["Internal Ops"])

MAX_EVENTS = 200


class ErrorEvent(BaseModel):
    occurred_at: datetime | None = None
    method: str = Field(max_length=10)
    route: str = Field(max_length=300)
    status: int = Field(ge=100, le=599)
    error_type: str | None = Field(None, max_length=150)
    location: str | None = Field(None, max_length=200)
    message: str | None = Field(None, max_length=5000)
    request_id: str | None = Field(None, max_length=100)


class ErrorBatch(BaseModel):
    service: str = Field(pattern=r"^[a-z0-9-]{1,30}$")
    dropped: int = Field(0, ge=0)
    events: list[ErrorEvent] = Field(max_length=MAX_EVENTS)


@router.post("/errors:batch", response_model=ApiResponse[dict])
async def ingest_errors(batch: ErrorBatch, _caller: str = Depends(require_internal_service)):
    grouped: dict[tuple, list] = {}
    for e in batch.events:
        if e.status < 400 or is_skipped_path(e.route):
            continue
        key = (
            "error" if e.status >= 500 else "client", e.method, redact(e.route, 300) or "<unmatched>",
            e.status, redact(e.error_type, 150), redact(e.location, 200),
        )
        entry = grouped.setdefault(key, [0, None, None])
        entry[0] += 1
        entry[1], entry[2] = e.message, e.request_id
    accepted = 0
    for (kind, method, route, status, error_type, location), (count, message, request_id) in grouped.items():
        if await record_error(
            service=batch.service, kind=kind, method=method, route=route, status=status,
            error_type=error_type, location=location, message=message, request_id=request_id, count=count,
        ):
            accepted += count
    return ApiResponse(success=True, message="Events accepted", data={"accepted": accepted})
