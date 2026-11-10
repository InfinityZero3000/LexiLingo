"""Operator-editable settings and the ledger of gems admins hand out."""

import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, PortableJSON, TZDateTime


def _now() -> datetime:
    return datetime.now(timezone.utc)


class AppSetting(Base):
    """One key, one JSON value. Env values in config.py are the fallback when a key is unset."""

    __tablename__ = "app_settings"

    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    value: Mapped[Any] = mapped_column(PortableJSON, nullable=False)
    updated_by: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(TZDateTime, default=_now, onupdate=_now, nullable=False)


class AdminGemGrant(Base):
    """Every gem an admin gifted or adjusted. The daily budget is summed from here."""

    __tablename__ = "admin_gem_grants"
    __table_args__ = (Index("ix_admin_gem_grants_actor_created", "actor_id", "created_at"),)

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    kind: Mapped[str] = mapped_column(String(10), nullable=False)  # gift | adjust
    amount: Mapped[int] = mapped_column(Integer, nullable=False)  # signed: adjust may take gems back
    reason: Mapped[str] = mapped_column(String(300), nullable=False)
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=_now, nullable=False)
