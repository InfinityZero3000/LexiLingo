"""One-time user reward grants."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, TZDateTime


class UserRewardGrant(Base):
    """Server-authoritative state for an idempotent user reward."""

    __tablename__ = "user_reward_grants"

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
    reward_key: Mapped[str] = mapped_column(String(100), nullable=False)
    gems_awarded: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    popup_seen_at: Mapped[datetime | None] = mapped_column(
        TZDateTime,
        nullable=True,
    )
    push_sent_at: Mapped[datetime | None] = mapped_column(
        TZDateTime,
        nullable=True,
    )

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "reward_key",
            name="uq_user_reward_grant_user_key",
        ),
    )
