"""
RBAC (Role-Based Access Control) Models
Roles, Permissions, and Role-Permission mappings for admin/super_admin system.
"""

import uuid
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, Text, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.db_types import GUID


class Role(Base):
    """
    System roles: user, admin, super_admin.
    Hierarchical via 'level' field — higher level = more privileges.
    """

    __tablename__ = "roles"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4,
    )

    name: Mapped[str] = mapped_column(String(50), nullable=False, unique=True)
    slug: Mapped[str] = mapped_column(String(50), nullable=False, unique=True, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    level: Mapped[int] = mapped_column(Integer, nullable=False, default=0)  # 0=user, 1=admin, 2=super_admin
    is_system: Mapped[bool] = mapped_column(Boolean, default=True)  # System roles can't be deleted
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relationships
    permissions = relationship("RolePermission", back_populates="role", lazy="selectin")
    users = relationship("User", back_populates="role", lazy="noload")

    def __repr__(self) -> str:
        return f"<Role {self.slug} (level={self.level})>"


class Permission(Base):
    """
    Granular permissions: resource + action.
    Examples: courses:create, users:delete, analytics:read
    """

    __tablename__ = "permissions"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4,
    )

    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    slug: Mapped[str] = mapped_column(String(100), nullable=False, unique=True, index=True)
    resource: Mapped[str] = mapped_column(String(50), nullable=False, index=True)  # courses, users, achievements, etc.
    action: Mapped[str] = mapped_column(String(50), nullable=False)  # create, read, update, delete, manage
    description: Mapped[str] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # Relationships
    roles = relationship("RolePermission", back_populates="permission", lazy="noload")

    __table_args__ = (
        Index("idx_permission_resource_action", "resource", "action", unique=True),
    )

    def __repr__(self) -> str:
        return f"<Permission {self.resource}:{self.action}>"


class RolePermission(Base):
    """Junction table: which permissions belong to which role."""

    __tablename__ = "role_permissions"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4,
    )

    role_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("roles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    permission_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("permissions.id", ondelete="CASCADE"), nullable=False, index=True
    )

    granted_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # Relationships
    role = relationship("Role", back_populates="permissions")
    permission = relationship("Permission", back_populates="roles")

    __table_args__ = (
        Index("idx_role_permission_unique", "role_id", "permission_id", unique=True),
    )

    def __repr__(self) -> str:
        return f"<RolePermission role={self.role_id} perm={self.permission_id}>"


class AuditLog(Base):
    """
    Audit trail for admin actions.
    Tracks who did what, when, and to which resource.
    """

    __tablename__ = "audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4,
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    action: Mapped[str] = mapped_column(String(50), nullable=False)  # create, update, delete, login, etc.
    resource_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)  # user, course, achievement, etc.
    resource_id: Mapped[str] = mapped_column(String(255), nullable=True)  # UUID of affected resource
    details: Mapped[dict] = mapped_column(type_=Text, nullable=True)  # JSON-like description of changes
    ip_address: Mapped[str] = mapped_column(String(50), nullable=True)
    user_agent: Mapped[str] = mapped_column(String(500), nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)

    __table_args__ = (
        Index("idx_audit_user_action", "user_id", "action"),
        Index("idx_audit_resource", "resource_type", "resource_id"),
    )

    def __repr__(self) -> str:
        return f"<AuditLog {self.action} on {self.resource_type}/{self.resource_id}>"
