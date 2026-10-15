"""In-app promotional banner model (hero/sidebar/interstitial CTAs)."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Boolean, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, TZDateTime


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Banner(Base):
    """Admin-managed promo banner shown to learners on scheduled, targeted slots."""

    __tablename__ = "banners"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    image_url: Mapped[str] = mapped_column(String(1000), nullable=False)
    link_url: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)

    # hero | sidebar | interstitial
    position: Mapped[str] = mapped_column(String(20), default="hero", nullable=False, index=True)
    priority: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)

    # Schedule: null start_at means "already started", null end_at means "no end".
    start_at: Mapped[Optional[datetime]] = mapped_column(TZDateTime, nullable=True)
    end_at: Mapped[Optional[datetime]] = mapped_column(TZDateTime, nullable=True)

    # Targeting: null means "no restriction on this axis".
    target_min_level: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    target_max_level: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    target_language: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)

    created_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=_utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime, default=_utcnow, onupdate=_utcnow, nullable=False
    )

    __table_args__ = (
        Index("ix_banners_active_position_priority", "is_active", "position", "priority"),
    )

    def __repr__(self) -> str:
        return f"<Banner {self.title} position={self.position} active={self.is_active}>"
