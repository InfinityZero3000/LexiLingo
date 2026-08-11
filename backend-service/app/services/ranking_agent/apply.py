"""Transactional application of Ranking/Gamification Agent job artifacts."""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.gamification import LeaderboardCRUD
from app.models.games import XPTransaction
from app.models.gamification import (
    Achievement,
    ActivityFeed,
    LeaderboardEntry,
    ShopItem,
    UserAchievement,
    UserInventory,
    UserWallet,
    WalletTransaction,
)
from app.models.progress import DailyActivity
from app.models.ranking_agent import RankingAgentJob
from app.models.user import User
from app.services.level_service import calculate_numeric_level
from app.services.rank_service import apply_rank_info_to_user, calculate_rank
from app.services.ranking_agent_jobs import RankingAgentJobService

_LEAGUE_ORDER = ["bronze", "silver", "gold", "platinum", "sapphire", "ruby", "amethyst", "master"]
_QUERY_CHUNK_SIZE = 10_000


class RankingAgentApplyService:
    @staticmethod
    async def apply(db: AsyncSession, job_id: uuid.UUID) -> tuple[RankingAgentJob, dict]:
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
            effects={
                "duration_hours": duration_hours,
                "multiplier": artifact.get("multiplier", 2.0),
            },
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


async def _apply_achievement_batch(db: AsyncSession, artifact: dict, config: dict) -> dict:
    slugs: list[str] = config.get("achievement_slugs", [])
    criteria: dict = config.get("criteria", {})

    from app.services.ranking_agent.achievement_batch import AchievementBatchEngine

    eligible_user_ids = await AchievementBatchEngine()._resolve_eligible_users(db, criteria)

    ach_rows = await db.execute(select(Achievement).where(Achievement.slug.in_(slugs)))
    achievements = ach_rows.scalars().all()

    now = datetime.now(UTC)
    achievement_ids = [achievement.id for achievement in achievements]
    existing_pairs: set[tuple[uuid.UUID, uuid.UUID]] = set()
    for user_offset in range(0, len(eligible_user_ids), _QUERY_CHUNK_SIZE):
        user_chunk = eligible_user_ids[user_offset : user_offset + _QUERY_CHUNK_SIZE]
        for achievement_offset in range(0, len(achievement_ids), _QUERY_CHUNK_SIZE):
            achievement_chunk = achievement_ids[
                achievement_offset : achievement_offset + _QUERY_CHUNK_SIZE
            ]
            existing_rows = await db.execute(
                select(
                    UserAchievement.user_id,
                    UserAchievement.achievement_id,
                ).where(
                    UserAchievement.user_id.in_(user_chunk),
                    UserAchievement.achievement_id.in_(achievement_chunk),
                )
            )
            existing_pairs.update(existing_rows.all())
    candidates = [
        (user_id, achievement)
        for achievement in achievements
        for user_id in eligible_user_ids
        if (user_id, achievement.id) not in existing_pairs
    ]

    inserted_pairs: set[tuple[uuid.UUID, uuid.UUID]] = set()
    if candidates:
        unlock_rows = [
            {
                "id": uuid.uuid4(),
                "user_id": user_id,
                "achievement_id": achievement.id,
                "unlocked_at": now,
            }
            for user_id, achievement in candidates
        ]
        inserted = await db.execute(
            pg_insert(UserAchievement)
            .on_conflict_do_nothing(constraint="uq_user_achievement")
            .returning(UserAchievement.user_id, UserAchievement.achievement_id),
            unlock_rows,
        )
        inserted_pairs = set(inserted.all())

    granted = [
        (user_id, achievement)
        for user_id, achievement in candidates
        if (user_id, achievement.id) in inserted_pairs
    ]
    await _grant_achievement_rewards(db, granted, now)

    return {
        "granted_count": len(granted),
        "achievement_slugs": slugs,
        "eligible_user_count": len(eligible_user_ids),
    }


