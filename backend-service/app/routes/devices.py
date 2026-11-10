"""
Device Routes

Endpoints for device registration and FCM token management
"""

from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User, UserDevice
from app.schemas.devices import (
    DeviceRegisterRequest,
    DeviceResponse
)
from app.schemas.common import MessageResponse
from app.schemas.response import ApiResponse
from app.services.starter_reward_service import StarterRewardService

router = APIRouter(prefix="/devices", tags=["Devices"])


def _session_dialect_name(db: AsyncSession) -> str | None:
    """Return the SQL dialect when available without coupling route tests to DB internals."""
    try:
        get_bind = getattr(db, "get_bind", None)
        bind = get_bind() if callable(get_bind) else getattr(db, "bind", None)
        dialect = getattr(bind, "dialect", None)
        name = getattr(dialect, "name", None)
        return name if isinstance(name, str) else None
    except Exception:
        return None


@router.post("", response_model=ApiResponse[DeviceResponse], status_code=status.HTTP_201_CREATED)
async def register_device(
    request: DeviceRegisterRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Register a device for push notifications.
    
    If device already exists, updates FCM token and returns existing device.
    """
    now = datetime.now(timezone.utc)

    if _session_dialect_name(db) == "postgresql":
        # Atomic upsert avoids duplicate registrations when the app starts
        # and refreshes the same FCM token from multiple requests.
        stmt = (
            pg_insert(UserDevice)
            .values(
                user_id=current_user.id,
                device_id=request.device_id,
                device_type=request.device_type,
                device_name=request.device_name,
                fcm_token=request.fcm_token,
                last_active=now,
            )
            .on_conflict_do_update(
                index_elements=["device_id"],
                set_=dict(
                    user_id=current_user.id,
                    device_type=request.device_type,
                    fcm_token=request.fcm_token,
                    device_name=request.device_name,
                    last_active=now,
                ),
            )
            .returning(UserDevice)
        )
        result = await db.execute(stmt)
        device = result.scalar_one()
    else:
        result = await db.execute(
            select(UserDevice).where(
                and_(
                    UserDevice.user_id == current_user.id,
                    UserDevice.device_id == request.device_id
                )
            )
        )
        device = result.scalar_one_or_none()

        if device:
            device.fcm_token = request.fcm_token
            device.device_name = request.device_name
            device.last_active = now
        else:
            device = UserDevice(
                user_id=current_user.id,
                device_id=request.device_id,
                device_type=request.device_type,
                device_name=request.device_name,
                fcm_token=request.fcm_token,
                last_active=now,
            )
            db.add(device)

    await db.commit()
    await db.refresh(device)

    if request.fcm_token:
        await StarterRewardService.deliver_pending_push(
            db,
            current_user.id,
            tokens=[request.fcm_token],
        )

    return ApiResponse(
        success=True,
        message="Device registered",
        data=DeviceResponse(
            id=str(device.id),
            device_id=device.device_id,
            device_type=device.device_type,
            device_name=device.device_name,
            fcm_token=device.fcm_token,
            last_active=device.last_active,
            created_at=device.created_at
        )
    )


@router.delete("/{device_id}", response_model=MessageResponse)
async def unregister_device(
    device_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Unregister a device."""
    result = await db.execute(
        select(UserDevice).where(
            and_(
                UserDevice.user_id == current_user.id,
                UserDevice.device_id == device_id
            )
        )
    )
    device = result.scalar_one_or_none()
    
    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found"
        )
    
    await db.delete(device)
    await db.commit()
    
    return MessageResponse(message="Device unregistered successfully")
