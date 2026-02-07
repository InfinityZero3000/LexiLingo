"""
Seed Data Script for Development
Creates sample data for testing the LexiLingo backend
"""

import asyncio
import uuid
from datetime import datetime, timedelta
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import engine, AsyncSessionLocal
from app.core.security import get_password_hash
from app.models import *


# ── RBAC Seed ─────────────────────────────────────────────

async def seed_roles(db: AsyncSession):
    """Create system roles: user, admin, super_admin."""
    print("🔧 Creating roles...")

    roles_data = [
        {
            "name": "User",
            "slug": "user",
            "description": "Default role — can learn, complete courses, earn achievements",
            "level": 0,
            "is_system": True,
        },
        {
            "name": "Admin",
            "slug": "admin",
            "description": "Can manage courses, users, achievements, view analytics",
            "level": 1,
            "is_system": True,
        },
        {
            "name": "Super Admin",
            "slug": "super_admin",
            "description": "Full system access — manage admins, system config, delete users",
            "level": 2,
            "is_system": True,
        },
    ]

    created_roles = {}
    for role_data in roles_data:
        result = await db.execute(
            select(Role).where(Role.slug == role_data["slug"])
        )
        existing = result.scalar_one_or_none()
        if not existing:
            role = Role(**role_data)
            db.add(role)
            created_roles[role_data["slug"]] = role
            print(f"  ✅ Created role: {role_data['name']}")
        else:
            created_roles[role_data["slug"]] = existing
            print(f"  ⏭️  Role already exists: {existing.name}")

    await db.commit()
    # Refresh to get IDs
    for slug in created_roles:
        await db.refresh(created_roles[slug])
    print(f"✅ Roles: {len(created_roles)}\n")
    return created_roles


async def seed_permissions(db: AsyncSession, roles: dict):
    """Create permissions and assign to roles."""
    print("🔧 Creating permissions...")

    # Define all permissions
    permissions_data = [
        # Courses
        {"name": "View Courses", "slug": "courses:read", "resource": "courses", "action": "read", "description": "View published courses"},
        {"name": "Create Courses", "slug": "courses:create", "resource": "courses", "action": "create", "description": "Create new courses"},
        {"name": "Update Courses", "slug": "courses:update", "resource": "courses", "action": "update", "description": "Edit existing courses"},
        {"name": "Delete Courses", "slug": "courses:delete", "resource": "courses", "action": "delete", "description": "Delete courses"},
        # Users
        {"name": "View Users", "slug": "users:read", "resource": "users", "action": "read", "description": "View user profiles and list"},
        {"name": "Update Users", "slug": "users:update", "resource": "users", "action": "update", "description": "Edit user profiles"},
        {"name": "Delete Users", "slug": "users:delete", "resource": "users", "action": "delete", "description": "Delete/ban users"},
        {"name": "Manage User Roles", "slug": "users:manage_roles", "resource": "users", "action": "manage_roles", "description": "Assign/revoke roles"},
        # Achievements
        {"name": "View Achievements", "slug": "achievements:read", "resource": "achievements", "action": "read", "description": "View achievements"},
        {"name": "Manage Achievements", "slug": "achievements:manage", "resource": "achievements", "action": "manage", "description": "Create/edit/delete achievements"},
        # Content
        {"name": "Manage Content", "slug": "content:manage", "resource": "content", "action": "manage", "description": "Manage lessons, units, vocabulary"},
        # Analytics
        {"name": "View Analytics", "slug": "analytics:read", "resource": "analytics", "action": "read", "description": "View platform analytics & reports"},
        # System
        {"name": "System Settings", "slug": "system:manage", "resource": "system", "action": "manage", "description": "System configuration and maintenance"},
        # Reports
        {"name": "View Reports", "slug": "reports:read", "resource": "reports", "action": "read", "description": "View user activity and engagement reports"},
        # Shop
        {"name": "Manage Shop", "slug": "shop:manage", "resource": "shop", "action": "manage", "description": "Create/edit/delete shop items"},
        # Audit
        {"name": "View Audit Logs", "slug": "audit:read", "resource": "audit", "action": "read", "description": "View admin audit trail"},
    ]

    perm_map = {}
    for perm_data in permissions_data:
        result = await db.execute(
            select(Permission).where(Permission.slug == perm_data["slug"])
        )
        existing = result.scalar_one_or_none()
        if not existing:
            perm = Permission(**perm_data)
            db.add(perm)
            perm_map[perm_data["slug"]] = perm
            print(f"  ✅ Created permission: {perm_data['slug']}")
        else:
            perm_map[perm_data["slug"]] = existing
            print(f"  ⏭️  Permission exists: {existing.slug}")

    await db.commit()
    for slug in perm_map:
        await db.refresh(perm_map[slug])

    # ── Assign permissions to roles ──
    # Admin gets most permissions
    admin_perms = [
        "courses:read", "courses:create", "courses:update", "courses:delete",
        "users:read", "users:update",
        "achievements:read", "achievements:manage",
        "content:manage",
        "analytics:read",
        "reports:read",
        "shop:manage",
        "audit:read",
    ]

    # Super admin gets everything (also enforced in code via level check)
    super_admin_perms = list(perm_map.keys())  # all permissions

    # User gets basic read
    user_perms = ["courses:read", "achievements:read"]

    role_perm_assignments = {
        "user": user_perms,
        "admin": admin_perms,
        "super_admin": super_admin_perms,
    }

    assigned_count = 0
    for role_slug, perm_slugs in role_perm_assignments.items():
        role = roles.get(role_slug)
        if not role:
            continue
        for perm_slug in perm_slugs:
            perm = perm_map.get(perm_slug)
            if not perm:
                continue
            # Check if already assigned
            result = await db.execute(
                select(RolePermission).where(
                    RolePermission.role_id == role.id,
                    RolePermission.permission_id == perm.id,
                )
            )
            if not result.scalar_one_or_none():
                db.add(RolePermission(role_id=role.id, permission_id=perm.id))
                assigned_count += 1

    await db.commit()
    print(f"✅ Permissions: {len(perm_map)} total, {assigned_count} new assignments\n")
    return perm_map


