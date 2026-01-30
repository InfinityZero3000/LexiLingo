"""
Seed Data Script for Development
Creates sample data for testing the LexiLingo backend
"""

import asyncio
import uuid
from datetime import datetime, timedelta
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import engine, AsyncSessionLocal
from app.core.security import get_password_hash
from app.models import *


async def seed_users(db: AsyncSession):
    """Create sample users."""
    print("🔧 Creating users...")
    
    users_data = [
        {
            "email": "admin@lexilingo.com",
            "username": "admin",
            "password": "admin123",
            "display_name": "Admin User",
            "level": "advanced",
            "is_verified": True,
        },
        {
            "email": "john@example.com",
            "username": "john_doe",
            "password": "password123",
            "display_name": "John Doe",
            "level": "beginner",
            "is_verified": True,
        },
        {
            "email": "mary@example.com",
            "username": "mary_smith",
            "password": "password123",
            "display_name": "Mary Smith",
            "level": "intermediate",
            "is_verified": True,
        },
    ]
    
    created_users = []
    for user_data in users_data:
        # Check if user exists
        result = await db.execute(
            select(User).where(User.email == user_data["email"])
        )
        existing_user = result.scalar_one_or_none()
        
        if not existing_user:
            password = user_data.pop("password")
            user = User(
                **user_data,
                hashed_password=get_password_hash(password)
            )
            db.add(user)
            created_users.append(user)
            print(f"  ✅ Created user: {user.username}")
        else:
            created_users.append(existing_user)
            print(f"  ⏭️  User already exists: {existing_user.username}")
    
    await db.commit()
    print(f"✅ Users created: {len(created_users)}\n")
    return created_users


async def seed_courses(db: AsyncSession):
    """Create sample courses with units and lessons."""
    print("🔧 Creating courses...")
    
    # Course 1: Beginner English
    result = await db.execute(
        select(Course).where(Course.title == "English for Beginners")
    )
    course1 = result.scalar_one_or_none()
    
    if not course1:
        course1 = Course(
            title="English for Beginners",
            description="Start your English learning journey with the basics",
            language="en",
            level="A1",
            tags={"categories": ["grammar", "vocabulary", "pronunciation"]},
            total_xp=500,
            estimated_duration=1200,  # 20 hours
            content_version=1,
            is_published=True,
            thumbnail_url="https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=400"
        )
        db.add(course1)
        await db.flush()
        print(f"  ✅ Created course: {course1.title}")
    else:
        print(f"  ⏭️  Course already exists: {course1.title}")
    
    # Create Units for Course 1
    units_data = [
        {
            "title": "Greetings & Introductions",
            "description": "Learn how to introduce yourself and greet people",
            "order_index": 1,
            "background_color": "#4CAF50",
        },
        {
            "title": "Basic Vocabulary",
            "description": "Essential words for daily conversations",
            "order_index": 2,
            "background_color": "#2196F3",
        },
        {
            "title": "Simple Grammar",
            "description": "Understand basic English grammar rules",
            "order_index": 3,
            "background_color": "#FF9800",
        },
    ]
    
    created_units = []
    for unit_data in units_data:
        result = await db.execute(
            select(Unit).where(
                Unit.course_id == course1.id,
                Unit.title == unit_data["title"]
            )
        )
        unit = result.scalar_one_or_none()
        
        if not unit:
            unit = Unit(course_id=course1.id, **unit_data)
            db.add(unit)
            await db.flush()
            created_units.append(unit)
            print(f"    ✅ Created unit: {unit.title}")
        else:
            created_units.append(unit)
            print(f"    ⏭️  Unit already exists: {unit.title}")
    
    # Create Lessons for each Unit
    lessons_data = [
        # Unit 1 Lessons
        {
            "unit_idx": 0,
            "title": "Saying Hello",
            "description": "Learn different ways to greet people",
            "order_index": 1,
            "lesson_type": "vocabulary",
            "pass_threshold": 70,
            "estimated_minutes": 10,
            "xp_reward": 10,
            "content": {
                "questions": [
                    {
                        "type": "multiple_choice",
                        "question": "How do you say 'Good morning' in a formal way?",
                        "options": ["Morning!", "Good morning", "Yo!", "Hey"],
                        "correct_answer": 1
                    }
                ]
            }
        },
        {
            "unit_idx": 0,
            "title": "Introducing Yourself",
            "description": "Practice self-introduction",
            "order_index": 2,
            "lesson_type": "grammar",
            "pass_threshold": 70,
            "estimated_minutes": 15,
            "xp_reward": 15,
            "content": {
                "questions": [
                    {
                        "type": "fill_blank",
                        "question": "My name ___ John.",
                        "correct_answer": "is"
                    }
                ]
            }
        },
        # Unit 2 Lessons
        {
            "unit_idx": 1,
            "title": "Common Nouns",
            "description": "Learn everyday objects",
            "order_index": 1,
            "lesson_type": "vocabulary",
            "pass_threshold": 80,
            "estimated_minutes": 12,
            "xp_reward": 12,
            "content": {
                "words": ["apple", "book", "cat", "dog", "house"]
            }
        },
    ]
    
    for lesson_data in lessons_data:
        unit_idx = lesson_data.pop("unit_idx")
        unit = created_units[unit_idx]
        
        result = await db.execute(
            select(Lesson).where(
                Lesson.unit_id == unit.id,
                Lesson.title == lesson_data["title"]
            )
        )
        lesson = result.scalar_one_or_none()
        
        if not lesson:
            lesson = Lesson(
                course_id=course1.id,
                unit_id=unit.id,
                **lesson_data
            )
            db.add(lesson)
            print(f"      ✅ Created lesson: {lesson.title}")
        else:
            print(f"      ⏭️  Lesson already exists: {lesson.title}")
    
    await db.commit()
    print(f"✅ Courses seeded\n")
    return course1


