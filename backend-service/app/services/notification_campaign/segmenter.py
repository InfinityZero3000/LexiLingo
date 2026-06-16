"""User segmentation engine for Notification Campaign Agent."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, and_, exists
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import LeaderboardEntry
from app.models.progress import Streak
from app.models.user import User, UserDevice

logger = logging.getLogger(__name__)


@dataclass
class SegmentResult:
    user_ids: list[str]
    fcm_token_map: dict[str, list[str]]  # user_id → [fcm_token, ...]
    audience_size: int
    sample_users: list[dict]
    filter_summary: dict


async def segment_users(
    db: AsyncSession,
    *,
    audience_type: str,
    filters: dict,
) -> SegmentResult:
    """Resolve the target user IDs and their FCM tokens based on audience config."""
    has_fcm_required = filters.get("has_fcm_token", True)
    leagues = filters.get("leagues")
    cefr_levels = filters.get("cefr_levels")
    min_streak = filters.get("min_streak")
    inactive_days = filters.get("inactive_days")

    conditions = [User.is_active == True]

    if cefr_levels:
        normalized = [lvl.upper() for lvl in cefr_levels]
        conditions.append(User.level.in_(normalized))

    if inactive_days is not None:
        cutoff = datetime.now(UTC) - timedelta(days=inactive_days)
        conditions.append(
            (User.last_login < cutoff) | (User.last_login == None)
        )

    if has_fcm_required:
        conditions.append(
            exists(
                select(UserDevice.id).where(
                    UserDevice.user_id == User.id,
                    UserDevice.fcm_token != None,
                    UserDevice.fcm_token != "",
                )
            )
        )

    if leagues:
        # Match users with a LeaderboardEntry in any of the given leagues (any week)
        conditions.append(
            exists(
                select(LeaderboardEntry.id).where(
                    LeaderboardEntry.user_id == User.id,
                    LeaderboardEntry.league.in_(leagues),
                )
            )
        )

    if min_streak is not None:
        conditions.append(
            exists(
                select(Streak.id).where(
                    Streak.user_id == User.id,
                    Streak.current_streak >= min_streak,
                )
            )
        )

    query = (
        select(User.id, User.username, User.email, User.level, User.last_login)
        .where(and_(*conditions))
        .order_by(User.created_at.desc())
    )
    rows = (await db.execute(query)).all()

    user_ids = [str(row.id) for row in rows]

    # Fetch FCM tokens for matched users
    fcm_token_map: dict[str, list[str]] = {}
    if user_ids:
        device_rows = (
            await db.execute(
                select(UserDevice.user_id, UserDevice.fcm_token).where(
                    UserDevice.user_id.in_([row.id for row in rows]),
                    UserDevice.fcm_token != None,
                    UserDevice.fcm_token != "",
                )
            )
        ).all()
        for dr in device_rows:
            uid = str(dr.user_id)
            fcm_token_map.setdefault(uid, []).append(dr.fcm_token)

    sample_users = [
        {
            "id": str(r.id),
            "username": r.username,
            "email": r.email,
            "cefr_level": r.level,
            "last_login": r.last_login.isoformat() if r.last_login else None,
            "has_fcm": str(r.id) in fcm_token_map,
        }
        for r in rows[:5]
    ]

    filter_summary = {
        "audience_type": audience_type,
        "leagues": leagues,
        "cefr_levels": cefr_levels,
        "min_streak": min_streak,
        "inactive_days": inactive_days,
        "has_fcm_token": has_fcm_required,
    }

    logger.info(
        "Segmentation complete: %d users matched (%d with FCM tokens)",
        len(user_ids),
        len(fcm_token_map),
    )

    return SegmentResult(
        user_ids=user_ids,
        fcm_token_map=fcm_token_map,
        audience_size=len(user_ids),
        sample_users=sample_users,
        filter_summary=filter_summary,
    )