async def _grant_achievement_rewards(
    db: AsyncSession,
    grants: list[tuple[uuid.UUID, Achievement]],
    now: datetime,
) -> None:
    """Batch exact XP and gem rewards for newly inserted unlock pairs."""
    if not grants:
        return

    user_ids = {user_id for user_id, _ in grants}
    users = []
    ordered_user_ids = sorted(user_ids, key=str)
    for offset in range(0, len(ordered_user_ids), _QUERY_CHUNK_SIZE):
        users.extend(
            (
                await db.scalars(
                    select(User)
                    .where(User.id.in_(ordered_user_ids[offset : offset + _QUERY_CHUNK_SIZE]))
                    .with_for_update()
                )
            ).all()
        )
    users_by_id = {user.id: user for user in users}

    xp_rows = []
    xp_by_user: dict[uuid.UUID, int] = defaultdict(int)
    running_xp = {user.id: user.total_xp or 0 for user in users}
    for user_id, achievement in grants:
        xp = achievement.xp_reward or 0
        user = users_by_id.get(user_id)
        if not user or xp <= 0:
            continue
        old_xp = running_xp[user_id]
        new_xp = old_xp + xp
        old_level = calculate_numeric_level(old_xp)
        new_level = calculate_numeric_level(new_xp)
        xp_rows.append(
            {
                "id": uuid.uuid4(),
                "user_id": user_id,
                "amount": xp,
                "base_amount": xp,
                "multiplier": 1.0,
                "source": "achievement_batch",
                "source_id": str(achievement.id),
                "source_detail": achievement.slug,
                "level_before": old_level,
                "level_after": new_level,
                "leveled_up": new_level > old_level,
                "created_at": now,
            }
        )
        running_xp[user_id] = new_xp
        xp_by_user[user_id] += xp

    if xp_rows:
        inserted_xp = await db.execute(
            pg_insert(XPTransaction)
            .on_conflict_do_nothing(
                index_elements=["user_id", "source", "source_id"],
                index_where=XPTransaction.source_id.is_not(None),
            )
            .returning(XPTransaction.user_id, XPTransaction.source_id),
            xp_rows,
        )
        inserted_xp_keys = set(inserted_xp.all())
        xp_by_user.clear()
        for row in xp_rows:
            if (row["user_id"], row["source_id"]) in inserted_xp_keys:
                xp_by_user[row["user_id"]] += row["amount"]

    for user_id, xp in xp_by_user.items():
        user = users_by_id[user_id]
        user.total_xp = (user.total_xp or 0) + xp
        user.numeric_level = calculate_numeric_level(user.total_xp)
        apply_rank_info_to_user(
            user,
            calculate_rank(user.numeric_level, user.level or "A1"),
        )

    if xp_by_user:
        today = now.date()
        daily_rows = [
            {
                "id": uuid.uuid4(),
                "user_id": user_id,
                "activity_date": today,
                "xp_earned": xp,
            }
            for user_id, xp in xp_by_user.items()
        ]
        daily_insert = pg_insert(DailyActivity)
        await db.execute(
            daily_insert.on_conflict_do_update(
                index_elements=["user_id", "activity_date"],
                set_={"xp_earned": DailyActivity.xp_earned + daily_insert.excluded.xp_earned},
            ),
            daily_rows,
        )

        week_start, week_end = LeaderboardCRUD.get_current_week_range()
        leaderboard_rows = [
            {
                "id": uuid.uuid4(),
                "user_id": user_id,
                "week_start": week_start,
                "week_end": week_end,
                "league": users_by_id[user_id].rank,
                "xp_earned": xp,
            }
            for user_id, xp in xp_by_user.items()
        ]
        leaderboard_insert = pg_insert(LeaderboardEntry)
        await db.execute(
            leaderboard_insert.on_conflict_do_update(
                constraint="uq_leaderboard_user_week",
                set_={
                    "xp_earned": LeaderboardEntry.xp_earned + leaderboard_insert.excluded.xp_earned,
                    "league": leaderboard_insert.excluded.league,
                },
            ),
            leaderboard_rows,
        )

    gem_grants = [
        (user_id, achievement)
        for user_id, achievement in grants
        if (achievement.gems_reward or 0) > 0
    ]
    if not gem_grants:
        return

    gem_user_ids = {user_id for user_id, _ in gem_grants}
    wallet_rows = [
        {
            "id": uuid.uuid4(),
            "user_id": user_id,
            "gems": 0,
            "total_gems_earned": 0,
            "total_gems_spent": 0,
        }
        for user_id in gem_user_ids
    ]
    await db.execute(
        pg_insert(UserWallet).on_conflict_do_nothing(index_elements=["user_id"]),
        wallet_rows,
    )
    wallets = []
    ordered_gem_user_ids = sorted(gem_user_ids, key=str)
    for offset in range(0, len(ordered_gem_user_ids), _QUERY_CHUNK_SIZE):
        wallets.extend(
            (
                await db.scalars(
                    select(UserWallet)
                    .where(
                        UserWallet.user_id.in_(
                            ordered_gem_user_ids[offset : offset + _QUERY_CHUNK_SIZE]
                        )
                    )
                    .with_for_update()
                )
            ).all()
        )
    wallets_by_user = {wallet.user_id: wallet for wallet in wallets}
    wallet_transactions = []
    for user_id, achievement in gem_grants:
        wallet = wallets_by_user[user_id]
        gems = achievement.gems_reward or 0
        wallet.gems += gems
        wallet.total_gems_earned += gems
        wallet_transactions.append(
            WalletTransaction(
                wallet_id=wallet.id,
                user_id=user_id,
                transaction_type="earn",
                amount=gems,
                balance_after=wallet.gems,
                source="achievement_batch",
                reference_id=str(achievement.id),
                description=f"Achievement: {achievement.name}",
            )
        )
    db.add_all(wallet_transactions)
