"""Server-verified user entitlement state (source of truth for premium gating)."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, TZDateTime


class UserEntitlement(Base):
    """One row per (user, entitlement id), refreshed from RevenueCat on sync."""

    __tablename__ = "user_entitlements"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    entitlement_id: Mapped[str] = mapped_column(String(100), nullable=False)
    product_id: Mapped[str | None] = mapped_column(String(200), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    expires_at: Mapped[datetime | None] = mapped_column(
        TZDateTime,
        nullable=True,
    )
    source: Mapped[str] = mapped_column(String(20), nullable=False, default="revenuecat")
    synced_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "entitlement_id",
            name="uq_user_entitlement_user_entitlement",
        ),
    )