async def seed_achievements(db: AsyncSession):
    """Create comprehensive achievements/badges."""
    print("🔧 Creating achievements...")
    
    achievements_data = [
        # ========== LESSON ACHIEVEMENTS ==========
        {
            "name": "First Steps",
            "description": "Complete your first lesson",
            "condition_type": "lesson_complete",
            "condition_value": 1,
            "badge_icon": "target",
            "badge_color": "#4CAF50",
            "category": "lessons",
            "xp_reward": 10,
            "gems_reward": 5,
            "rarity": "common",
        },
        {
            "name": "Dedicated Learner",
            "description": "Complete 10 lessons",
            "condition_type": "lesson_complete",
            "condition_value": 10,
            "badge_icon": "📖",
            "badge_color": "#8BC34A",
            "category": "lessons",
            "xp_reward": 30,
            "gems_reward": 15,
            "rarity": "common",
        },
        {
            "name": "Knowledge Seeker",
            "description": "Complete 50 lessons",
            "condition_type": "lesson_complete",
            "condition_value": 50,
            "badge_icon": "🎓",
            "badge_color": "#009688",
            "category": "lessons",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "rare",
        },
        {
            "name": "Scholar",
            "description": "Complete 100 lessons",
            "condition_type": "lesson_complete",
            "condition_value": 100,
            "badge_icon": "trophy",
            "badge_color": "#673AB7",
            "category": "lessons",
            "xp_reward": 200,
            "gems_reward": 100,
            "rarity": "epic",
        },
        {
            "name": "Professor",
            "description": "Complete 500 lessons",
            "condition_type": "lesson_complete",
            "condition_value": 500,
            "badge_icon": "crown",
            "badge_color": "#FFD700",
            "category": "lessons",
            "xp_reward": 500,
            "gems_reward": 250,
            "rarity": "legendary",
        },
        
        # ========== STREAK ACHIEVEMENTS ==========
        {
            "name": "Getting Started",
            "description": "Maintain a 3-day streak",
            "condition_type": "reach_streak",
            "condition_value": 3,
            "badge_icon": "fire",
            "badge_color": "#FF9800",
            "category": "streak",
            "xp_reward": 15,
            "gems_reward": 10,
            "rarity": "common",
        },
        {
            "name": "Week Warrior",
            "description": "Maintain a 7-day streak",
            "condition_type": "reach_streak",
            "condition_value": 7,
            "badge_icon": "fire",
            "badge_color": "#FF5722",
            "category": "streak",
            "xp_reward": 50,
            "gems_reward": 25,
            "rarity": "rare",
        },
        {
            "name": "Two Weeks Strong",
            "description": "Maintain a 14-day streak",
            "condition_type": "reach_streak",
            "condition_value": 14,
            "badge_icon": "bolt",
            "badge_color": "#E91E63",
            "category": "streak",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "rare",
        },
        {
            "name": "Month Master",
            "description": "Maintain a 30-day streak",
            "condition_type": "reach_streak",
            "condition_value": 30,
            "badge_icon": "⚡",
            "badge_color": "#9C27B0",
            "category": "streak",
            "xp_reward": 200,
            "gems_reward": 100,
            "rarity": "epic",
        },
        {
            "name": "Quarterly Champion",
            "description": "Maintain a 90-day streak",
            "condition_type": "reach_streak",
            "condition_value": 90,
            "badge_icon": "🌟",
            "badge_color": "#3F51B5",
            "category": "streak",
            "xp_reward": 500,
            "gems_reward": 250,
            "rarity": "legendary",
        },
        {
            "name": "Year Legend",
            "description": "Maintain a 365-day streak",
            "condition_type": "reach_streak",
            "condition_value": 365,
            "badge_icon": "🏅",
            "badge_color": "#FFD700",
            "category": "streak",
            "xp_reward": 1000,
            "gems_reward": 500,
            "rarity": "legendary",
            "is_hidden": True,
        },
        
        # ========== VOCABULARY ACHIEVEMENTS ==========
        {
            "name": "Word Collector",
            "description": "Master 10 vocabulary words",
            "condition_type": "vocab_mastered",
            "condition_value": 10,
            "badge_icon": "📝",
            "badge_color": "#00BCD4",
            "category": "vocabulary",
            "xp_reward": 20,
            "gems_reward": 10,
            "rarity": "common",
        },
        {
            "name": "Vocab Builder",
            "description": "Master 50 vocabulary words",
            "condition_type": "vocab_mastered",
            "condition_value": 50,
            "badge_icon": "📕",
            "badge_color": "#03A9F4",
            "category": "vocabulary",
            "xp_reward": 75,
            "gems_reward": 35,
            "rarity": "rare",
        },
        {
            "name": "Vocab Master",
            "description": "Master 100 vocabulary words",
            "condition_type": "vocab_mastered",
            "condition_value": 100,
            "badge_icon": "book",
            "badge_color": "#2196F3",
            "category": "vocabulary",
            "xp_reward": 150,
            "gems_reward": 75,
            "rarity": "epic",
        },
        {
            "name": "Walking Dictionary",
            "description": "Master 500 vocabulary words",
            "condition_type": "vocab_mastered",
            "condition_value": 500,
            "badge_icon": "📖",
            "badge_color": "#1976D2",
            "category": "vocabulary",
            "xp_reward": 400,
            "gems_reward": 200,
            "rarity": "legendary",
        },
        
        # ========== XP ACHIEVEMENTS ==========
        {
            "name": "XP Hunter",
            "description": "Earn 100 XP total",
            "condition_type": "xp_earned",
            "condition_value": 100,
            "badge_icon": "star",
            "badge_color": "#FFC107",
            "category": "xp",
            "xp_reward": 10,
            "gems_reward": 5,
            "rarity": "common",
        },
        {
            "name": "XP Warrior",
            "description": "Earn 500 XP total",
            "condition_type": "xp_earned",
            "condition_value": 500,
            "badge_icon": "🌟",
            "badge_color": "#FF9800",
            "category": "xp",
            "xp_reward": 50,
            "gems_reward": 25,
            "rarity": "rare",
        },
        {
            "name": "XP Champion",
            "description": "Earn 1000 XP total",
            "condition_type": "xp_earned",
            "condition_value": 1000,
            "badge_icon": "💫",
            "badge_color": "#FF5722",
            "category": "xp",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "epic",
        },
        {
            "name": "XP Legend",
            "description": "Earn 5000 XP total",
            "condition_type": "xp_earned",
            "condition_value": 5000,
            "badge_icon": "🔮",
            "badge_color": "#9C27B0",
            "category": "xp",
            "xp_reward": 250,
            "gems_reward": 125,
            "rarity": "legendary",
        },
        
        # ========== PERFECT SCORE ACHIEVEMENTS ==========
        {
            "name": "Perfectionist",
            "description": "Get a perfect score on a lesson",
            "condition_type": "perfect_score",
            "condition_value": 1,
            "badge_icon": "💯",
            "badge_color": "#4CAF50",
            "category": "quiz",
            "xp_reward": 25,
            "gems_reward": 15,
            "rarity": "common",
        },
        {
            "name": "Perfect 10",
            "description": "Get 10 perfect scores",
            "condition_type": "perfect_score",
            "condition_value": 10,
            "badge_icon": "target",
            "badge_color": "#8BC34A",
            "category": "quiz",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "rare",
        },
        {
            "name": "Flawless",
            "description": "Get 50 perfect scores",
            "condition_type": "perfect_score",
            "condition_value": 50,
            "badge_icon": "✨",
            "badge_color": "#CDDC39",
            "category": "quiz",
            "xp_reward": 250,
            "gems_reward": 125,
            "rarity": "epic",
        },
        
        # ========== COURSE ACHIEVEMENTS ==========
        {
            "name": "Graduate",
            "description": "Complete your first course",
            "condition_type": "course_complete",
            "condition_value": 1,
            "badge_icon": "🎓",
            "badge_color": "#3F51B5",
            "category": "course",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "rare",
        },
        {
            "name": "Multi-Course Master",
            "description": "Complete 5 courses",
            "condition_type": "course_complete",
            "condition_value": 5,
            "badge_icon": "🎖️",
            "badge_color": "#673AB7",
            "category": "course",
            "xp_reward": 300,
            "gems_reward": 150,
            "rarity": "epic",
        },
        
        # ========== VOICE/PRONUNCIATION ACHIEVEMENTS ==========
        {
            "name": "Voice Starter",
            "description": "Complete 10 pronunciation practices",
            "condition_type": "voice_practice",
            "condition_value": 10,
            "badge_icon": "🎤",
            "badge_color": "#E91E63",
            "category": "voice",
            "xp_reward": 30,
            "gems_reward": 15,
            "rarity": "common",
        },
        {
            "name": "Voice Pro",
            "description": "Complete 100 pronunciation practices",
            "condition_type": "voice_practice",
            "condition_value": 100,
            "badge_icon": "🎙️",
            "badge_color": "#9C27B0",
            "category": "voice",
            "xp_reward": 150,
            "gems_reward": 75,
            "rarity": "epic",
        },
    ]
    
    created_count = 0
    for achievement_data in achievements_data:
        result = await db.execute(
            select(Achievement).where(Achievement.name == achievement_data["name"])
        )
        achievement = result.scalar_one_or_none()
        
        if not achievement:
            achievement = Achievement(**achievement_data)
            db.add(achievement)
            created_count += 1
            print(f"  ✅ Created achievement: {achievement.name}")
        else:
            print(f"  ⏭️  Achievement already exists: {achievement.name}")
    
    await db.commit()
    print(f"✅ Achievements created: {created_count} new, {len(achievements_data)} total\n")


