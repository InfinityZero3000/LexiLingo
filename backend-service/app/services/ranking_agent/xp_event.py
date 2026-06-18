"""XP Event engine — computes preview for a system-wide XP boost grant."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import LeaderboardEntry, UserInventory
from app.models.progress import Streak
from app.models.user import User

_VALID_LEAGUES = {"bronze", "silver", "gold", "platinum", "sapphire", "ruby", "amethyst", "master"}
_VALID_CEFR = {"A1", "A2", "B1", "B2", "C1", "C2"}

_SAMPLE_LIMIT = 10


class XPEventEngine:
    async def calculate(self, db: AsyncSession, config: dict) -> dict:
        target: str = config.get("target", "all")
        duration_hours: int = int(config.get("duration_hours", 24))
        multiplier: float = float(config.get("multiplier", 2.0))
        name: str = config.get("name", "XP Event")

        query = select(User.id, User.username, User.email)

        if target.startswith("league:"):
            league = target.split(":", 1)[1]
            from app.crud.gamification import LeaderboardCRUD
            week_start, week_end = LeaderboardCRUD.get_current_week_range()
            league_user_ids = select(LeaderboardEntry.user_id).where(
                LeaderboardEntry.week_start == week_start,
                LeaderboardEntry.league == league,
            )
            query = query.where(User.id.in_(league_user_ids))
        elif target.startswith("cefr:"):
            level = target.split(":", 1)[1].upper()
            query = query.where(User.proficiency_level == level)

        query = query.where(User.is_active.is_(True))

        result = await db.execute(query)
        users = result.all()
        user_ids = [str(row[0]) for row in users]
        count = len(user_ids)

        sample = [
            {"user_id": str(r[0]), "username": r[1] or r[2].split("@")[0]}
            for r in users[:_SAMPLE_LIMIT]
        ]

        expires_at = datetime.now(UTC) + timedelta(hours=duration_hours)
        estimated_xp_delta = count * 50 * (multiplier - 1)

        return {
            "event_name": name,
            "target": target,
            "multiplier": multiplier,
            "duration_hours": duration_hours,
            "expires_at": expires_at.isoformat(),
            "target_user_count": count,
            "sample_users": sample,
            "estimated_total_xp_delta": f"+{estimated_xp_delta:,.0f} XP",
            "item_type": "double_xp",
        }
