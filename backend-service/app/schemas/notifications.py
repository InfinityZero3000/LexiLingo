"""Schemas for persisted notifications."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class NotificationResponse(BaseModel):
    """Notification item returned to the mobile app."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    body: str
    type: str
    data: dict | None = None
    is_read: bool
    read_at: datetime | None = None
    created_at: datetime