async def seed_shop_items(db: AsyncSession):
    """Create sample shop items."""
    print("🔧 Creating shop items...")
    
    shop_items_data = [
        {
            "name": "Streak Freeze",
            "description": "Protect your streak for 1 day",
            "item_type": "streak_freeze",
            "price_gems": 10,
            "effects": {"duration_hours": 24},
            "icon_url": "❄️",
        },
        {
            "name": "Double XP (1 hour)",
            "description": "Earn 2x XP for 1 hour",
            "item_type": "double_xp",
            "price_gems": 20,
            "effects": {"duration_hours": 1, "multiplier": 2},
            "icon_url": "⚡",
        },
        {
            "name": "Hint Pack (5)",
            "description": "Get 5 extra hints",
            "item_type": "hint_pack",
            "price_gems": 15,
            "effects": {"quantity": 5},
            "icon_url": "💡",
        },
    ]
    
    for item_data in shop_items_data:
        result = await db.execute(
            select(ShopItem).where(ShopItem.name == item_data["name"])
        )
        item = result.scalar_one_or_none()
        
        if not item:
            item = ShopItem(**item_data)
            db.add(item)
            print(f"  ✅ Created shop item: {item.name}")
        else:
            print(f"  ⏭️  Shop item already exists: {item.name}")
    
    await db.commit()
    print(f"✅ Shop items created\n")


