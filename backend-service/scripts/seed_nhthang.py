"""
seed_nhthang.py
───────────────
Set up the nhthang312@gmail.com account for local development/testing.

Actions:
  1. Update provider → add 'local' (keeps existing 'google' if already linked)
  2. Keep existing role (admin) and role_id untouched
  3. Seed learning data:
       - Course progress: Beginners (100%), Everyday (65%), Pre-Intermediate (30%)
       - Lesson completions matching each progress level
       - 45 days of daily_activities
       - XP transactions

Note on admin dashboard security:
  - Admin dashboard login uses Google OAuth only (no password form in UI)
  - provider=['local','google'] means both API password login AND Google OAuth work
  - Admin dashboard (http://localhost:5173) still requires Google OAuth (real Google account ownership)

Usage:
    cd backend-service
    venv/bin/python3 scripts/seed_nhthang.py
"""

import asyncio
import uuid
import random
from datetime import datetime, timezone, timedelta, date

import bcrypt
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.config import settings
from app.models.user import User
from app.models.course import Course, Lesson
from app.models.progress import UserCourseProgress, LessonCompletion, DailyActivity
from app.models.games import XPTransaction

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────

TARGET_EMAIL = "nhthang312@gmail.com"
NEW_PASSWORD = "thang123"

# Courses to enroll + target progress %
COURSE_TARGETS = [
    ("English for Beginners",     1.0),   # 100% complete
    ("Everyday English",          0.65),  # 65%
    ("Pre-Intermediate English",  0.30),  # 30%
]

ACTIVITY_DAYS = 45
DAILY_GOAL_XP  = 50
random.seed(hash(TARGET_EMAIL))


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

def days_ago(n: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=n)


def make_daily_activity(user_id: uuid.UUID, act_date: date, streak_active: bool) -> DailyActivity:
    xp         = random.randint(30, 150) if streak_active else random.randint(5, 40)
    lessons    = random.randint(2, 6)   if streak_active else random.randint(0, 2)
    study_time = random.randint(15, 60) if streak_active else random.randint(5, 20)
    vocab      = random.randint(5, 25)  if streak_active else random.randint(0, 8)
    goal_met   = xp >= DAILY_GOAL_XP
    return DailyActivity(
        id=uuid.uuid4(),
        user_id=user_id,
        activity_date=act_date,
        xp_earned=xp,
        lessons_completed=lessons,
        study_time_minutes=study_time,
        vocabulary_reviewed=vocab,
        daily_goal_met=goal_met,
        daily_goal_xp=DAILY_GOAL_XP,
        created_at=datetime.combine(act_date, datetime.min.time()).replace(tzinfo=timezone.utc),
        updated_at=datetime.combine(act_date, datetime.min.time()).replace(tzinfo=timezone.utc),
    )


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

