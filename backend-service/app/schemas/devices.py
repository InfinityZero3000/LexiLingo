"""
Device Schemas

Schemas for device registration and FCM token management
"""

from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime


class DeviceRegisterRequest(BaseModel):
    """Device registration request."""
    device_id: str = Field(..., description="Unique device identifier")
    device_type: str = Field(..., description="Device type: ios, android, web")
    device_name: Optional[str] = Field(None, description="Human readable device name")
    fcm_token: Optional[str] = Field(None, description="Firebase Cloud Messaging token")


class DeviceUpdateRequest(BaseModel):
    """Device update request (for FCM token updates)."""
    fcm_token: Optional[str] = Field(None, description="New FCM token")
    device_name: Optional[str] = Field(None, description="Updated device name")


class DeviceResponse(BaseModel):
    """Device response."""
    id: str
    device_id: str
    device_type: str
    device_name: Optional[str]
    fcm_token: Optional[str]
    last_active: datetime
    created_at: datetime

    class Config:
        from_attributes = True