async def seed_user_wallets(db: AsyncSession, users):
    """Create wallets for users."""
    print("🔧 Creating user wallets...")
    
    for user in users:
        result = await db.execute(
            select(UserWallet).where(UserWallet.user_id == user.id)
        )
        wallet = result.scalar_one_or_none()
        
        if not wallet:
            wallet = UserWallet(
                user_id=user.id,
                gems=100,  # Starting gems
                total_gems_earned=100
            )
            db.add(wallet)
            print(f"  ✅ Created wallet for: {user.username}")
        else:
            print(f"  ⏭️  Wallet already exists for: {user.username}")
    
    await db.commit()
    print(f"✅ Wallets created\n")


async def seed_streaks(db: AsyncSession, users):
    """Create streak records for users."""
    print("🔧 Creating streaks...")
    
    for user in users:
        result = await db.execute(
            select(Streak).where(Streak.user_id == user.id)
        )
        streak = result.scalar_one_or_none()
        
        if not streak:
            streak = Streak(
                user_id=user.id,
                current_streak=0,
                longest_streak=0,
                total_days_active=0
            )
            db.add(streak)
            print(f"  ✅ Created streak for: {user.username}")
        else:
            print(f"  ⏭️  Streak already exists for: {user.username}")
    
    await db.commit()
    print(f"✅ Streaks created\n")


async def main():
    """Main seeding function."""
    print("\n" + "="*50)
    print("🌱 LexiLingo Database Seeding")
    print("="*50 + "\n")
    
    async with AsyncSessionLocal() as db:
        try:
            # Seed in order due to foreign key dependencies
            users = await seed_users(db)
            await seed_courses(db)
            await seed_achievements(db)
            await seed_shop_items(db)
            await seed_user_wallets(db, users)
            await seed_streaks(db, users)
            
            print("\n" + "="*50)
            print("✅ Seeding completed successfully!")
            print("="*50 + "\n")
            
            print("📊 Summary:")
            print(f"  • Users: {len(users)}")
            print(f"  • Courses: 1 (with units and lessons)")
            print(f"  • Achievements: 3")
            print(f"  • Shop Items: 3")
            print(f"  • Wallets: {len(users)}")
            print(f"  • Streaks: {len(users)}")
            print("\n")
            
        except Exception as e:
            print(f"\n❌ Error during seeding: {e}")
            raise


if __name__ == "__main__":
    asyncio.run(main())
