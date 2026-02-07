"""
Seed Achievements from Flutter sample_achievements.dart + badge_asset_mapper.dart
Imports 46 achievements with their badge image URLs into the database.
"""

import asyncio
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import select
from app.core.database import AsyncSessionLocal
from app.models.gamification import Achievement


# Badge asset mapping (from badge_asset_mapper.dart)
BADGE_ASSETS = {
    "first_steps": "common-lesson.png",
    "dedicated_learner": "common-lesson.png",
    "knowledge_seeker": "rare-lesson.png",
    "scholar": "epic-lesson.png",
    "professor": "legendary-lesson.png",
    "getting_started": "streak3.png",
    "week_warrior": "streak7.png",
    "two_weeks_strong": "streak30.png",
    "month_master": "streak30.png",
    "quarterly_champion": "streak90.png",
    "year_legend": "streak365.png",
    "word_collector": "common-vocabulary.png",
    "vocab_builder": "rare-vocabulary.png",
    "vocab_master": "epic-vocabulary.png",
    "walking_dictionary": "legendary-vocabulary.png",
    "xp_hunter": "xp-hunter.png",  # XP Hunter - Common (grey)
    "xp_warrior": "xp-warrior.png",  # XP Warrior - Rare (blue)
    "xp_champion": "xp-champion.png",  # XP Champion - Epic (purple)
    "xp_legend": "xp-legend.png",  # XP Legend - Legendary (gold)
    "perfectionist": "100%.png",
    "first_perfect_score": "first-perfect.png",
    "accuracy_master": "perfect-10.png",
    "flawless": "perfect-50.png",
    "quiz_champion": "quiz-champion.png",
    "course_explorer": "course-graduate.png",
    "course_champion": "course-master.png",
    "voice_beginner": "voice-starter.png",
    "voice_talent": "voice-pro.png",
    "pronunciation_master": "pronunciation-pro.png",
    "level_25": "lv25.png",
    "level_50": "lv50.png",
    "level_100": "lv100.png",
    "level_150": "lv150.png",
    "level_200": "lv200.png",
    "level_300": "lv300.png",
    "level_500": "lv500.png",
    "night_owl": "moon.png",
    "early_bird": "early-bird.png",
    "speed_demon": "speed-demon.png",
    "grammar_guardian": "grammar-guardian.png",
    "culture_explorer": "culture-explorer.png",
    "writing_wizard": "writing-wizard.png",
    "listening_legend": "listening-legend.png",
    "social_butterfly": "social-butterfly.png",
    "conversation_champion": "conversation-champion.png",
    "feedback_friend": "feedback-friend.png",
    "challenge_crusher": "challenge-crusher.png",
    "milestone_maker": "milestone-maker.png",
    "comeback_king": "comeback-king.png",
}