async def run():
    engine = create_async_engine(settings.DATABASE_URL, echo=False)
    Session = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)

    async with Session() as db:
        # 1. Load user ─────────────────────────────
        result = await db.execute(select(User).where(User.email == TARGET_EMAIL))
        user: User | None = result.scalar_one_or_none()

        if not user:
            print(f"[ERROR] User {TARGET_EMAIL} not found. Run seed_data.py + setup_admin_oauth.py first.")
            return

        user_id = user.id
        print(f"[INFO] Found user: {user.username}  id={user_id}  current providers={user.provider}")

        # 2. Link local provider + set password ───
        new_hash = bcrypt.hashpw(NEW_PASSWORD.encode(), bcrypt.gensalt(12)).decode()
        user.add_provider("local")   # keeps "google" if already present
        user.hashed_password = new_hash
        user.is_verified    = True
        user.is_active      = True
        # Update profile fields to be more realistic
        user.total_xp       = max(user.total_xp, 3200)
        user.numeric_level  = max(user.numeric_level, 18)
        user.rank           = "gold"
        await db.flush()
        print(f"[OK]   Providers={user.provider}, password='{NEW_PASSWORD}'")

        # 3. Clean up previous seed data ───────────
        await db.execute(delete(DailyActivity).where(DailyActivity.user_id == user_id))
        await db.execute(delete(XPTransaction).where(XPTransaction.user_id == user_id))
        await db.execute(delete(LessonCompletion).where(LessonCompletion.user_id == user_id))
        await db.execute(delete(UserCourseProgress).where(UserCourseProgress.user_id == user_id))
        print("[OK]   Cleared previous seed data")

        # 4. Course progress + lesson completions ──
        total_xp_from_lessons = 0

        for course_title, pct in COURSE_TARGETS:
            res = await db.execute(select(Course).where(Course.title == course_title))
            course: Course | None = res.scalar_one_or_none()
            if not course:
                print(f"[WARN] Course not found: {course_title}")
                continue

            res2 = await db.execute(select(Lesson).where(Lesson.course_id == course.id))
            lessons = sorted(res2.scalars().all(), key=lambda l: l.order_index)
            total_lessons = len(lessons)
            done_count = round(total_lessons * pct)

            course_xp = 0
            started_at = days_ago(ACTIVITY_DAYS - 2)

            for i, lesson in enumerate(lessons[:done_count]):
                completed_at = days_ago(max(1, ACTIVITY_DAYS - 3 - i * 2))
                score = random.randint(75, 100)
                xp_earned = lesson.xp_reward
                db.add(LessonCompletion(
                    id=uuid.uuid4(),
                    user_id=user_id,
                    lesson_id=lesson.id,
                    is_passed=True,
                    best_score=score,
                    completed_at=completed_at,
                ))
                course_xp += xp_earned

            last_activity = days_ago(max(1, ACTIVITY_DAYS - 3 - (done_count - 1) * 2)) if done_count else started_at

            db.add(UserCourseProgress(
                id=uuid.uuid4(),
                user_id=user_id,
                course_id=course.id,
                progress_percentage=round(pct * 100, 1),
                lessons_completed=done_count,
                total_xp_earned=course_xp,
                started_at=started_at,
                last_activity_at=last_activity,
            ))
            total_xp_from_lessons += course_xp
            print(f"[OK]   {course_title}: {done_count}/{total_lessons} lessons  ({pct*100:.0f}%)  +{course_xp} XP")

        # 5. Daily activities ───────────────────────
        today = date.today()
        # Active streak: last 12 days; sporadic before that
        for i in range(ACTIVITY_DAYS):
            act_date = today - timedelta(days=i)
            streak_active = i < 12 or (i % 3 != 0)   # miss every 3rd day beyond day 12
            da = make_daily_activity(user_id, act_date, streak_active)
            db.add(da)
        print(f"[OK]   Added {ACTIVITY_DAYS} daily activities (12-day active streak)")

        # 6. XP transactions ────────────────────────
        # Lesson XP transactions spread over past weeks
        xp_sources = [
            ("lesson_complete",  60, ACTIVITY_DAYS - 2),
            ("lesson_complete",  45, ACTIVITY_DAYS - 5),
            ("lesson_complete",  80, ACTIVITY_DAYS - 8),
            ("daily_goal",       50, ACTIVITY_DAYS - 1),
            ("daily_goal",       50, ACTIVITY_DAYS - 2),
            ("daily_goal",       50, 10),
            ("streak_bonus",    100, 8),
            ("review_session",   30, 5),
            ("review_session",   30, 3),
            ("game_session",     75, 2),
        ]
        for source, amount, ago in xp_sources:
            db.add(XPTransaction(
                id=uuid.uuid4(),
                user_id=user_id,
                amount=amount,
                base_amount=amount,
                multiplier=1.0,
                source=source,
                source_id=None,
                source_detail=None,
                level_before=15,
                level_after=18,
                leveled_up=False,
                created_at=days_ago(ago),
            ))
        print(f"[OK]   Added {len(xp_sources)} XP transactions")

        # 7. Commit ────────────────────────────────
        await db.commit()
        print(f"\n Done! Login credentials:")
        print(f"  Email    : {TARGET_EMAIL}")
        print(f"  Password : {NEW_PASSWORD}")
        print(f"  Providers: {user.provider}")
        print(f"  Role     : {user.role_slug if hasattr(user, 'role_slug') else 'admin (unchanged)'}")
        print(f"\n  - API login (POST /api/v1/auth/login) works via password")
        print(f"  - Admin dashboard (http://localhost:5173) requires Google OAuth (real Google account)")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(run())