async def seed_users(db: AsyncSession, roles: dict = None):
    """Create sample users with role assignments."""
    print("🔧 Creating users...")
    
    # Get role IDs
    user_role_id = roles["user"].id if roles and "user" in roles else None
    admin_role_id = roles["admin"].id if roles and "admin" in roles else None
    super_admin_role_id = roles["super_admin"].id if roles and "super_admin" in roles else None
    
    users_data = [
        {
            "email": "admin@lexilingo.com",
            "username": "admin",
            "password": "admin123",
            "display_name": "Admin User",
            "level": "advanced",
            "is_verified": True,
            "_role_id": super_admin_role_id,
        },
        {
            "email": "john@example.com",
            "username": "john_doe",
            "password": "password123",
            "display_name": "John Doe",
            "level": "beginner",
            "is_verified": True,
            "_role_id": user_role_id,
        },
        {
            "email": "mary@example.com",
            "username": "mary_smith",
            "password": "password123",
            "display_name": "Mary Smith",
            "level": "intermediate",
            "is_verified": True,
            "_role_id": admin_role_id,
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
            role_id = user_data.pop("_role_id", None)
            user = User(
                **user_data,
                hashed_password=get_password_hash(password),
                role_id=role_id,
            )
            db.add(user)
            created_users.append(user)
            print(f"  ✅ Created user: {user.username} (role_id={role_id})")
        else:
            # Update role if not set
            role_id = user_data.get("_role_id")
            if role_id and not existing_user.role_id:
                existing_user.role_id = role_id
                print(f"  🔄 Updated role for: {existing_user.username}")
            else:
                print(f"  ⏭️  User already exists: {existing_user.username}")
            created_users.append(existing_user)
    
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
            "slug": "first_steps",
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
            "slug": "dedicated_learner",
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
            "slug": "knowledge_seeker",
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
            "slug": "scholar",
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
            "slug": "professor",
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
            "slug": "getting_started",
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
            "slug": "week_warrior",
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
            "slug": "two_weeks_strong",
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
            "slug": "month_master",
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
            "slug": "quarterly_champion",
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
            "slug": "year_legend",
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
            "slug": "word_collector",
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
            "slug": "vocab_builder",
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
            "slug": "vocab_master",
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
            "slug": "walking_dictionary",
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
            "slug": "xp_hunter",
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
            "slug": "xp_warrior",
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
            "slug": "xp_champion",
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
            "slug": "xp_legend",
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
            "slug": "perfectionist",
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
            "slug": "accuracy_master",
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
            "slug": "flawless",
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
            "slug": "course_explorer",
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
            "slug": "course_champion",
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
            "slug": "voice_beginner",
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
            "slug": "voice_talent",
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

        # ========== LEVEL MILESTONE ACHIEVEMENTS ==========
        {
            "name": "Rising Star",
            "slug": "level_25",
            "description": "Reach Level 25",
            "condition_type": "numeric_level",
            "condition_value": 25,
            "badge_icon": "trending",
            "badge_color": "#4CAF50",
            "category": "level",
            "xp_reward": 50,
            "gems_reward": 30,
            "rarity": "common",
        },
        {
            "name": "Half Century",
            "slug": "level_50",
            "description": "Reach Level 50",
            "condition_type": "numeric_level",
            "condition_value": 50,
            "badge_icon": "star",
            "badge_color": "#2196F3",
            "category": "level",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "rare",
        },
        {
            "name": "Centurion",
            "slug": "level_100",
            "description": "Reach Level 100",
            "condition_type": "numeric_level",
            "condition_value": 100,
            "badge_icon": "star_gold",
            "badge_color": "#9C27B0",
            "category": "level",
            "xp_reward": 200,
            "gems_reward": 100,
            "rarity": "epic",
        },
        {
            "name": "Veteran",
            "slug": "level_150",
            "description": "Reach Level 150",
            "condition_type": "numeric_level",
            "condition_value": 150,
            "badge_icon": "trophy",
            "badge_color": "#673AB7",
            "category": "level",
            "xp_reward": 300,
            "gems_reward": 150,
            "rarity": "epic",
        },
        {
            "name": "Legend",
            "slug": "level_200",
            "description": "Reach Level 200",
            "condition_type": "numeric_level",
            "condition_value": 200,
            "badge_icon": "crown",
            "badge_color": "#FF9800",
            "category": "level",
            "xp_reward": 400,
            "gems_reward": 200,
            "rarity": "legendary",
        },
        {
            "name": "Mythic",
            "slug": "level_300",
            "description": "Reach Level 300",
            "condition_type": "numeric_level",
            "condition_value": 300,
            "badge_icon": "💎",
            "badge_color": "#E91E63",
            "category": "level",
            "xp_reward": 600,
            "gems_reward": 300,
            "rarity": "legendary",
        },
        {
            "name": "Immortal",
            "slug": "level_500",
            "description": "Reach Level 500",
            "condition_type": "numeric_level",
            "condition_value": 500,
            "badge_icon": "💎",
            "badge_color": "#FFD700",
            "category": "level",
            "xp_reward": 1000,
            "gems_reward": 500,
            "rarity": "legendary",
            "is_hidden": True,
        },

        # ========== SPECIAL — TIME-BASED ==========
        {
            "name": "Night Owl",
            "slug": "night_owl",
            "description": "Study after 10 PM, 7 times",
            "condition_type": "study_time_night",
            "condition_value": 7,
            "badge_icon": "🌙",
            "badge_color": "#303F9F",
            "category": "special",
            "xp_reward": 30,
            "gems_reward": 15,
            "rarity": "common",
        },
        {
            "name": "Early Bird",
            "slug": "early_bird",
            "description": "Study before 7 AM, 7 times",
            "condition_type": "study_time_morning",
            "condition_value": 7,
            "badge_icon": "🌅",
            "badge_color": "#FF9800",
            "category": "special",
            "xp_reward": 30,
            "gems_reward": 15,
            "rarity": "common",
        },
        {
            "name": "Speed Demon",
            "slug": "speed_demon",
            "description": "Complete 5 lessons in under 3 minutes each",
            "condition_type": "speed_lesson",
            "condition_value": 5,
            "badge_icon": "⚡",
            "badge_color": "#00BCD4",
            "category": "special",
            "xp_reward": 75,
            "gems_reward": 40,
            "rarity": "rare",
        },
        {
            "name": "First Perfect",
            "slug": "first_perfect_score",
            "description": "Get 100% on your very first quiz attempt",
            "condition_type": "first_perfect",
            "condition_value": 1,
            "badge_icon": "✨",
            "badge_color": "#8BC34A",
            "category": "quiz",
            "xp_reward": 30,
            "gems_reward": 20,
            "rarity": "common",
        },
        {
            "name": "Quiz Champion",
            "slug": "quiz_champion",
            "description": "Score 100% on 10 different quizzes",
            "condition_type": "perfect_score",
            "condition_value": 10,
            "badge_icon": "🏆",
            "badge_color": "#FFD700",
            "category": "quiz",
            "xp_reward": 150,
            "gems_reward": 75,
            "rarity": "rare",
        },

        # ========== SPECIAL — SKILL MASTERY ==========
        {
            "name": "Grammar Guardian",
            "slug": "grammar_guardian",
            "description": "Master 50 grammar rules",
            "condition_type": "grammar_mastered",
            "condition_value": 50,
            "badge_icon": "📚",
            "badge_color": "#1A237E",
            "category": "skill",
            "xp_reward": 150,
            "gems_reward": 75,
            "rarity": "rare",
        },
        {
            "name": "Culture Explorer",
            "slug": "culture_explorer",
            "description": "Complete 10 cultural lessons",
            "condition_type": "culture_lesson",
            "condition_value": 10,
            "badge_icon": "🌍",
            "badge_color": "#00897B",
            "category": "skill",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "epic",
        },
        {
            "name": "Writing Wizard",
            "slug": "writing_wizard",
            "description": "Write 30 essays or responses",
            "condition_type": "writing_complete",
            "condition_value": 30,
            "badge_icon": "✍️",
            "badge_color": "#6A1B9A",
            "category": "skill",
            "xp_reward": 150,
            "gems_reward": 75,
            "rarity": "epic",
        },
        {
            "name": "Listening Legend",
            "slug": "listening_legend",
            "description": "Complete 30 listening exercises",
            "condition_type": "listening_complete",
            "condition_value": 30,
            "badge_icon": "🎧",
            "badge_color": "#283593",
            "category": "skill",
            "xp_reward": 150,
            "gems_reward": 75,
            "rarity": "epic",
        },

        # ========== SPECIAL — SOCIAL ==========
        {
            "name": "Social Butterfly",
            "slug": "social_butterfly",
            "description": "Interact with 20 community posts",
            "condition_type": "social_interaction",
            "condition_value": 20,
            "badge_icon": "🦋",
            "badge_color": "#E91E63",
            "category": "social",
            "xp_reward": 50,
            "gems_reward": 25,
            "rarity": "common",
        },
        {
            "name": "Conversation Champion",
            "slug": "conversation_champion",
            "description": "Complete 50 chat conversations",
            "condition_type": "chat_complete",
            "condition_value": 50,
            "badge_icon": "💬",
            "badge_color": "#1565C0",
            "category": "social",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "rare",
        },
        {
            "name": "Feedback Friend",
            "slug": "feedback_friend",
            "description": "Help 10 other learners",
            "condition_type": "help_others",
            "condition_value": 10,
            "badge_icon": "🤝",
            "badge_color": "#FF6F00",
            "category": "social",
            "xp_reward": 75,
            "gems_reward": 40,
            "rarity": "epic",
        },

        # ========== SPECIAL — MILESTONES ==========
        {
            "name": "Challenge Crusher",
            "slug": "challenge_crusher",
            "description": "Complete 30 daily challenges",
            "condition_type": "daily_challenge_complete",
            "condition_value": 30,
            "badge_icon": "🔨",
            "badge_color": "#D32F2F",
            "category": "milestone",
            "xp_reward": 150,
            "gems_reward": 75,
            "rarity": "epic",
        },
        {
            "name": "Milestone Maker",
            "slug": "milestone_maker",
            "description": "Reach Level 10",
            "condition_type": "numeric_level",
            "condition_value": 10,
            "badge_icon": "🚩",
            "badge_color": "#1976D2",
            "category": "milestone",
            "xp_reward": 50,
            "gems_reward": 25,
            "rarity": "common",
        },
        {
            "name": "Comeback King",
            "slug": "comeback_king",
            "description": "Return after 7+ days away and complete 3 lessons",
            "condition_type": "comeback",
            "condition_value": 1,
            "badge_icon": "🔥",
            "badge_color": "#FF5722",
            "category": "milestone",
            "xp_reward": 100,
            "gems_reward": 50,
            "rarity": "legendary",
        },
    ]
    
    created_count = 0
    updated_count = 0
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
            # Update slug if missing
            if not achievement.slug and "slug" in achievement_data:
                achievement.slug = achievement_data["slug"]
                updated_count += 1
            print(f"  ⏭️  Achievement already exists: {achievement.name}")
    
    await db.commit()
    print(f"✅ Achievements: {created_count} new, {updated_count} updated slugs, {len(achievements_data)} total\n")


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
            # Seed RBAC first (no dependencies)
            roles = await seed_roles(db)
            await seed_permissions(db, roles)
            
            # Seed in order due to foreign key dependencies
            users = await seed_users(db, roles)
            await seed_courses(db)
            await seed_achievements(db)
            await seed_shop_items(db)
            await seed_user_wallets(db, users)
            await seed_streaks(db, users)
            
            print("\n" + "="*50)
            print("✅ Seeding completed successfully!")
            print("="*50 + "\n")
            
            print("📊 Summary:")
            print(f"  • Roles: {len(roles)} (user, admin, super_admin)")
            print(f"  • Permissions: 16 (with role assignments)")
            print(f"  • Users: {len(users)}")
            print(f"  • Courses: 1 (with units and lessons)")
            print(f"  • Achievements: 48 (with slugs)")
            print(f"  • Shop Items: 3")
            print(f"  • Wallets: {len(users)}")
            print(f"  • Streaks: {len(users)}")
            print("\n")
            
        except Exception as e:
            print(f"\n❌ Error during seeding: {e}")
            import traceback
            traceback.print_exc()
            raise


if __name__ == "__main__":
    asyncio.run(main())
