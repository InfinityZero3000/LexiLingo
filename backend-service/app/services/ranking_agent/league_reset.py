"""League reset engine — computes promotion/demotion preview for a given week."""

from __future__ import annotations

import math
from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import LeaderboardEntry
from app.models.user import User

LEAGUE_ORDER = [
    "bronze", "silver", "gold", "platinum", "sapphire", "ruby", "amethyst", "master"
]


def _week_range_for(week_start_iso: str | None) -> tuple[datetime, datetime]:
    """Return (week_start, week_end) for the given ISO date or the last completed week."""
    if week_start_iso:
        week_start = datetime.fromisoformat(week_start_iso).replace(
            hour=0, minute=0, second=0, microsecond=0, tzinfo=UTC
        )
    else:
        now = datetime.now(UTC)
        days_since_monday = now.weekday()
        last_monday = now - timedelta(days=days_since_monday + 7)
        week_start = last_monday.replace(hour=0, minute=0, second=0, microsecond=0)
    week_end = week_start + timedelta(days=7)
    return week_start, week_end


def _next_league(current: str, direction: int) -> str:
    idx = LEAGUE_ORDER.index(current)
    new_idx = max(0, min(len(LEAGUE_ORDER) - 1, idx + direction))
    return LEAGUE_ORDER[new_idx]


class LeagueResetEngine:
    def __init__(
        self,
        promotion_threshold: float = 0.10,
        demotion_threshold: float = 0.10,
    ) -> None:
        self._promo_pct = promotion_threshold
        self._demo_pct = demotion_threshold

    async def calculate(
        self,
        db: AsyncSession,
        config: dict,
    ) -> dict:
        week_start, week_end = _week_range_for(config.get("week_start"))

        rows = await db.execute(
            select(LeaderboardEntry, User.username, User.email)
            .join(User, LeaderboardEntry.user_id == User.id)
            .where(
                and_(
                    LeaderboardEntry.week_start == week_start,
                    LeaderboardEntry.week_end == week_end,
                )
            )
            .order_by(LeaderboardEntry.league, LeaderboardEntry.xp_earned.desc())
        )
        entries_with_users = rows.all()

        by_league: dict[str, list[dict]] = {l: [] for l in LEAGUE_ORDER}
        for entry, username, email in entries_with_users:
            by_league[entry.league].append(
                {
                    "user_id": str(entry.user_id),
                    "username": username or email.split("@")[0],
                    "league": entry.league,
                    "xp_earned": entry.xp_earned,
                    "lessons_completed": entry.lessons_completed,
                    "entry_id": str(entry.id),
                }
            )

        promotions = []
        demotions = []
        unchanged_count = 0
        league_summary: dict[str, dict] = {}

        for league, members in by_league.items():
            n = len(members)
            league_summary[league] = {"total": n, "promoted": 0, "demoted": 0, "unchanged": 0}
            if n == 0:
                continue

            promo_cut = math.ceil(n * self._promo_pct)
            demo_cut = math.ceil(n * self._demo_pct)

            for i, m in enumerate(members):
                rank_pos = i + 1
                if league != "master" and rank_pos <= promo_cut:
                    to_league = _next_league(league, +1)
                    promotions.append({**m, "to": to_league, "rank_pos": rank_pos})
                    league_summary[league]["promoted"] += 1
                elif league != "bronze" and rank_pos > n - demo_cut:
                    to_league = _next_league(league, -1)
                    demotions.append({**m, "to": to_league, "rank_pos": rank_pos})
                    league_summary[league]["demoted"] += 1
                else:
                    unchanged_count += 1
                    league_summary[league]["unchanged"] += 1

        total = sum(d["total"] for d in league_summary.values())
        week_label = (
            f"{week_start.strftime('%Y-%m-%d')} → "
            f"{(week_end - timedelta(seconds=1)).strftime('%Y-%m-%d')}"
        )

        return {
            "week": week_label,
            "week_start": week_start.isoformat(),
            "week_end": week_end.isoformat(),
            "total_participants": total,
            "promotions": promotions,
            "demotions": demotions,
            "unchanged": unchanged_count,
            "league_summary": league_summary,
        }
