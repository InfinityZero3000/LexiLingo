"""
RBAC Schemas — Roles, Permissions, Audit Logs
"""

from typing import Optional, List
from uuid import UUID
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field, field_validator


# ── Role ──────────────────────────────────────────────────

class RoleBase(BaseModel):
    name: str = Field(..., max_length=50)
    slug: str = Field(..., max_length=50)
    description: Optional[str] = None
    level: int = 0


# Built-in slugs carry behaviour elsewhere, so a new role may not take one.
RESERVED_ROLE_SLUGS = frozenset({"user", "test", "admin", "super_admin"})


class RoleCreate(BaseModel):
    """A custom admin role. It is always admin level; permissions decide what it may do."""

    name: str = Field(..., min_length=2, max_length=50)
    slug: str = Field(..., pattern=r"^[a-z][a-z0-9_]{1,49}$")
    description: Optional[str] = Field(None, max_length=500)
    permission_slugs: List[str] = Field(default_factory=list)

    @field_validator("name")
    @classmethod
    def strip_name(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 2:
            raise ValueError("Name must have at least 2 characters")
        return value


class RoleUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=50)
    description: Optional[str] = None
    level: Optional[int] = None
    is_active: Optional[bool] = None


class RoleResponse(RoleBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    is_system: bool
    is_active: bool
    created_at: datetime


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
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    created_at: datetime


# ── Audit Log ─────────────────────────────────────────────

class AuditLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: Optional[UUID] = None
    action: str
    resource_type: str
    resource_id: Optional[str] = None
    details: Optional[str] = None
    ip_address: Optional[str] = None
    created_at: datetime


# ── Role Assignment ───────────────────────────────────────


# ── Notification ─────────────────────────────

class NotificationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    body: str
    type: str
    data: Optional[dict] = None
    is_read: bool
    read_at: Optional[datetime] = None
    created_at: datetime


# Resolve forward references
RoleWithPermissions.model_rebuild()
