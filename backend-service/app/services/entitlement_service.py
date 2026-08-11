"""Server-authoritative entitlement state, refreshed from RevenueCat."""

from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entitlement import UserEntitlement
from app.services.revenuecat_client import RevenueCatClient, RevenueCatUnavailableError


class EntitlementService:
    """Reads/writes `UserEntitlement`. RevenueCat is the source of truth for
    *active* grants; on RevenueCat outage this fails closed on new grants
    (never invents an entitlement it hasn't confirmed) and fails open on
    already-confirmed ones (a transient outage does not revoke a paying
    user mid-outage — the stored row simply goes stale until the next
    successful sync)."""

    @staticmethod
    async def get(db: AsyncSession, user_id: UUID, entitlement_id: str = "premium") -> UserEntitlement | None:
        result = await db.execute(
            select(UserEntitlement).where(
                UserEntitlement.user_id == user_id,
                UserEntitlement.entitlement_id == entitlement_id,
            )
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def is_active(db: AsyncSession, user_id: UUID, entitlement_id: str = "premium") -> bool:
        row = await EntitlementService.get(db, user_id, entitlement_id)
        if row is None or row.status != "active":
            return False
        if row.expires_at is None:
            return True
        return row.expires_at > datetime.now(timezone.utc)

    @staticmethod
    async def sync(
        db: AsyncSession,
        user_id: UUID,
        entitlement_id: str = "premium",
        *,
        client: RevenueCatClient | None = None,
    ) -> tuple[UserEntitlement | None, bool]:
        """Fetch the subscriber's current entitlements from RevenueCat and
        upsert the local row. Returns `(row, degraded)` — `row` is the
        existing row (possibly stale) when `degraded` is True."""
        rc = client or RevenueCatClient()
        try:
            entitlements = await rc.get_subscriber_entitlements(str(user_id))
        except RevenueCatUnavailableError:
            existing = await EntitlementService.get(db, user_id, entitlement_id)
            return existing, True

        grant = entitlements.get(entitlement_id)
        row = await EntitlementService.get(db, user_id, entitlement_id)

        if grant is None:
            status = "none"
            product_id = None
            expires_at = None
        else:
            expires_raw = grant.get("expires_date")
            expires_at = (
                datetime.fromisoformat(expires_raw.replace("Z", "+00:00"))
                if expires_raw
                else None
            )
            is_active = expires_at is None or expires_at > datetime.now(timezone.utc)
            status = "active" if is_active else "expired"
            product_id = grant.get("product_identifier")

        if row is None:
            row = UserEntitlement(
                user_id=user_id,
                entitlement_id=entitlement_id,
                product_id=product_id,
                status=status,
                expires_at=expires_at,
                source="revenuecat",
            )
            db.add(row)
        else:
            row.product_id = product_id
            row.status = status
            row.expires_at = expires_at
            row.source = "revenuecat"

        await db.commit()
        await db.refresh(row)
        return row, False