# All 46 achievements from sample_achievements.dart
ACHIEVEMENTS = [
    # ========== LESSON ACHIEVEMENTS (5) ==========
    {"slug": "first_steps", "name": "First Steps", "description": "Complete your first lesson", "condition_type": "lesson_complete", "condition_value": 1, "badge_color": "#4CAF50", "category": "lessons", "xp_reward": 10, "gems_reward": 5, "rarity": "common"},
    {"slug": "dedicated_learner", "name": "Dedicated Learner", "description": "Complete 10 lessons", "condition_type": "lesson_complete", "condition_value": 10, "badge_color": "#8BC34A", "category": "lessons", "xp_reward": 30, "gems_reward": 15, "rarity": "common"},
    {"slug": "knowledge_seeker", "name": "Knowledge Seeker", "description": "Complete 50 lessons", "condition_type": "lesson_complete", "condition_value": 50, "badge_color": "#009688", "category": "lessons", "xp_reward": 100, "gems_reward": 50, "rarity": "rare"},
    {"slug": "scholar", "name": "Scholar", "description": "Complete 100 lessons", "condition_type": "lesson_complete", "condition_value": 100, "badge_color": "#673AB7", "category": "lessons", "xp_reward": 200, "gems_reward": 100, "rarity": "epic"},
    {"slug": "professor", "name": "Professor", "description": "Complete 500 lessons", "condition_type": "lesson_complete", "condition_value": 500, "badge_color": "#FFD700", "category": "lessons", "xp_reward": 500, "gems_reward": 250, "rarity": "legendary"},

    # ========== STREAK ACHIEVEMENTS (6) ==========
    {"slug": "getting_started", "name": "Getting Started", "description": "Maintain a 3-day streak", "condition_type": "reach_streak", "condition_value": 3, "badge_color": "#FF9800", "category": "streak", "xp_reward": 15, "gems_reward": 10, "rarity": "common"},
    {"slug": "week_warrior", "name": "Week Warrior", "description": "Maintain a 7-day streak", "condition_type": "reach_streak", "condition_value": 7, "badge_color": "#FF5722", "category": "streak", "xp_reward": 50, "gems_reward": 25, "rarity": "rare"},
    {"slug": "two_weeks_strong", "name": "Two Weeks Strong", "description": "Maintain a 14-day streak", "condition_type": "reach_streak", "condition_value": 14, "badge_color": "#E91E63", "category": "streak", "xp_reward": 100, "gems_reward": 50, "rarity": "rare"},
    {"slug": "month_master", "name": "Month Master", "description": "Maintain a 30-day streak", "condition_type": "reach_streak", "condition_value": 30, "badge_color": "#9C27B0", "category": "streak", "xp_reward": 200, "gems_reward": 100, "rarity": "epic"},
    {"slug": "quarterly_champion", "name": "Quarterly Champion", "description": "Maintain a 90-day streak", "condition_type": "reach_streak", "condition_value": 90, "badge_color": "#3F51B5", "category": "streak", "xp_reward": 500, "gems_reward": 250, "rarity": "legendary"},
    {"slug": "year_legend", "name": "Year Legend", "description": "Maintain a 365-day streak", "condition_type": "reach_streak", "condition_value": 365, "badge_color": "#FFD700", "category": "streak", "xp_reward": 1000, "gems_reward": 500, "rarity": "legendary", "is_hidden": True},

    # ========== VOCABULARY ACHIEVEMENTS (4) ==========
    {"slug": "word_collector", "name": "Word Collector", "description": "Master 10 vocabulary words", "condition_type": "vocab_mastered", "condition_value": 10, "badge_color": "#00BCD4", "category": "vocabulary", "xp_reward": 20, "gems_reward": 10, "rarity": "common"},
    {"slug": "vocab_builder", "name": "Vocab Builder", "description": "Master 50 vocabulary words", "condition_type": "vocab_mastered", "condition_value": 50, "badge_color": "#03A9F4", "category": "vocabulary", "xp_reward": 75, "gems_reward": 35, "rarity": "rare"},
    {"slug": "vocab_master", "name": "Vocab Master", "description": "Master 100 vocabulary words", "condition_type": "vocab_mastered", "condition_value": 100, "badge_color": "#2196F3", "category": "vocabulary", "xp_reward": 150, "gems_reward": 75, "rarity": "epic"},
    {"slug": "walking_dictionary", "name": "Walking Dictionary", "description": "Master 500 vocabulary words", "condition_type": "vocab_mastered", "condition_value": 500, "badge_color": "#1976D2", "category": "vocabulary", "xp_reward": 400, "gems_reward": 200, "rarity": "legendary"},

    # ========== XP ACHIEVEMENTS (4) ==========
    {"slug": "xp_hunter", "name": "XP Hunter", "description": "Earn 100 XP total", "condition_type": "xp_earned", "condition_value": 100, "badge_color": "#9E9E9E", "category": "xp", "xp_reward": 10, "gems_reward": 5, "rarity": "common"},
    {"slug": "xp_warrior", "name": "XP Warrior", "description": "Earn 500 XP total", "condition_type": "xp_earned", "condition_value": 500, "badge_color": "#2196F3", "category": "xp", "xp_reward": 50, "gems_reward": 25, "rarity": "rare"},
    {"slug": "xp_champion", "name": "XP Champion", "description": "Earn 1,000 XP total", "condition_type": "xp_earned", "condition_value": 1000, "badge_color": "#9C27B0", "category": "xp", "xp_reward": 100, "gems_reward": 50, "rarity": "epic"},
    {"slug": "xp_legend", "name": "XP Legend", "description": "Earn 5,000 XP total", "condition_type": "xp_earned", "condition_value": 5000, "badge_color": "#FFD700", "category": "xp", "xp_reward": 250, "gems_reward": 125, "rarity": "legendary"},

    # ========== QUIZ / PERFECT SCORE (5) ==========
    {"slug": "perfectionist", "name": "Perfectionist", "description": "Get a perfect score on any quiz", "condition_type": "perfect_score", "condition_value": 1, "badge_color": "#4CAF50", "category": "quiz", "xp_reward": 25, "gems_reward": 15, "rarity": "common"},
    {"slug": "first_perfect_score", "name": "First Perfect", "description": "Get 100% on your very first quiz attempt", "condition_type": "first_perfect", "condition_value": 1, "badge_color": "#8BC34A", "category": "quiz", "xp_reward": 30, "gems_reward": 20, "rarity": "common"},
    {"slug": "accuracy_master", "name": "Accuracy Master", "description": "Get 10 perfect scores", "condition_type": "perfect_score", "condition_value": 10, "badge_color": "#8BC34A", "category": "quiz", "xp_reward": 100, "gems_reward": 50, "rarity": "rare"},
    {"slug": "flawless", "name": "Flawless", "description": "Get 50 perfect scores", "condition_type": "perfect_score", "condition_value": 50, "badge_color": "#00BCD4", "category": "quiz", "xp_reward": 300, "gems_reward": 150, "rarity": "epic"},
    {"slug": "quiz_champion", "name": "Quiz Champion", "description": "Score 100% on 10 different quizzes", "condition_type": "perfect_score", "condition_value": 10, "badge_color": "#FFD700", "category": "quiz", "xp_reward": 150, "gems_reward": 75, "rarity": "rare"},

    # ========== COURSE ACHIEVEMENTS (3) ==========
    {"slug": "course_explorer", "name": "Graduate", "description": "Complete your first course", "condition_type": "course_complete", "condition_value": 1, "badge_color": "#3F51B5", "category": "course", "xp_reward": 100, "gems_reward": 50, "rarity": "rare"},
    {"slug": "course_champion", "name": "Multi-Course Master", "description": "Complete 5 courses", "condition_type": "course_complete", "condition_value": 5, "badge_color": "#673AB7", "category": "course", "xp_reward": 500, "gems_reward": 250, "rarity": "epic"},
    {"slug": "polyglot", "name": "Polyglot", "description": "Complete 10 courses", "condition_type": "course_complete", "condition_value": 10, "badge_color": "#FFD700", "category": "course", "xp_reward": 1000, "gems_reward": 500, "rarity": "legendary"},

    # ========== VOICE ACHIEVEMENTS (3) ==========
    {"slug": "voice_beginner", "name": "Voice Starter", "description": "Complete 5 voice exercises", "condition_type": "voice_practice", "condition_value": 5, "badge_color": "#FF5722", "category": "voice", "xp_reward": 20, "gems_reward": 10, "rarity": "common"},
    {"slug": "voice_talent", "name": "Voice Talent", "description": "Complete 25 voice exercises", "condition_type": "voice_practice", "condition_value": 25, "badge_color": "#E91E63", "category": "voice", "xp_reward": 75, "gems_reward": 35, "rarity": "rare"},
    {"slug": "pronunciation_master", "name": "Pronunciation Pro", "description": "Complete 100 voice exercises", "condition_type": "voice_practice", "condition_value": 100, "badge_color": "#9C27B0", "category": "voice", "xp_reward": 200, "gems_reward": 100, "rarity": "epic"},

    # ========== LEVEL MILESTONES (7) ==========
    {"slug": "level_25", "name": "Rising Star", "description": "Reach Level 25", "condition_type": "numeric_level", "condition_value": 25, "badge_color": "#4CAF50", "category": "level", "xp_reward": 50, "gems_reward": 30, "rarity": "common"},
    {"slug": "level_50", "name": "Half Century", "description": "Reach Level 50", "condition_type": "numeric_level", "condition_value": 50, "badge_color": "#2196F3", "category": "level", "xp_reward": 100, "gems_reward": 50, "rarity": "rare"},
    {"slug": "level_100", "name": "Centurion", "description": "Reach Level 100", "condition_type": "numeric_level", "condition_value": 100, "badge_color": "#9C27B0", "category": "level", "xp_reward": 200, "gems_reward": 100, "rarity": "epic"},
    {"slug": "level_150", "name": "Veteran", "description": "Reach Level 150", "condition_type": "numeric_level", "condition_value": 150, "badge_color": "#673AB7", "category": "level", "xp_reward": 300, "gems_reward": 150, "rarity": "epic"},
    {"slug": "level_200", "name": "Legend", "description": "Reach Level 200", "condition_type": "numeric_level", "condition_value": 200, "badge_color": "#FF9800", "category": "level", "xp_reward": 400, "gems_reward": 200, "rarity": "legendary"},
    {"slug": "level_300", "name": "Mythic", "description": "Reach Level 300", "condition_type": "numeric_level", "condition_value": 300, "badge_color": "#E91E63", "category": "level", "xp_reward": 600, "gems_reward": 300, "rarity": "legendary"},
    {"slug": "level_500", "name": "Immortal", "description": "Reach Level 500", "condition_type": "numeric_level", "condition_value": 500, "badge_color": "#FFD700", "category": "level", "xp_reward": 1000, "gems_reward": 500, "rarity": "legendary", "is_hidden": True},

    # ========== SPECIAL — TIME-BASED (3) ==========
    {"slug": "night_owl", "name": "Night Owl", "description": "Study after 10 PM, 7 times", "condition_type": "study_time_night", "condition_value": 7, "badge_color": "#303F9F", "category": "special", "xp_reward": 30, "gems_reward": 15, "rarity": "common"},
    {"slug": "early_bird", "name": "Early Bird", "description": "Study before 7 AM, 7 times", "condition_type": "study_time_morning", "condition_value": 7, "badge_color": "#FF9800", "category": "special", "xp_reward": 30, "gems_reward": 15, "rarity": "common"},
    {"slug": "speed_demon", "name": "Speed Demon", "description": "Complete 5 lessons in under 3 minutes each", "condition_type": "speed_lesson", "condition_value": 5, "badge_color": "#00BCD4", "category": "special", "xp_reward": 75, "gems_reward": 40, "rarity": "rare"},

    # ========== SKILL MASTERY (4) ==========
    {"slug": "grammar_guardian", "name": "Grammar Guardian", "description": "Master 50 grammar rules", "condition_type": "grammar_mastered", "condition_value": 50, "badge_color": "#1A237E", "category": "skill", "xp_reward": 150, "gems_reward": 75, "rarity": "rare"},
    {"slug": "culture_explorer", "name": "Culture Explorer", "description": "Complete 10 cultural lessons", "condition_type": "culture_lesson", "condition_value": 10, "badge_color": "#00897B", "category": "skill", "xp_reward": 100, "gems_reward": 50, "rarity": "epic"},
    {"slug": "writing_wizard", "name": "Writing Wizard", "description": "Write 30 essays or responses", "condition_type": "writing_complete", "condition_value": 30, "badge_color": "#6A1B9A", "category": "skill", "xp_reward": 150, "gems_reward": 75, "rarity": "epic"},
    {"slug": "listening_legend", "name": "Listening Legend", "description": "Complete 30 listening exercises", "condition_type": "listening_complete", "condition_value": 30, "badge_color": "#283593", "category": "skill", "xp_reward": 150, "gems_reward": 75, "rarity": "epic"},

    # ========== SOCIAL (3) ==========
    {"slug": "social_butterfly", "name": "Social Butterfly", "description": "Interact with 20 community posts", "condition_type": "social_interaction", "condition_value": 20, "badge_color": "#E91E63", "category": "social", "xp_reward": 50, "gems_reward": 25, "rarity": "common"},
    {"slug": "conversation_champion", "name": "Conversation Champion", "description": "Complete 50 chat conversations", "condition_type": "chat_complete", "condition_value": 50, "badge_color": "#1565C0", "category": "social", "xp_reward": 100, "gems_reward": 50, "rarity": "rare"},
    {"slug": "feedback_friend", "name": "Feedback Friend", "description": "Help 10 other learners", "condition_type": "help_others", "condition_value": 10, "badge_color": "#FF6F00", "category": "social", "xp_reward": 75, "gems_reward": 40, "rarity": "epic"},

    # ========== MILESTONES (3) ==========
    {"slug": "challenge_crusher", "name": "Challenge Crusher", "description": "Complete 30 daily challenges", "condition_type": "daily_challenge_complete", "condition_value": 30, "badge_color": "#D32F2F", "category": "milestone", "xp_reward": 150, "gems_reward": 75, "rarity": "epic"},
    {"slug": "milestone_maker", "name": "Milestone Maker", "description": "Reach Level 10", "condition_type": "numeric_level", "condition_value": 10, "badge_color": "#1976D2", "category": "milestone", "xp_reward": 50, "gems_reward": 25, "rarity": "common"},
    {"slug": "comeback_king", "name": "Comeback King", "description": "Return after 7+ days away and complete 3 lessons", "condition_type": "comeback", "condition_value": 1, "badge_color": "#FF5722", "category": "milestone", "xp_reward": 100, "gems_reward": 50, "rarity": "legendary"},
]


