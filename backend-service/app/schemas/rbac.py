"""
RBAC Schemas — Roles, Permissions, Audit Logs
"""

from typing import Optional, List
from datetime import datetime
from pydantic import BaseModel, Field, UUID4


# ── Role ──────────────────────────────────────────────────

class RoleBase(BaseModel):
    name: str = Field(..., max_length=50)
    slug: str = Field(..., max_length=50)
    description: Optional[str] = None
    level: int = 0


class RoleCreate(RoleBase):
    pass


class RoleUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=50)
    description: Optional[str] = None
    level: Optional[int] = None
    is_active: Optional[bool] = None


class RoleResponse(RoleBase):
    id: UUID4
    is_system: bool
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class RoleWithPermissions(RoleResponse):
    permissions: List["PermissionResponse"] = []


# ── Permission ────────────────────────────────────────────

class PermissionBase(BaseModel):
    name: str = Field(..., max_length=100)
    slug: str = Field(..., max_length=100)
    resource: str = Field(..., max_length=50)
    action: str = Field(..., max_length=50)
    description: Optional[str] = None


class PermissionCreate(PermissionBase):
    pass


class PermissionResponse(PermissionBase):
    id: UUID4
    created_at: datetime

    class Config:
        from_attributes = True


# ── Audit Log ─────────────────────────────────────────────

class AuditLogResponse(BaseModel):
    id: UUID4
    user_id: Optional[UUID4] = None
    action: str
    resource_type: str
    resource_id: Optional[str] = None
    details: Optional[str] = None
    ip_address: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


# ── Role Assignment ───────────────────────────────────────

class AssignRoleRequest(BaseModel):
    user_id: UUID4
    role_slug: str = Field(..., description="Role slug: user, admin, super_admin")


# ── Notification ──────────────────────────────────────────

class NotificationResponse(BaseModel):
    id: UUID4
    title: str
    body: str
    type: str
    data: Optional[dict] = None
    is_read: bool
    read_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


# Resolve forward references
RoleWithPermissions.model_rebuild()
