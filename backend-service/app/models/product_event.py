import uuid
from datetime import UTC, datetime

from sqlalchemy import ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, PortableJSON, TZDateTime


def utc_now() -> datetime:
    return datetime.now(UTC)


class ProductEvent(Base):
    """Durable product interaction event."""

    __tablename__ = "product_events"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    event_id: Mapped[uuid.UUID] = mapped_column(GUID(), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    event_name: Mapped[str] = mapped_column(String(100), nullable=False)
    properties: Mapped[dict] = mapped_column(PortableJSON, nullable=False, default=dict)
    source: Mapped[str] = mapped_column(String(50), nullable=False)
    client_timestamp: Mapped[datetime] = mapped_column(TZDateTime, nullable=False)
    created_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=False, default=utc_now)

    __table_args__ = (
        UniqueConstraint("user_id", "event_id", name="uq_product_events_user_event"),
        Index("ix_product_events_event_created", "event_name", "created_at"),
        Index("ix_product_events_user_created", "user_id", "created_at"),
    )
