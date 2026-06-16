"""Transactional application of Ranking/Gamification Agent job artifacts."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.gamification import AchievementCRUD, LeaderboardCRUD, WalletCRUD
from app.models.gamification import (
    Achievement,
    ActivityFeed,
    LeaderboardEntry,
    ShopItem,
    UserAchievement,
    UserInventory,
)
from app.models.user import User
from app.models.ranking_agent import RankingAgentJob
from app.services.ranking_agent_jobs import RankingAgentJobService
from app.services.rank_service import apply_rank_info_to_user, calculate_rank

_LEAGUE_ORDER = [
    "bronze", "silver", "gold", "platinum", "sapphire", "ruby", "amethyst", "master"
]


class RankingAgentApplyService:
    @staticmethod
    async def apply(
        db: AsyncSession, job_id: uuid.UUID
    ) -> tuple[RankingAgentJob, dict]:
        job = await RankingAgentJobService.get(db, job_id, lock=True)
        if job is None:
            raise LookupError("Ranking-agent job not found")
        if job.status == "completed":
            return job, job.created_entity_ids
        if job.status != "preview_ready":
            raise ValueError("Only preview-ready jobs can be applied")
        if job.blocking_errors:
            raise ValueError("Job has blocking validation errors")
        if not job.artifact:
            raise ValueError("Job has no preview artifact")

        await RankingAgentJobService.transition(db, job, "applying", percent=100)

        if job.job_type == "league_reset":
            result = await _apply_league_reset(db, job.artifact)
        elif job.job_type == "xp_event":
            result = await _apply_xp_event(db, job.artifact, job.config)
        elif job.job_type == "achievement_batch":
            result = await _apply_achievement_batch(db, job.artifact, job.config)
        else:
            raise ValueError(f"Unknown job_type: {job.job_type}")

        job.created_entity_ids = result
        job.completed_at = datetime.now(UTC)
        await RankingAgentJobService.transition(db, job, "completed", percent=100)
        await db.flush()
        return job, result


async def _apply_league_reset(db: AsyncSession, artifact: dict) -> dict:
    week_start = datetime.fromisoformat(artifact["week_start"])
    week_end = datetime.fromisoformat(artifact["week_end"])
    next_week_start = week_end
    next_week_end = next_week_start + timedelta(days=7)

    promoted_ids: list[str] = []
    demoted_ids: list[str] = []

    for entry_data in artifact.get("promotions", []):
        await _process_league_change(
            db,
            entry_data=entry_data,
            old_league=entry_data["league"],
            new_league=entry_data["to"],
            week_start=week_start,
            next_week_start=next_week_start,
            next_week_end=next_week_end,
            is_promotion=True,
        )
        promoted_ids.append(entry_data["user_id"])

    for entry_data in artifact.get("demotions", []):
        await _process_league_change(
            db,
            entry_data=entry_data,
            old_league=entry_data["league"],
            new_league=entry_data["to"],
            week_start=week_start,
            next_week_start=next_week_start,
            next_week_end=next_week_end,
            is_promotion=False,
        )
        demoted_ids.append(entry_data["user_id"])

    # Create next-week entries for unchanged users
    unchanged_entries = await db.execute(
        select(LeaderboardEntry).where(
            and_(
                LeaderboardEntry.week_start == week_start,
                LeaderboardEntry.is_promoted.is_(False),
                LeaderboardEntry.is_demoted.is_(False),
            )
        )
    )
    for entry in unchanged_entries.scalars():
        if str(entry.user_id) not in promoted_ids and str(entry.user_id) not in demoted_ids:
            await _upsert_next_week_entry(
                db, entry.user_id, entry.league, next_week_start, next_week_end
            )

    return {
        "promoted_user_ids": promoted_ids,
        "demoted_user_ids": demoted_ids,
        "week_start": artifact["week_start"],
        "week_end": artifact["week_end"],
    }


async def _process_league_change(
    db: AsyncSession,
    *,
    entry_data: dict,
    old_league: str,
    new_league: str,
    week_start: datetime,
    next_week_start: datetime,
    next_week_end: datetime,
    is_promotion: bool,
) -> None:
    user_id = uuid.UUID(entry_data["user_id"])

    # Mark old entry
    old_entry = await db.scalar(
        select(LeaderboardEntry).where(
            and_(
                LeaderboardEntry.user_id == user_id,
                LeaderboardEntry.week_start == week_start,
            )
        )
    )
    if old_entry:
        if is_promotion:
            old_entry.is_promoted = True
        else:
            old_entry.is_demoted = True
        await db.flush()

    # Create new week entry in new league
    await _upsert_next_week_entry(db, user_id, new_league, next_week_start, next_week_end)

    # Update User.rank
    user = await db.get(User, user_id)
    if user:
        proficiency = getattr(user, "proficiency_level", None) or "A1"
        numeric = getattr(user, "numeric_level", None) or 1
        rank_info = calculate_rank(numeric, proficiency)
        apply_rank_info_to_user(user, rank_info)
        await db.flush()

    # Activity feed entry
    direction = "promoted" if is_promotion else "demoted"
    db.add(
        ActivityFeed(
            user_id=user_id,
            activity_type="league_change",
            activity_data={
                "from_league": old_league,
                "to_league": new_league,
                "direction": direction,
            },
            message=(
                f"You were {direction} to {new_league.capitalize()} league!"
                if is_promotion
                else f"You were moved to {new_league.capitalize()} league."
            ),
            is_public=True,
        )
    )
    await db.flush()


async def _upsert_next_week_entry(
    db: AsyncSession,
    user_id: uuid.UUID,
    league: str,
    week_start: datetime,
    week_end: datetime,
) -> None:
    existing = await db.scalar(
        select(LeaderboardEntry).where(
            and_(
                LeaderboardEntry.user_id == user_id,
                LeaderboardEntry.week_start == week_start,
            )
        )
    )
    if existing:
        existing.league = league
    else:
        db.add(
            LeaderboardEntry(
                user_id=user_id,
                week_start=week_start,
                week_end=week_end,
                league=league,
            )
        )
    await db.flush()


async def _apply_xp_event(db: AsyncSession, artifact: dict, config: dict) -> dict:
    expires_at = datetime.fromisoformat(artifact["expires_at"])
    target = artifact.get("target", "all")
    duration_hours = int(config.get("duration_hours", 24))
    event_name = artifact.get("event_name", "XP Event")

    # Find or create double_xp ShopItem
    shop_item = await db.scalar(
        select(ShopItem).where(
            and_(
                ShopItem.item_type == "double_xp",
                ShopItem.is_available.is_(True),
            )
        )
    )
    if shop_item is None:
        shop_item = ShopItem(
            name=event_name,
            description=f"System XP boost: {artifact.get('multiplier', 2.0)}x for {duration_hours}h",
            item_type="double_xp",
            price_gems=0,
            effects={"duration_hours": duration_hours, "multiplier": artifact.get("multiplier", 2.0)},
            is_available=True,
        )
        db.add(shop_item)
        await db.flush()

    # Determine target users from artifact sample + full query
    from app.models.gamification import LeaderboardEntry
    from app.models.user import User

    query = select(User.id).where(User.is_active.is_(True))
    if target.startswith("league:"):
        league = target.split(":", 1)[1]
        week_start, _ = LeaderboardCRUD.get_current_week_range()
        query = query.where(
            User.id.in_(
                select(LeaderboardEntry.user_id).where(
                    and_(
                        LeaderboardEntry.week_start == week_start,
                        LeaderboardEntry.league == league,
                    )
                )
            )
        )
    elif target.startswith("cefr:"):
        level = target.split(":", 1)[1].upper()
        query = query.where(User.proficiency_level == level)

    result = await db.execute(query)
    user_ids = result.scalars().all()

    granted = 0
    now = datetime.now(UTC)
    for uid in user_ids:
        existing = await db.scalar(
            select(UserInventory).where(
                and_(
                    UserInventory.user_id == uid,
                    UserInventory.shop_item_id == shop_item.id,
                    UserInventory.is_active.is_(True),
                )
            )
        )
        if existing:
            continue
        db.add(
            UserInventory(
                user_id=uid,
                shop_item_id=shop_item.id,
                quantity=1,
                is_active=True,
                activated_at=now,
                expires_at=expires_at,
                purchased_at=now,
            )
        )
        granted += 1

    await db.flush()
    return {
        "shop_item_id": str(shop_item.id),
        "granted_count": granted,
        "expires_at": expires_at.isoformat(),
        "target": target,
    }


async def _apply_achievement_batch(
    db: AsyncSession, artifact: dict, config: dict
) -> dict:
    slugs: list[str] = config.get("achievement_slugs", [])
    criteria: dict = config.get("criteria", {})

    from app.services.ranking_agent.achievement_batch import AchievementBatchEngine

    eligible_user_ids = await AchievementBatchEngine()._resolve_eligible_users(db, criteria)

    ach_rows = await db.execute(
        select(Achievement).where(Achievement.slug.in_(slugs))
    )
    achievements = ach_rows.scalars().all()

    granted_records: list[str] = []
    now = datetime.now(UTC)

    for ach in achievements:
        xp = ach.xp_reward or 0
        gems = ach.gems_reward or 0

        for uid in eligible_user_ids:
            existing = await db.scalar(
                select(UserAchievement).where(
                    and_(
                        UserAchievement.user_id == uid,
                        UserAchievement.achievement_id == ach.id,
                    )
                )
            )
            if existing:
                continue

            ua = UserAchievement(
                user_id=uid,
                achievement_id=ach.id,
                unlocked_at=now,
            )
            try:
                async with db.begin_nested():
                    db.add(ua)
                    await db.flush()
                    granted_records.append(f"{uid}:{ach.slug}")

                    if gems > 0:
                        await WalletCRUD.add_gems(
                            db,
                            uid,
                            gems,
                            source="achievement_batch",
                            description=f"Achievement: {ach.name}",
                            commit=False,
                        )
            except IntegrityError:
                pass  # race: already unlocked

    return {
        "granted_count": len(granted_records),
        "achievement_slugs": slugs,
        "eligible_user_count": len(eligible_user_ids),
    }
