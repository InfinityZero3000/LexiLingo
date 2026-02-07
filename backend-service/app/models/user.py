"""
User Model
Extended for Phase 1: Authentication & Secure User Foundation
"""

import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Integer, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.db_types import GUID


class User(Base):
    """User model for authentication and profile."""
    
    __tablename__ = "users"
    
    # Primary key
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4,
        index=True
    )
    
    # Authentication
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    username: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    
    # Profile
    display_name: Mapped[str] = mapped_column(String(100), nullable=True)
    avatar_url: Mapped[str] = mapped_column(String(500), nullable=True)
    
    # Learning preferences
    native_language: Mapped[str] = mapped_column(String(10), default="vi")
    target_language: Mapped[str] = mapped_column(String(10), default="en")
    level: Mapped[str] = mapped_column(String(20), default="A1")  # A1, A2, B1, B2, C1, C2
    total_xp: Mapped[int] = mapped_column(Integer, default=0, nullable=False)  # Total XP earned
    numeric_level: Mapped[int] = mapped_column(Integer, default=1, nullable=False)  # Gamification level (1, 2, 3...)
    rank: Mapped[str] = mapped_column(String(20), default="bronze", nullable=False)  # bronze, silver, gold, platinum, diamond, master
    
    # RBAC
    role_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("roles.id", ondelete="SET NULL"),
        nullable=True,  # null = default 'user' role (backward compatible)
        index=True,
    )
    
    # Status & Verification (Phase 1 requirements)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    provider: Mapped[str] = mapped_column(String(20), default="local")  # local, google, facebook
    
    # Relationships
    role = relationship("Role", back_populates="users", lazy="selectin")
    
    @property
    def role_slug(self) -> str:
        """Return role slug for API serialization."""
        if self.role and hasattr(self.role, "slug"):
            return self.role.slug
        return "user"  # default
    
    @property
    def role_level(self) -> int:
        """Return role level for permission checks."""
        if self.role and hasattr(self.role, "level"):
            return self.role.level
        return 0

    @property
    def is_admin(self) -> bool:
        return self.role_level >= 1

    @property
    def is_super_admin(self) -> bool:
        return self.role_level >= 2
    
    # Timestamps
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    last_login: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    last_login_ip: Mapped[str] = mapped_column(String(50), nullable=True)
    
    def __repr__(self) -> str:
        return f"<User {self.username}>"


class UserDevice(Base):
    """User devices for FCM push notifications."""
    
    __tablename__ = "user_devices"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        nullable=False,
        index=True
    )
    
    device_id: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    fcm_token: Mapped[str] = mapped_column(String(500), nullable=True)
    device_type: Mapped[str] = mapped_column(String(20), nullable=False)  # ios, android, web
    device_name: Mapped[str] = mapped_column(String(100), nullable=True)
    
    last_active: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<UserDevice {self.device_type} - {self.device_id[:8]}>"


class RefreshToken(Base):
    """Refresh tokens for JWT authentication with rotation support."""
    
    __tablename__ = "refresh_tokens"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        nullable=False,
        index=True
    )
    
    token: Mapped[str] = mapped_column(String(500), unique=True, nullable=False, index=True)
    device_id: Mapped[str] = mapped_column(String(255), nullable=True)
    
    is_revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    is_used: Mapped[bool] = mapped_column(Boolean, default=False)
    
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    revoked_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    
    def __repr__(self) -> str:
        return f"<RefreshToken {self.token[:16]}...>"
