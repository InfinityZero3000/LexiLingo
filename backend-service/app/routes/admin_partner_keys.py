"""Issue and revoke the keys partners use against the read-only /integrations API.

Only a hash is stored (the same SHA-256 `require_partner_api_key` checks), so the
raw key exists exactly once: in the response to the create call.
"""
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_super_admin
from app.models.partner import PartnerApiKey
from app.models.user import User
from app.schemas.response import ApiResponse
from app.services.admin_audit import record_admin_action

router = APIRouter(prefix="/admin/partner-keys", tags=["Admin - Partner API Keys"])

KEY_ID_PREFIX = "pk_"


class PartnerKeyCreate(BaseModel):
    owner: str = Field(..., min_length=2, max_length=255, description="Who the key is issued to")
    expires_in_days: int | None = Field(None, ge=1, le=730, description="Omit for a key that never expires")


def _aware(value: datetime | None) -> datetime | None:
    return value if value is None or value.tzinfo else value.replace(tzinfo=timezone.utc)


def _view(key: PartnerApiKey) -> dict:
    now = datetime.now(timezone.utc)
    expires = _aware(key.expires_at)
    state = "revoked" if key.revoked_at else "expired" if expires and expires <= now else "active"
    return {
        "id": str(key.id),
        "key_id": key.key_id,
        "owner": key.owner,
        "scope": key.scope,
        "status": state,
        "created_at": _aware(key.created_at).isoformat() if key.created_at else None,
        "expires_at": expires.isoformat() if expires else None,
        "revoked_at": _aware(key.revoked_at).isoformat() if key.revoked_at else None,
    }


@router.get("", response_model=ApiResponse[list])
async def list_partner_keys(
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    keys = (await db.execute(select(PartnerApiKey).order_by(PartnerApiKey.created_at.desc()))).scalars().all()
    return ApiResponse(success=True, message=f"{len(keys)} keys", data=[_view(k) for k in keys])


@router.post("", response_model=ApiResponse[dict], status_code=status.HTTP_201_CREATED)
async def create_partner_key(
    data: PartnerKeyCreate,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    """Create a read-only key. The raw `key` in the response is shown once and cannot be recovered."""
    key_id = KEY_ID_PREFIX + secrets.token_hex(6)
    raw_key = f"{key_id}.{secrets.token_urlsafe(32)}"
    expires_at = (
        datetime.now(timezone.utc) + timedelta(days=data.expires_in_days) if data.expires_in_days else None
    )
    record = PartnerApiKey(
        key_id=key_id,
        key_hash=hashlib.sha256(raw_key.encode()).hexdigest(),
        owner=data.owner.strip(),
        scope="read",
        expires_at=expires_at,
    )
    db.add(record)
    record_admin_action(
        db, admin, "partner_key_create", "partner_key", key_id,
        {"owner": record.owner, "expires_at": expires_at.isoformat() if expires_at else None}, request,
    )
    await db.commit()
    await db.refresh(record)
    return ApiResponse(success=True, message="Partner key created", data={**_view(record), "key": raw_key})


@router.post("/{key_pk}/revoke", response_model=ApiResponse[dict])
async def revoke_partner_key(
    key_pk: UUID,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    key = (await db.execute(select(PartnerApiKey).where(PartnerApiKey.id == key_pk))).scalar_one_or_none()
    if key is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Partner key not found")
    if key.revoked_at is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Partner key is already revoked")

    key.revoked_at = datetime.now(timezone.utc)
    record_admin_action(db, admin, "partner_key_revoke", "partner_key", key.key_id, {"owner": key.owner}, request)
    await db.commit()
    return ApiResponse(success=True, message="Partner key revoked", data=_view(key))
