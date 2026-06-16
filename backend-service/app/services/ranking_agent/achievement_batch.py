"""Achievement batch engine — computes preview for bulk achievement granting."""

from __future__ import annotations

from sqlalchemy import and_, func, not_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import Achievement, LeaderboardEntry, UserAchievement
from app.models.progress import Streak
from app.models.user import User
from app.models.vocabulary import UserVocabulary, VocabularyStatus


class AchievementBatchEngine:
    async def calculate(self, db: AsyncSession, config: dict) -> dict:
        slugs: list[str] = config.get("achievement_slugs", [])
        criteria: dict = config.get("criteria", {})

        eligible_user_ids = await self._resolve_eligible_users(db, criteria)

        achievement_rows = await db.execute(
            select(Achievement).where(Achievement.slug.in_(slugs))
        )
        achievements = achievement_rows.scalars().all()

        missing_slugs = set(slugs) - {a.slug for a in achievements}
        blocking_errors = [f"Achievement slug not found: '{s}'" for s in missing_slugs]

        results = []
        all_affected_user_ids: set[str] = set()
        total_xp = 0
        total_gems = 0

        for ach in achievements:
            already_unlocked = await db.scalar(
                select(func.count(UserAchievement.id)).where(
                    and_(
                        UserAchievement.achievement_id == ach.id,
                        UserAchievement.user_id.in_(eligible_user_ids),
                    )
                )
            ) or 0

            to_grant = len(eligible_user_ids) - already_unlocked

            results.append(
                {
                    "slug": ach.slug,
                    "name": ach.name,
                    "xp_reward": ach.xp_reward,
                    "gems_reward": ach.gems_reward,
                    "rarity": ach.rarity,
                    "eligible_users": len(eligible_user_ids),
                    "already_unlocked": already_unlocked,
                    "to_grant": to_grant,
                }
            )
            if to_grant > 0:
                all_affected_user_ids.update(
                    str(uid) for uid in eligible_user_ids
                )
                total_xp += to_grant * (ach.xp_reward or 0)
                total_gems += to_grant * (ach.gems_reward or 0)

        return {
            "achievements": results,
            "total_users_affected": len(all_affected_user_ids),
            "total_xp_to_award": total_xp,
            "total_gems_to_award": total_gems,
            "blocking_errors": blocking_errors,
        }

    async def _resolve_eligible_users(
        self, db: AsyncSession, criteria: dict
    ) -> list:
        query = select(User.id).where(User.is_active.is_(True))

        min_streak = criteria.get("min_streak")
        if min_streak is not None:
            streak_user_ids = select(Streak.user_id).where(
                Streak.current_streak >= min_streak
            )
            query = query.where(User.id.in_(streak_user_ids))

        min_vocab = criteria.get("min_vocabulary_mastered")
        if min_vocab is not None:
            vocab_user_ids = (
                select(UserVocabulary.user_id)
                .where(UserVocabulary.status == VocabularyStatus.MASTERED)
                .group_by(UserVocabulary.user_id)
                .having(func.count(UserVocabulary.id) >= min_vocab)
            )
            query = query.where(User.id.in_(vocab_user_ids))

        leagues = criteria.get("leagues")
        if leagues:
            from app.crud.gamification import LeaderboardCRUD
            week_start, _ = LeaderboardCRUD.get_current_week_range()
            league_user_ids = select(LeaderboardEntry.user_id).where(
                and_(
                    LeaderboardEntry.week_start == week_start,
                    LeaderboardEntry.league.in_([l.lower() for l in leagues]),
                )
            )
            query = query.where(User.id.in_(league_user_ids))

        cefr_levels = criteria.get("cefr_levels")
        if cefr_levels:
            query = query.where(
                User.proficiency_level.in_([l.upper() for l in cefr_levels])
            )

        result = await db.execute(query)
        return result.scalars().all()
