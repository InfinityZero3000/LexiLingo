"""Private service-to-service entitlement reads (ai-service -> backend-service).

Reuses the existing ai-service<->backend-service shared token
(`LEARNER_STATE_INTERNAL_TOKEN`/`LEARNER_STATE_INTERNAL_AUDIENCE`) rather than
minting a second secret to deploy — but does NOT gate on
`settings.LEARNER_STATE_ENABLED`: premium must keep working even with that
unrelated feature flag off.
"""

import secrets
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.services.entitlement_service import EntitlementService

router = APIRouter(prefix="/internal/entitlements", tags=["Internal Entitlements"])


async def require_internal_service(
    x_lexilingo_service_token: str = Header(default=""),
    x_lexilingo_audience: str = Header(default=""),
) -> str:
    if not secrets.compare_digest(
        x_lexilingo_audience, settings.LEARNER_STATE_INTERNAL_AUDIENCE
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid service identity")
    if not x_lexilingo_service_token or not secrets.compare_digest(
        x_lexilingo_service_token, settings.LEARNER_STATE_INTERNAL_TOKEN
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid service identity")
    return "ai-service"


@router.get("/{user_id}")
async def get_internal_entitlement(
    user_id: str,
    entitlement_id: str = "premium",
    db: AsyncSession = Depends(get_db),
    _caller: str = Depends(require_internal_service),
) -> dict:
    try:
        uid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=422, detail="invalid user_id")

    active = await EntitlementService.is_active(db, uid, entitlement_id)
    return {"user_id": user_id, "entitlement_id": entitlement_id, "active": active}
