"""
Device Routes

Endpoints for device registration and FCM token management
"""

from uuid import UUID
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User, UserDevice
from app.schemas.devices import (
    DeviceRegisterRequest,
    DeviceUpdateRequest,
    DeviceResponse
)
from app.schemas.common import MessageResponse
from app.schemas.response import ApiResponse
from typing import List

router = APIRouter(prefix="/devices", tags=["Devices"])


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
    # Check if device already exists
    result = await db.execute(
        select(UserDevice).where(
            and_(
                UserDevice.user_id == current_user.id,
                UserDevice.device_id == request.device_id
            )
        )
    )
    existing = result.scalar_one_or_none()
    
    if existing:
        # Update existing device
        existing.fcm_token = request.fcm_token
        existing.device_name = request.device_name or existing.device_name
        existing.last_active = datetime.utcnow()
        await db.commit()
        await db.refresh(existing)
        
        return ApiResponse(
            success=True,
            message="Device updated",
            data=DeviceResponse(
                id=str(existing.id),
                device_id=existing.device_id,
                device_type=existing.device_type,
                device_name=existing.device_name,
                fcm_token=existing.fcm_token,
                last_active=existing.last_active,
                created_at=existing.created_at
            )
        )
    
    # Create new device
    device = UserDevice(
        user_id=current_user.id,
        device_id=request.device_id,
        device_type=request.device_type,
        device_name=request.device_name,
        fcm_token=request.fcm_token,
        last_active=datetime.utcnow()
    )
    
    db.add(device)
    await db.commit()
    await db.refresh(device)
    
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


@router.put("/{device_id}", response_model=ApiResponse[DeviceResponse])
async def update_device(
    device_id: str,
    request: DeviceUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Update device FCM token.
    
    Used when FCM token is refreshed by the client.
    """
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
    
    if request.fcm_token is not None:
        device.fcm_token = request.fcm_token
    if request.device_name is not None:
        device.device_name = request.device_name
    device.last_active = datetime.utcnow()
    
    await db.commit()
    await db.refresh(device)
    
    return ApiResponse(
        success=True,
        message="Device updated",
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


@router.get("", response_model=ApiResponse[List[DeviceResponse]])
async def list_devices(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """List all registered devices for current user."""
    result = await db.execute(
        select(UserDevice).where(UserDevice.user_id == current_user.id)
    )
    devices = result.scalars().all()
    
    return ApiResponse(
        success=True,
        message=f"Found {len(devices)} devices",
        data=[
            DeviceResponse(
                id=str(d.id),
                device_id=d.device_id,
                device_type=d.device_type,
                device_name=d.device_name,
                fcm_token=d.fcm_token,
                last_active=d.last_active,
                created_at=d.created_at
            )
            for d in devices
        ]
    )