async def seed_achievements():
    """Seed all 46 achievements into database with badge image URLs."""
    async with AsyncSessionLocal() as session:
        created = 0
        skipped = 0
        updated = 0

        for ach_data in ACHIEVEMENTS:
            slug = ach_data["slug"]

            # Check if achievement already exists by slug or name
            result = await session.execute(
                select(Achievement).where(
                    (Achievement.slug == slug) | (Achievement.name == ach_data["name"])
                )
            )
            existing = result.scalar_one_or_none()

            # Map badge_icon to CDN image URL
            badge_filename = BADGE_ASSETS.get(slug)
            cdn_base = "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@feature/flutter-app/assets/badges"
            badge_icon = f"{cdn_base}/{badge_filename}" if badge_filename else None

            if existing:
                # Update badge_icon and slug if not set
                changed = False
                if not existing.badge_icon or existing.badge_icon != badge_icon:
                    existing.badge_icon = badge_icon
                    changed = True
                if not existing.slug:
                    existing.slug = slug
                    changed = True
                if not existing.badge_color and ach_data.get("badge_color"):
                    existing.badge_color = ach_data["badge_color"]
                    changed = True
                if changed:
                    updated += 1
                else:
                    skipped += 1
                continue

            achievement = Achievement(
                name=ach_data["name"],
                slug=slug,
                description=ach_data["description"],
                condition_type=ach_data["condition_type"],
                condition_value=ach_data.get("condition_value"),
                badge_icon=badge_icon,
                badge_color=ach_data.get("badge_color"),
                category=ach_data.get("category", "special"),
                xp_reward=ach_data.get("xp_reward", 0),
                gems_reward=ach_data.get("gems_reward", 0),
                rarity=ach_data.get("rarity", "common"),
                is_hidden=ach_data.get("is_hidden", False),
            )
            session.add(achievement)
            created += 1

        await session.commit()

        # Count total
        result = await session.execute(select(Achievement))
        total = len(result.scalars().all())

        print(f"\n{'='*50}")
        print(f"Achievements Seed Complete!")
        print(f"{'='*50}")
        print(f"  Created: {created}")
        print(f"  Updated: {updated}")
        print(f"  Skipped: {skipped}")
        print(f"  Total in DB: {total}")
        print(f"{'='*50}\n")


if __name__ == "__main__":
    asyncio.run(seed_achievements())
