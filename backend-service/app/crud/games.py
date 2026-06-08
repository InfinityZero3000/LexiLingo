"""Persistence helpers for game sessions."""

import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.games import GameSession


async def create_game_session(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    game_type: str,
    cefr_level: str,
    expected_items: list[dict[str, Any]],
    category: str | None = None,
    session_metadata: dict[str, Any] | None = None,
) -> GameSession:
    session = GameSession(
        id=uuid.uuid4(),
        user_id=user_id,
        game_type=game_type,
        cefr_level=cefr_level,
        category=category,
        total_questions=len(expected_items),
        started_at=datetime.now(timezone.utc),
        session_data={
            "expected_items": expected_items,
            **(session_metadata or {}),
        },
    )
    db.add(session)
    await db.commit()
    return session


async def get_game_session_for_update(
    db: AsyncSession,
    *,
    session_id: uuid.UUID,
) -> GameSession | None:
    result = await db.execute(
        select(GameSession)
        .where(GameSession.id == session_id)
        .with_for_update()
    )
    return result.scalar_one_or_none()
