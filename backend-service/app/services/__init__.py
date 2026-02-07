"""
Achievement Checker Service
Stateless service to evaluate and unlock achievements based on user actions.

This service checks achievement conditions and automatically unlocks badges
when conditions are met. It's designed to be called after specific user actions.
"""

from typing import List, Optional, Dict, Any
from uuid import UUID
from datetime import datetime
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import Achievement, UserAchievement, ChallengeRewardClaim
from app.models.progress import UserCourseProgress, LessonCompletion, Streak, DailyActivity
from app.models.vocabulary import UserVocabulary, VocabularyStatus
from app.models.user import User


# Mapping of triggers to achievement condition types
TRIGGER_CONDITIONS = {
    "lesson_complete": [
        "lesson_complete", "xp_earned", "course_complete",
        "numeric_level", "speed_lesson",
    ],
    "streak_update": ["reach_streak", "comeback"],
    "vocab_review": ["vocab_mastered", "vocab_reviewed"],
    "quiz_complete": ["perfect_score", "quiz_complete", "first_perfect"],
    "voice_practice": ["voice_practice"],
    "xp_earned": ["xp_earned", "numeric_level"],
    "study_session": ["study_time_night", "study_time_morning"],
    "grammar_complete": ["grammar_mastered"],
    "culture_complete": ["culture_lesson"],
    "writing_complete": ["writing_complete"],
    "listening_complete": ["listening_complete"],
    "social_action": ["social_interaction", "help_others"],
    "chat_complete": ["chat_complete"],
    "daily_challenge": ["daily_challenge_complete"],
}


