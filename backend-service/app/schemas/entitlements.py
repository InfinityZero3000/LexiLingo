"""Entitlement API schemas."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict


class EntitlementStatus(BaseModel):
    model_config = ConfigDict(extra="forbid")

    entitlement_id: str
    active: bool
    product_id: str | None = None
    expires_at: datetime | None = None
    source: str
    synced_at: datetime | None = None
    degraded: bool = False
