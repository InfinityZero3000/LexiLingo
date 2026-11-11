"""What support needs to see and fix for one learner: wallet, XP, inventory, premium.

Reads are open to admins. Anything that moves money or premium is super admin
only, needs a written reason, and is audited with that reason.
"""
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import build_cache_key, delete_cached
from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_current_super_admin, require_permission
from app.crud.gamification import ShopCRUD, WalletCRUD
from app.models.gamification import UserWallet, WalletTransaction
from app.models.games import XPTransaction
from app.models.user import User
from app.models.entitlement import UserEntitlement
from app.schemas.response import ApiResponse
from app.services.admin_audit import record_admin_action
from app.services.entitlement_service import EntitlementService
from app.services.gem_limits import reserve_gems

router = APIRouter(prefix="/admin/users", tags=["Admin - User Support"])

PREMIUM = "premium"


async def _user_or_404(db: AsyncSession, user_id: UUID) -> User:
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


# ── Wallet ────────────────────────────────────────────────────────────────

@router.get("/{user_id}/wallet", response_model=ApiResponse[dict])
async def get_user_wallet(
    user_id: UUID,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    admin: User = Depends(require_permission("users:read")),
    db: AsyncSession = Depends(get_db),
):
    """Balance and the gem ledger, newest first. Reading never creates a wallet."""
    await _user_or_404(db, user_id)
    wallet = (await db.execute(select(UserWallet).where(UserWallet.user_id == user_id))).scalar_one_or_none()
    total = (
        await db.execute(select(func.count()).select_from(WalletTransaction).where(WalletTransaction.user_id == user_id))
    ).scalar() or 0
    rows = (
        (
            await db.execute(
                select(WalletTransaction)
                .where(WalletTransaction.user_id == user_id)
                .order_by(WalletTransaction.created_at.desc())
                .offset(offset)
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    return ApiResponse(
        success=True,
        message="Wallet retrieved",
        data={
            "balance": wallet.gems if wallet else 0,
            "total_earned": wallet.total_gems_earned if wallet else 0,
            "total_spent": wallet.total_gems_spent if wallet else 0,
            "total": total,
            "transactions": [
                {
                    "id": str(tx.id),
                    "type": tx.transaction_type,
                    "amount": tx.amount,
                    "balance_after": tx.balance_after,
                    "source": tx.source,
                    "description": tx.description,
                    "created_at": _iso(tx.created_at),
                }
                for tx in rows
            ],
        },
    )


class WalletAdjustRequest(BaseModel):
    delta: int = Field(..., description="Gems to add (positive) or take back (negative)")
    reason: str = Field(..., min_length=5, max_length=300)

    @field_validator("delta")
    @classmethod
    def _non_zero(cls, value: int) -> int:
        if value == 0:
            raise ValueError("delta must not be 0")
        return value


@router.post("/{user_id}/wallet/adjust", response_model=ApiResponse[dict])
async def adjust_user_wallet(
    user_id: UUID,
    data: WalletAdjustRequest,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    """Correct or refund gems. A debit may not take the balance below zero."""
    await _user_or_404(db, user_id)
    await reserve_gems(db, admin, user_id, "adjust", data.delta, data.reason)

    # Queued first so the audit row commits atomically with the ledger entry.
    record_admin_action(
        db, admin, "wallet_adjust", "user", user_id, {"delta": data.delta, "reason": data.reason}, request
    )
    description = f"Admin adjustment by {admin.username}: {data.reason}"
    if data.delta > 0:
        wallet, _ = await WalletCRUD.add_gems(
            db, user_id, data.delta, source="admin_adjust", description=description, commit=False
        )
    else:
        wallet, _ = await WalletCRUD.spend_gems(
            db, user_id, -data.delta, source="admin_adjust", description=description, commit=False
        )
        if wallet is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="The learner does not have enough gems to take back that amount",
            )
    balance = wallet.gems
    await db.commit()
    await delete_cached(build_cache_key("wallet", user_id=str(user_id)))
    return ApiResponse(success=True, message="Wallet adjusted", data={"balance": balance, "delta": data.delta})


# ── XP and inventory ──────────────────────────────────────────────────────

@router.get("/{user_id}/xp-transactions", response_model=ApiResponse[dict])
async def get_user_xp_transactions(
    user_id: UUID,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    admin: User = Depends(require_permission("users:read")),
    db: AsyncSession = Depends(get_db),
):
    user = await _user_or_404(db, user_id)
    total = (
        await db.execute(select(func.count()).select_from(XPTransaction).where(XPTransaction.user_id == user_id))
    ).scalar() or 0
    rows = (
        (
            await db.execute(
                select(XPTransaction)
                .where(XPTransaction.user_id == user_id)
                .order_by(XPTransaction.created_at.desc())
                .offset(offset)
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    return ApiResponse(
        success=True,
        message="XP history retrieved",
        data={
            "total_xp": user.total_xp or 0,
            "total": total,
            "transactions": [
                {
                    "id": str(tx.id),
                    "amount": tx.amount,
                    "base_amount": tx.base_amount,
                    "multiplier": tx.multiplier,
                    "source": tx.source,
                    "source_detail": tx.source_detail,
                    "created_at": _iso(tx.created_at),
                }
                for tx in rows
            ],
        },
    )


@router.get("/{user_id}/inventory", response_model=ApiResponse[dict])
async def get_user_inventory(
    user_id: UUID,
    admin: User = Depends(require_permission("users:read")),
    db: AsyncSession = Depends(get_db),
):
    await _user_or_404(db, user_id)
    pairs = await ShopCRUD.get_user_inventory_with_items(db, user_id)
    return ApiResponse(
        success=True,
        message="Inventory retrieved",
        data={
            "items": [
                {
                    "id": str(entry.id),
                    "name": item.name,
                    "item_type": item.item_type,
                    "quantity": entry.quantity,
                    "is_active": bool(entry.is_active),
                    "expires_at": _iso(entry.expires_at),
                    "purchased_at": _iso(entry.purchased_at),
                }
                for entry, item in pairs
            ]
        },
    )


# ── Premium ───────────────────────────────────────────────────────────────

def _entitlement_view(row: UserEntitlement | None) -> dict:
    now = datetime.now(timezone.utc)
    active = bool(
        row and row.status == "active" and (row.expires_at is None or _aware(row.expires_at) > now)
    )
    return {
        "entitlement_id": PREMIUM,
        "exists": row is not None,
        "is_active": active,
        "status": row.status if row else "none",
        "source": row.source if row else None,
        "product_id": row.product_id if row else None,
        "expires_at": _iso(row.expires_at) if row else None,
        "synced_at": _iso(row.synced_at) if row else None,
        "force_enabled": settings.PREMIUM_FORCE_ENABLED,
    }


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


@router.get("/{user_id}/entitlements", response_model=ApiResponse[dict])
async def get_user_entitlement(
    user_id: UUID,
    admin: User = Depends(require_permission("users:read")),
    db: AsyncSession = Depends(get_db),
):
    await _user_or_404(db, user_id)
    row = await EntitlementService.get(db, user_id, PREMIUM)
    return ApiResponse(success=True, message="Entitlement retrieved", data=_entitlement_view(row))


class PremiumGrantRequest(BaseModel):
    days: int = Field(..., ge=1, le=365)
    reason: str = Field(..., min_length=5, max_length=300)


class PremiumRevokeRequest(BaseModel):
    reason: str = Field(..., min_length=5, max_length=300)


@router.post("/{user_id}/entitlements/grant", response_model=ApiResponse[dict])
async def grant_user_premium(
    user_id: UUID,
    data: PremiumGrantRequest,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    """Give premium for a fixed number of days, without touching a paid subscription."""
    await _user_or_404(db, user_id)
    row = await EntitlementService.get(db, user_id, PREMIUM)
    now = datetime.now(timezone.utc)

    if (
        row is not None
        and row.source != "admin"
        and row.status == "active"
        and (row.expires_at is None or _aware(row.expires_at) > now)
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The learner already has an active paid subscription",
        )

    expires_at = now + timedelta(days=data.days)
    if row is None:
        row = UserEntitlement(user_id=user_id, entitlement_id=PREMIUM, status="active")
        db.add(row)
    row.status = "active"
    row.expires_at = expires_at
    row.source = "admin"
    row.product_id = "admin_grant"
    row.synced_at = now

    record_admin_action(
        db, admin, "premium_grant", "user", user_id,
        {"days": data.days, "expires_at": expires_at.isoformat(), "reason": data.reason}, request,
    )
    await db.commit()
    return ApiResponse(success=True, message="Premium granted", data=_entitlement_view(row))


@router.post("/{user_id}/entitlements/revoke", response_model=ApiResponse[dict])
async def revoke_user_premium(
    user_id: UUID,
    data: PremiumRevokeRequest,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    """End an admin-granted premium. A paid subscription is managed by the store, not here."""
    await _user_or_404(db, user_id)
    row = await EntitlementService.get(db, user_id, PREMIUM)
    if row is None or row.source != "admin":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only a premium granted by an admin can be revoked here",
        )

    now = datetime.now(timezone.utc)
    row.status = "expired"
    row.expires_at = now
    row.synced_at = now
    record_admin_action(db, admin, "premium_revoke", "user", user_id, {"reason": data.reason}, request)
    await db.commit()
    return ApiResponse(success=True, message="Premium revoked", data=_entitlement_view(row))