class AchievementCheckerService:
    """
    Service to check and unlock achievements.
    
    Usage:
        checker = AchievementCheckerService(db)
        newly_unlocked = await checker.check_by_trigger(user_id, "lesson_complete")
    """
    
    def __init__(self, db: AsyncSession):
        self.db = db
    
    async def check_all(self, user_id: UUID) -> List[Achievement]:
        """
        Check all achievements for a user.
        Returns list of newly unlocked achievements.
        
        Use sparingly as this checks ALL conditions.
        Prefer check_by_trigger() for better performance.
        """
        # Get all achievements not yet unlocked by user
        unlocked_ids = await self._get_unlocked_achievement_ids(user_id)
        
        result = await self.db.execute(
            select(Achievement).where(~Achievement.id.in_(unlocked_ids))
        )
        pending_achievements = list(result.scalars().all())
        
        # Get user stats once for all evaluations
        user_stats = await self._get_user_stats(user_id)
        
        newly_unlocked = []
        for achievement in pending_achievements:
            if await self._evaluate_condition(user_id, achievement, user_stats):
                unlocked = await self._unlock_achievement(user_id, achievement)
                if unlocked:
                    newly_unlocked.append(achievement)
        
        return newly_unlocked
    
    async def check_by_trigger(self, user_id: UUID, trigger: str) -> List[Achievement]:
        """
        Check only achievements related to a specific trigger.
        More efficient than check_all().
        
        Args:
            user_id: User UUID
            trigger: One of "lesson_complete", "streak_update", "vocab_review", 
                     "quiz_complete", "voice_practice", "xp_earned"
        
        Returns:
            List of newly unlocked achievements
        """
        condition_types = TRIGGER_CONDITIONS.get(trigger, [])
        if not condition_types:
            return []
        
        # Get pending achievements of relevant types
        unlocked_ids = await self._get_unlocked_achievement_ids(user_id)
        
        result = await self.db.execute(
            select(Achievement).where(
                and_(
                    ~Achievement.id.in_(unlocked_ids) if unlocked_ids else True,
                    Achievement.condition_type.in_(condition_types)
                )
            )
        )
        pending_achievements = list(result.scalars().all())
        
        if not pending_achievements:
            return []
        
        # Get only needed stats
        user_stats = await self._get_user_stats(user_id, condition_types)
        
        newly_unlocked = []
        for achievement in pending_achievements:
            if await self._evaluate_condition(user_id, achievement, user_stats):
                unlocked = await self._unlock_achievement(user_id, achievement)
                if unlocked:
                    newly_unlocked.append(achievement)
        
        return newly_unlocked
    
    async def _get_unlocked_achievement_ids(self, user_id: UUID) -> List[UUID]:
        """Get IDs of achievements already unlocked by user"""
        result = await self.db.execute(
            select(UserAchievement.achievement_id).where(
                UserAchievement.user_id == user_id
            )
        )
        return [row[0] for row in result.all()]
    
    async def _get_user_stats(
        self, 
        user_id: UUID, 
        condition_types: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Fetch user statistics needed for achievement evaluation.
        Only fetches stats relevant to the condition_types if provided.
        """
        stats = {}
        
        # Determine which stats to fetch
        fetch_all = condition_types is None
        need_lessons = fetch_all or "lesson_complete" in condition_types or "course_complete" in condition_types
        need_streak = fetch_all or "reach_streak" in condition_types or "comeback" in condition_types
        need_vocab = fetch_all or "vocab_mastered" in condition_types or "vocab_reviewed" in condition_types
        need_xp = fetch_all or "xp_earned" in condition_types or "numeric_level" in condition_types
        need_quiz = fetch_all or "perfect_score" in condition_types or "quiz_complete" in condition_types or "first_perfect" in condition_types
        need_voice = fetch_all or "voice_practice" in condition_types
        need_level = fetch_all or "numeric_level" in condition_types
        need_time = fetch_all or "study_time_night" in condition_types or "study_time_morning" in condition_types or "speed_lesson" in condition_types
        need_skills = fetch_all or any(ct in (condition_types or []) for ct in ["grammar_mastered", "culture_lesson", "writing_complete", "listening_complete"])
        need_social = fetch_all or any(ct in (condition_types or []) for ct in ["social_interaction", "chat_complete", "help_others"])
        need_challenges = fetch_all or "daily_challenge_complete" in condition_types
        
        # Fetch lesson completion count
        if need_lessons:
            result = await self.db.execute(
                select(func.count(LessonCompletion.id)).where(
                    and_(
                        LessonCompletion.user_id == user_id,
                        LessonCompletion.is_passed == True
                    )
                )
            )
            stats["lessons_completed"] = result.scalar() or 0
            
            # Count completed courses (progress_percentage >= 100)
            result = await self.db.execute(
                select(func.count(UserCourseProgress.id)).where(
                    and_(
                        UserCourseProgress.user_id == user_id,
                        UserCourseProgress.progress_percentage >= 100
                    )
                )
            )
            stats["courses_completed"] = result.scalar() or 0
        
        # Fetch streak from Streak model
        if need_streak:
            result = await self.db.execute(
                select(Streak.current_streak, Streak.longest_streak).where(Streak.user_id == user_id)
            )
            row = result.first()
            if row:
                stats["current_streak"] = row[0] or 0
                stats["longest_streak"] = row[1] or 0
            else:
                stats["current_streak"] = 0
                stats["longest_streak"] = 0
        
        # Fetch vocabulary mastered
        if need_vocab:
            # Count words with status MASTERED
            result = await self.db.execute(
                select(func.count(UserVocabulary.id)).where(
                    and_(
                        UserVocabulary.user_id == user_id,
                        UserVocabulary.status == VocabularyStatus.MASTERED
                    )
                )
            )
            stats["vocab_mastered"] = result.scalar() or 0
            
            # Count total reviewed
            result = await self.db.execute(
                select(func.count(UserVocabulary.id)).where(
                    and_(
                        UserVocabulary.user_id == user_id,
                        UserVocabulary.total_reviews > 0
                    )
                )
            )
            stats["vocab_reviewed"] = result.scalar() or 0
        
        # Fetch XP (sum from all user course progress)
        if need_xp:
            result = await self.db.execute(
                select(func.coalesce(func.sum(UserCourseProgress.total_xp_earned), 0)).where(
                    UserCourseProgress.user_id == user_id
                )
            )
            stats["total_xp"] = result.scalar() or 0
        
        # Fetch perfect scores and quiz completions
        if need_quiz:
            # Count perfect score lessons (best_score == 100)
            result = await self.db.execute(
                select(func.count(LessonCompletion.id)).where(
                    and_(
                        LessonCompletion.user_id == user_id,
                        LessonCompletion.best_score == 100
                    )
                )
            )
            stats["perfect_scores"] = result.scalar() or 0
            
            # Total quiz/lesson completions
            result = await self.db.execute(
                select(func.count(LessonCompletion.id)).where(
                    LessonCompletion.user_id == user_id
                )
            )
            stats["quiz_completed"] = result.scalar() or 0
        
        # Fetch voice practice count 
        # Note: Voice practices not tracked separately yet, return 0 for now
        if need_voice:
            stats["voice_practices"] = 0
        
        # Fetch numeric level from User model
        if need_level:
            result = await self.db.execute(
                select(User.numeric_level).where(User.id == user_id)
            )
            stats["numeric_level"] = result.scalar() or 0
        
        # Fetch time-based study stats from DailyActivity
        if need_time:
            # Count night study sessions (activities with night hours)
            # We approximate by counting daily activities — actual hour tracking
            # would need additional logging. For now count total daily activities.
            result = await self.db.execute(
                select(func.count(DailyActivity.id)).where(
                    DailyActivity.user_id == user_id
                )
            )
            total_activities = result.scalar() or 0
            stats["night_study_sessions"] = 0  # Placeholder: needs hour tracking
            stats["morning_study_sessions"] = 0  # Placeholder: needs hour tracking
            stats["speed_lessons"] = 0  # Placeholder: needs lesson duration tracking
        
        # Fetch skill-based stats (grammar, culture, writing, listening)
        if need_skills:
            # These are placeholders — actual implementation needs
            # tagged lesson categories in the database
            stats["grammar_mastered"] = 0
            stats["culture_lessons"] = 0
            stats["writing_completed"] = 0
            stats["listening_completed"] = 0
        
        # Fetch social stats
        if need_social:
            stats["social_interactions"] = 0  # Placeholder
            stats["chats_completed"] = 0  # Placeholder
            stats["help_others_count"] = 0  # Placeholder
        
        # Fetch daily challenge completions
        if need_challenges:
            result = await self.db.execute(
                select(func.count(ChallengeRewardClaim.id)).where(
                    and_(
                        ChallengeRewardClaim.user_id == user_id,
                        ChallengeRewardClaim.challenge_id != "daily_bonus"
                    )
                )
            )
            stats["daily_challenges_completed"] = result.scalar() or 0
        
        return stats
    
    async def _evaluate_condition(
        self, 
        user_id: UUID, 
        achievement: Achievement,
        user_stats: Dict[str, Any]
    ) -> bool:
        """
        Evaluate if user meets the achievement condition.
        
        Returns True if condition is met, False otherwise.
        """
        condition_type = achievement.condition_type
        condition_value = achievement.condition_value or 0
        condition_data = achievement.condition_data or {}
        
        # Map condition types to stat checks
        condition_evaluators = {
            "lesson_complete": lambda: user_stats.get("lessons_completed", 0) >= condition_value,
            "reach_streak": lambda: max(
                user_stats.get("current_streak", 0),
                user_stats.get("longest_streak", 0)
            ) >= condition_value,
            "vocab_mastered": lambda: user_stats.get("vocab_mastered", 0) >= condition_value,
            "vocab_reviewed": lambda: user_stats.get("vocab_reviewed", 0) >= condition_value,
            "xp_earned": lambda: user_stats.get("total_xp", 0) >= condition_value,
            "perfect_score": lambda: user_stats.get("perfect_scores", 0) >= condition_value,
            "quiz_complete": lambda: user_stats.get("quiz_completed", 0) >= condition_value,
            "voice_practice": lambda: user_stats.get("voice_practices", 0) >= condition_value,
            "course_complete": lambda: user_stats.get("courses_completed", 0) >= condition_value,
            # ---- New condition evaluators ----
            "numeric_level": lambda: user_stats.get("numeric_level", 0) >= condition_value,
            "study_time_night": lambda: user_stats.get("night_study_sessions", 0) >= condition_value,
            "study_time_morning": lambda: user_stats.get("morning_study_sessions", 0) >= condition_value,
            "speed_lesson": lambda: user_stats.get("speed_lessons", 0) >= condition_value,
            "first_perfect": lambda: user_stats.get("perfect_scores", 0) >= 1 and condition_value <= 1,
            "grammar_mastered": lambda: user_stats.get("grammar_mastered", 0) >= condition_value,
            "culture_lesson": lambda: user_stats.get("culture_lessons", 0) >= condition_value,
            "writing_complete": lambda: user_stats.get("writing_completed", 0) >= condition_value,
            "listening_complete": lambda: user_stats.get("listening_completed", 0) >= condition_value,
            "social_interaction": lambda: user_stats.get("social_interactions", 0) >= condition_value,
            "chat_complete": lambda: user_stats.get("chats_completed", 0) >= condition_value,
            "help_others": lambda: user_stats.get("help_others_count", 0) >= condition_value,
            "daily_challenge_complete": lambda: user_stats.get("daily_challenges_completed", 0) >= condition_value,
            "comeback": lambda: False,  # Special: checked contextually at login
        }
        
        evaluator = condition_evaluators.get(condition_type)
        if evaluator:
            return evaluator()
        
        # Unknown condition type - log warning and return False
        print(f"Warning: Unknown achievement condition type: {condition_type}")
        return False
    
    async def _unlock_achievement(
        self, 
        user_id: UUID, 
        achievement: Achievement
    ) -> Optional[UserAchievement]:
        """
        Unlock achievement for user (idempotent).
        Also awards XP and gems if configured.
        
        Returns UserAchievement if newly unlocked, None if already had.
        """
        # Check if already unlocked (double-check for race conditions)
        result = await self.db.execute(
            select(UserAchievement).where(
                and_(
                    UserAchievement.user_id == user_id,
                    UserAchievement.achievement_id == achievement.id
                )
            )
        )
        if result.scalar_one_or_none():
            return None
        
        # Create unlock record
        user_achievement = UserAchievement(
            user_id=user_id,
            achievement_id=achievement.id,
            unlocked_at=datetime.utcnow()
        )
        self.db.add(user_achievement)
        
        # Note: XP reward is tracked via UserCourseProgress.total_xp_earned
        # Achievement XP is already part of the achievement record for display
        
        # Award gems (if WalletCRUD is available)
        if achievement.gems_reward > 0:
            from app.crud.gamification import WalletCRUD
            await WalletCRUD.add_gems(
                self.db,
                user_id,
                achievement.gems_reward,
                source="achievement",
                description=f"Unlocked: {achievement.name}"
            )
        
        await self.db.commit()
        await self.db.refresh(user_achievement)
        
        return user_achievement


# ============================================================================
# Helper function for easy use in routes
# ============================================================================

async def check_achievements_for_user(
    db: AsyncSession,
    user_id: UUID,
    trigger: str
) -> List[Dict[str, Any]]:
    """
    Convenience function to check achievements and return serializable results.
    
    Args:
        db: Database session
        user_id: User UUID
        trigger: Trigger type (lesson_complete, streak_update, etc.)
    
    Returns:
        List of dicts with unlocked achievement info
    """
    checker = AchievementCheckerService(db)
    unlocked = await checker.check_by_trigger(user_id, trigger)
    
    return [
        {
            "id": str(a.id),
            "name": a.name,
            "description": a.description,
            "badge_icon": a.badge_icon,
            "badge_color": a.badge_color,
            "category": a.category,
            "rarity": a.rarity,
            "xp_reward": a.xp_reward,
            "gems_reward": a.gems_reward,
        }
        for a in unlocked
    ]
