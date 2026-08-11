"""Entitlement API routes.

Server-authoritative premium state. The Flutter client's local RevenueCat
SDK state is a UX hint only — this is the boundary any future premium-gated
route should depend on via `require_entitlement`.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.entitlements import EntitlementStatus
from app.services.entitlement_service import EntitlementService

router = APIRouter(prefix="/entitlements", tags=["Entitlements"])


def _to_status(row, entitlement_id: str, degraded: bool) -> EntitlementStatus:
    if row is None:
        return EntitlementStatus(
            entitlement_id=entitlement_id,
            active=False,
            source="revenuecat",
            degraded=degraded,
        )
    return EntitlementStatus(
        entitlement_id=row.entitlement_id,
        active=row.status == "active",
        product_id=row.product_id,
        expires_at=row.expires_at,
        source=row.source,
        synced_at=row.synced_at,
        degraded=degraded,
    )


@router.post("/sync", response_model=EntitlementStatus)
async def sync_entitlement(
    entitlement_id: str = "premium",
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EntitlementStatus:
    """Re-fetch this user's entitlement state from RevenueCat.

    Call right after a purchase/restore completes, and once per app-start
    session. Ignores any client-submitted purchase payload — verification
    is entirely server-to-RevenueCat.
    """
    row, degraded = await EntitlementService.sync(db, current_user.id, entitlement_id)
    return _to_status(row, entitlement_id, degraded)


@router.get("/me", response_model=EntitlementStatus)
async def get_my_entitlement(
    entitlement_id: str = "premium",
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EntitlementStatus:
    """Read the cached entitlement state. Does not call RevenueCat."""
    row = await EntitlementService.get(db, current_user.id, entitlement_id)
    return _to_status(row, entitlement_id, degraded=False)
