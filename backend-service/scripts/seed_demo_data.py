"""
Demo Data Seed Script — Admin Dashboard Charts
================================================
Seeds realistic user activity data so admin can see meaningful charts:
  • User growth chart (90 days)
  • DAU / WAU / MAU engagement
  • Course popularity & enrollment
  • Completion funnel
  • Vocabulary effectiveness

Dedup strategy (safe to re-run):
  • At startup, deletes ALL demo users (email LIKE 'demo_%@lexilingo.dev')
    and their cascade-linked data (daily_activities, course_progress, etc.)
  • Real users (OAuth / '@lexilingo.test') are NEVER touched.
  • Static reference data (courses, vocab, achievements) is NEVER deleted.
  • Then recreates fresh demo users with new random activity data.

Run:
    cd backend-service
    venv/bin/python3 -m scripts.seed_demo_data
"""

import sys
import os
from pathlib import Path

backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

import asyncio
import random
from datetime import datetime, timedelta, date, timezone

from sqlalchemy import select, func, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.models.user import User
from app.models.rbac import Role
from app.models.course import Course, Lesson
from app.models.progress import (
    UserCourseProgress,
    LessonCompletion,
    DailyActivity,
    Streak,
)
from app.models.vocabulary import VocabularyItem, UserVocabulary, VocabularyStatus
from app.models.gamification import (
    Achievement,
    UserAchievement,
    UserWallet,
    LeaderboardEntry,
)


# ─── Seed config ──────────────────────────────────────────────────────────────

TODAY = date.today()
NOW = datetime.now(timezone.utc)
SEED_DAYS = 90          # How many past days to distribute registrations / activity
TOTAL_USERS = 45        # Number of demo learner accounts to create
DAILY_ACTIVE_RATIO = 0.45   # ~45% of users active on any given day

# Seeded password hash for all demo accounts  ("LexiDemo2025!")
DEMO_PASSWORD_HASH = "$2b$12$demohashedpassword.for.seed.data.only.not.real"


# ─── Helpers ──────────────────────────────────────────────────────────────────

def days_ago(n: int) -> datetime:
    return NOW - timedelta(days=n)


def date_ago(n: int) -> date:
    return TODAY - timedelta(days=n)


def rand_between(lo: int, hi: int) -> int:
    return random.randint(lo, hi)


def w_choice(items, weights):
    """Weighted random choice."""
    return random.choices(items, weights=weights, k=1)[0]


# ─── 0. Cleanup — remove stale demo users (CASCADE removes all linked rows) ──

async def cleanup_demo_users(db: AsyncSession):
    """
    Delete all @lexilingo.dev demo users and their cascade-linked data.
    Leaves real users (@lexilingo.test, OAuth users) untouched.
    """
    result = await db.execute(
        select(User).where(User.email.like("demo_%@lexilingo.dev"))
    )
    demo_users = result.scalars().all()
    if not demo_users:
        print("  No existing demo users to clean up.")
        return

    ids = [u.id for u in demo_users]
    await db.execute(delete(User).where(User.id.in_(ids)))
    await db.commit()
    print(f"  ️  Removed {len(ids)} old demo users (and all cascade-linked data)")


# ─── 1. Users ─────────────────────────────────────────────────────────────────

DISPLAY_NAMES = [
    "Minh Tuấn", "Hương Lan", "Đức Thịnh", "Thu Hà", "Văn Khoa",
    "Bảo Châu", "Quang Huy", "Ngọc Mai", "Trọng Nghĩa", "Kim Phụng",
    "Tiến Đạt", "Thùy Linh", "Hoàng Nam", "Yến Nhi", "Phúc Khang",
    "Diệu My", "Đình Khải", "Trang Anh", "Hải Long", "Bích Ngọc",
    "Minh Khánh", "Hoa Sen", "Tuấn Kiệt", "Như Quỳnh", "Gia Bảo",
    "Thanh Tuyền", "Dũng Sức", "Ngân Hà", "Vĩnh Phúc", "Mỹ Duyên",
    "Hào Hiệp", "Quế Anh", "Đăng Khoa", "Thái Hà", "Bình An",
    "Thu Ngân", "Việt Anh", "Phương Thảo", "Trung Hiếu", "Xuân Mai",
    "Khánh Linh", "Nam Phong", "Hồng Nhung", "Thành Đạt", "Lan Anh",
]

CEFR_LEVELS = ["A1", "A1", "A2", "A2", "A2", "B1", "B1", "B1", "B2", "B2", "C1"]
XP_RANGES = {
    "A1": (0, 500),
    "A2": (500, 1500),
    "B1": (1500, 4000),
    "B2": (4000, 8000),
    "C1": (8000, 15000),
}
RANKS = {
    "A1": "bronze",
    "A2": "bronze",
    "B1": "silver",
    "B2": "gold",
    "C1": "platinum",
}


async def seed_demo_users(db: AsyncSession, user_role) -> list[User]:
    """Create TOTAL_USERS demo learner accounts spread over the past SEED_DAYS.
    Call cleanup_demo_users() before this to avoid duplicates."""
    print(f"  Creating {TOTAL_USERS} demo users...")
    created: list[User] = []

    for i in range(TOTAL_USERS):
        name = DISPLAY_NAMES[i] if i < len(DISPLAY_NAMES) else f"Learner {i+1}"
        safe = name.lower().replace(" ", "").replace("đ", "d")
        username = f"demo_{safe}_{i}"
        email = f"demo_{i}@lexilingo.dev"

        # Distribute registrations: more recent users, slight growth curve
        if i < 10:
            reg_day = rand_between(60, 90)
        elif i < 25:
            reg_day = rand_between(30, 60)
        else:
            reg_day = rand_between(1, 30)

        level = random.choice(CEFR_LEVELS)
        xp_lo, xp_hi = XP_RANGES[level]
        total_xp = rand_between(xp_lo, xp_hi)
        numeric_level = max(1, total_xp // 100)

        user = User(
            email=email,
            username=username,
            hashed_password=DEMO_PASSWORD_HASH,
            display_name=name,
            native_language="vi",
            target_language="en",
            level=level,
            total_xp=total_xp,
            numeric_level=min(numeric_level, 999),
            rank=RANKS.get(level, "bronze"),
            role_id=user_role.id,
            is_active=True,
            is_verified=True,
            provider=["local"],
        )
        user.created_at = days_ago(reg_day)
        db.add(user)
        created.append(user)

    await db.commit()
    for u in created:
        await db.refresh(u)

    print(f"     {len(created)} demo users created")
    return created


# ─── 2. Wallets & Streaks ─────────────────────────────────────────────────────

async def seed_wallets_and_streaks(db: AsyncSession, users: list[User]):
    print("  Creating wallets & streaks...")
    w_new = s_new = 0

    for user in users:
        # Wallet
        res = await db.execute(select(UserWallet).where(UserWallet.user_id == user.id))
        if not res.scalar_one_or_none():
            gems = rand_between(0, 500)
            db.add(UserWallet(
                user_id=user.id,
                gems=gems,
                total_gems_earned=gems + rand_between(0, 200),
                total_gems_spent=rand_between(0, 100),
            ))
            w_new += 1

        # Streak
        res = await db.execute(select(Streak).where(Streak.user_id == user.id))
        if not res.scalar_one_or_none():
            cur = rand_between(0, 30)
            longest = cur + rand_between(0, 20)
            last_active = date_ago(rand_between(0, 2))
            db.add(Streak(
                user_id=user.id,
                current_streak=cur,
                longest_streak=longest,
                last_activity_date=last_active,
                total_days_active=rand_between(cur, SEED_DAYS),
            ))
            s_new += 1

    await db.commit()
    print(f"     {w_new} wallets, {s_new} streaks created")


# ─── 3. Daily Activity (DAU/WAU/MAU source) ───────────────────────────────────

async def seed_daily_activities(db: AsyncSession, users: list[User]):
    """Populate daily_activities so engagement charts have data."""
    print(f"  Seeding daily activities for {SEED_DAYS} days...")
    new_count = 0

    for day_offset in range(SEED_DAYS, 0, -1):
        act_date = date_ago(day_offset)

        # For each user registered before this date, maybe active
        for user in users:
            # Only include users that had registered by this date
            reg_date = user.created_at.date() if user.created_at else date_ago(SEED_DAYS)
            if act_date < reg_date:
                continue

            # Probability of activity (newer users more active)
            age_days = (TODAY - reg_date).days
            # Newer users (< 14 days old) are more active
            prob = DAILY_ACTIVE_RATIO + (0.25 if age_days < 14 else 0.0)
            if random.random() > prob:
                continue

            # Check exists
            res = await db.execute(
                select(DailyActivity).where(
                    DailyActivity.user_id == user.id,
                    DailyActivity.activity_date == act_date,
                )
            )
            if res.scalar_one_or_none():
                continue

            xp = rand_between(10, 120)
            lessons = rand_between(0, 4)
            study_min = rand_between(5, 45)
            vocab_reviewed = rand_between(0, 20)
            goal_met = xp >= 20

            db.add(DailyActivity(
                user_id=user.id,
                activity_date=act_date,
                xp_earned=xp,
                lessons_completed=lessons,
                study_time_minutes=study_min,
                vocabulary_reviewed=vocab_reviewed,
                daily_goal_met=goal_met,
                daily_goal_xp=20,
            ))
            new_count += 1

        # Batch commit every 7 days to avoid huge transaction
        if day_offset % 7 == 0:
            await db.commit()

    await db.commit()
    print(f"     {new_count} daily activity records created")


# ─── 4. Course Enrolments & Progress ─────────────────────────────────────────

async def seed_course_progress(db: AsyncSession, users: list[User], courses: list[Course]):
    """Enrol users in courses with varying progress (feeds popularity + funnel charts)."""
    print(f"  Seeding course enrolments for {len(courses)} courses...")
    new_count = 0

    # Weight courses: more popular for A1-B1 levels
    course_weights = []
    for c in courses:
        lvl = c.level or "A1"
        if lvl in ("A1", "A2"):
            course_weights.append(4)
        elif lvl in ("B1", "B2"):
            course_weights.append(3)
        else:
            course_weights.append(1)

    for user in users:
        # Each user enrols in 1–4 courses
        num_courses = rand_between(1, 4)
        enrolled = random.choices(courses, weights=course_weights, k=num_courses)
        enrolled = list({c.id: c for c in enrolled}.values())  # dedup

        for course in enrolled:
            res = await db.execute(
                select(UserCourseProgress).where(
                    UserCourseProgress.user_id == user.id,
                    UserCourseProgress.course_id == course.id,
                )
            )
            if res.scalar_one_or_none():
                continue

            # Realistic progress distribution:
            # 30% barely started (0-10%), 40% mid (10-75%), 20% near end (75-99%), 10% completed
            progress_tier = w_choice(
                ["barely", "mid", "near", "complete"],
                weights=[30, 40, 20, 10],
            )
            if progress_tier == "barely":
                pct = rand_between(0, 10)
            elif progress_tier == "mid":
                pct = rand_between(10, 75)
            elif progress_tier == "near":
                pct = rand_between(75, 99)
            else:
                pct = 100

            started_days_ago = rand_between(1, SEED_DAYS)
            xp_earned = int(pct * rand_between(2, 5))

            db.add(UserCourseProgress(
                user_id=user.id,
                course_id=course.id,
                progress_percentage=float(pct),
                lessons_completed=max(0, int(pct / 10)),
                total_xp_earned=xp_earned,
                started_at=days_ago(started_days_ago),
                last_activity_at=days_ago(rand_between(0, started_days_ago)),
            ))
            new_count += 1

    await db.commit()
    print(f"     {new_count} course enrolments created")


# ─── 5. Lesson Completions ────────────────────────────────────────────────────

async def seed_lesson_completions(db: AsyncSession, users: list[User], lessons: list):
    """Record lesson completions for users (fills LessonCompletion table)."""
    if not lessons:
        print("  No lessons found — skipping lesson completions")
        return

    print(f"  Seeding lesson completions ({len(lessons)} lessons available)...")
    new_count = 0

    for user in users:
        # Users complete between 0 and 15 distinct lessons
        num = rand_between(0, min(15, len(lessons)))
        if num == 0:
            continue

        selected = random.sample(lessons, num)
        for lesson in selected:
            res = await db.execute(
                select(LessonCompletion).where(
                    LessonCompletion.user_id == user.id,
                    LessonCompletion.lesson_id == lesson.id,
                )
            )
            if res.scalar_one_or_none():
                continue

            passed = random.random() > 0.25  # 75% pass rate
            score = rand_between(70, 100) if passed else rand_between(30, 69)
            completed_at = days_ago(rand_between(0, 60))

            lc = LessonCompletion(
                user_id=user.id,
                lesson_id=lesson.id,
                is_passed=passed,
                best_score=score,
            )
            lc.completed_at = completed_at
            db.add(lc)
            new_count += 1

    await db.commit()
    print(f"     {new_count} lesson completions created")


# ─── 6. User Vocabulary (SRS) ─────────────────────────────────────────────────

async def seed_user_vocabulary(db: AsyncSession, users: list[User], vocab_items: list):
    """Assign vocabulary words to users with SRS status (feeds effectiveness chart)."""
    if not vocab_items:
        print("  No vocabulary items found — skipping")
        return

    print(f"  Seeding user vocabulary ({len(vocab_items)} items available)...")
    new_count = 0
    # Take a sample of vocab items to keep things fast
    pool = vocab_items[:80] if len(vocab_items) > 80 else vocab_items

    for user in users:
        num = rand_between(5, min(40, len(pool)))
        selected = random.sample(pool, num)

        for vitem in selected:
            res = await db.execute(
                select(UserVocabulary).where(
                    UserVocabulary.user_id == user.id,
                    UserVocabulary.vocabulary_id == vitem.id,
                )
            )
            if res.scalar_one_or_none():
                continue

            status = w_choice(
                ["learning", "reviewing", "mastered"],
                weights=[40, 35, 25],
            )
            reviews = rand_between(1, 20)
            correct = rand_between(int(reviews * 0.5), reviews)
            interval = rand_between(1, 30) if status == "mastered" else rand_between(1, 7)

            db.add(UserVocabulary(
                user_id=user.id,
                vocabulary_id=vitem.id,
                status=VocabularyStatus(status),
                ease_factor=round(random.uniform(1.8, 3.0), 2),
                interval=interval,
                repetitions=rand_between(0, 10),
                total_reviews=reviews,
                correct_reviews=correct,
                streak=rand_between(0, 5),
                total_xp_earned=correct * 5,
                last_reviewed_at=days_ago(rand_between(0, 30)),
            ))
            new_count += 1

    await db.commit()
    print(f"     {new_count} user vocabulary records created")


# ─── 7. Achievements ─────────────────────────────────────────────────────────

async def seed_user_achievements(db: AsyncSession, users: list[User], achievements: list):
    """Unlock a subset of achievements for users (makes achievement stats non-empty)."""
    if not achievements:
        print("  No achievements found — skipping")
        return

    print(f"  Seeding user achievements ({len(achievements)} available)...")
    new_count = 0
    common_achievs = [a for a in achievements if a.rarity == "common"]
    rare_achievs = [a for a in achievements if a.rarity in ("rare", "epic")]

    for user in users:
        # Every user gets 1-4 common achievements
        num_common = rand_between(1, min(4, len(common_achievs)))
        unlocked = random.sample(common_achievs, num_common)

        # Some users also get rare achievements
        if rare_achievs and random.random() > 0.5:
            unlocked.append(random.choice(rare_achievs))

        for ach in unlocked:
            res = await db.execute(
                select(UserAchievement).where(
                    UserAchievement.user_id == user.id,
                    UserAchievement.achievement_id == ach.id,
                )
            )
            if res.scalar_one_or_none():
                continue

            ua = UserAchievement(
                user_id=user.id,
                achievement_id=ach.id,
                progress=100,
                is_showcased=random.random() > 0.7,
            )
            ua.unlocked_at = days_ago(rand_between(0, 60))
            db.add(ua)
            new_count += 1

    await db.commit()
    print(f"     {new_count} user achievements created")


# ─── 8. Leaderboard entries ───────────────────────────────────────────────────

async def seed_leaderboard(db: AsyncSession, users: list[User]):
    """Create weekly leaderboard entries for the past 4 weeks."""
    print("  Seeding leaderboard entries...")
    new_count = 0
    leagues = ["bronze", "silver", "gold", "platinum"]

    for week_offset in range(4):
        # LeaderboardEntry uses TZDateTime so pass datetime, not date
        week_end_dt = NOW - timedelta(weeks=week_offset)
        week_start_dt = week_end_dt - timedelta(days=7)

        # Take a subset of users for this week
        active_this_week = random.sample(users, k=min(len(users), rand_between(10, 30)))

        for rank_pos, user in enumerate(active_this_week, start=1):
            res = await db.execute(
                select(LeaderboardEntry).where(
                    LeaderboardEntry.user_id == user.id,
                    LeaderboardEntry.week_start == week_start_dt,
                )
            )
            if res.scalar_one_or_none():
                continue

            xp = rand_between(20, 800)
            league = w_choice(leagues, weights=[40, 30, 20, 10])
            db.add(LeaderboardEntry(
                user_id=user.id,
                week_start=week_start_dt,
                week_end=week_end_dt,
                league=league,
                xp_earned=xp,
                lessons_completed=rand_between(1, 12),
                current_rank=rank_pos,
                is_promoted=random.random() > 0.85,
                is_demoted=False,
            ))
            new_count += 1

    await db.commit()
    print(f"     {new_count} leaderboard entries created")


# ─── Main ─────────────────────────────────────────────────────────────────────

async def main():
    print("\n" + "=" * 56)
    print("  LexiLingo — Demo Data Seed (Admin Charts)")
    print("=" * 56 + "\n")

    async with AsyncSessionLocal() as db:
        # ── 0. Cleanup demo users to prevent duplicates ──────────────────────
        print(" Cleaning up old demo users...")
        await cleanup_demo_users(db)

        # ── Load reference data ──────────────────────────────────────────────
        user_role_res = await db.execute(select(Role).where(Role.slug == "user"))
        user_role = user_role_res.scalar_one_or_none()
        if not user_role:
            print(" Role 'user' not found. Run seed_data.py first.\n")
            return

        courses_res = await db.execute(
            select(Course).where(Course.is_published == True)
        )
        courses = list(courses_res.scalars().all())
        if not courses:
            print(" No published courses found. Run seed_data.py first.\n")
            return
        print(f"  Found {len(courses)} published courses")

        lessons_res = await db.execute(select(Lesson))
        lessons = list(lessons_res.scalars().all())
        print(f"  Found {len(lessons)} lessons")

        vocab_res = await db.execute(select(VocabularyItem))
        vocab_items = list(vocab_res.scalars().all())
        print(f"  Found {len(vocab_items)} vocabulary items")

        achievements_res = await db.execute(select(Achievement))
        achievements = list(achievements_res.scalars().all())
        print(f"  Found {len(achievements)} achievements\n")

        # ── Seed ─────────────────────────────────────────────────────────────
        users = await seed_demo_users(db, user_role)

        await seed_wallets_and_streaks(db, users)
        await seed_daily_activities(db, users)
        await seed_course_progress(db, users, courses)
        await seed_lesson_completions(db, users, lessons)
        await seed_user_vocabulary(db, users, vocab_items)
        await seed_user_achievements(db, users, achievements)
        await seed_leaderboard(db, users)

        # ── Summary ──────────────────────────────────────────────────────────
        total_users = await db.scalar(select(func.count(User.id)))
        total_da = await db.scalar(select(func.count(DailyActivity.id)))
        total_ucp = await db.scalar(select(func.count(UserCourseProgress.id)))
        total_uv = await db.scalar(select(func.count(UserVocabulary.id)))
        total_ua = await db.scalar(select(func.count(UserAchievement.id)))
        total_lb = await db.scalar(select(func.count(LeaderboardEntry.id)))

        print("\n" + "=" * 56)
        print("  Seeding complete!")
        print("=" * 56)
        print(f"  Users total              : {total_users}")
        print(f"  Daily activity records   : {total_da}")
        print(f"  Course enrolments        : {total_ucp}")
        print(f"  User vocabulary records  : {total_uv}")
        print(f"  User achievements        : {total_ua}")
        print(f"  Leaderboard entries      : {total_lb}")
        print()
        print("  Admin dashboard endpoints now have data:")
        print("    GET /admin/analytics/dashboard/kpis")
        print("    GET /admin/analytics/dashboard/user-growth")
        print("    GET /admin/analytics/dashboard/engagement")
        print("    GET /admin/analytics/dashboard/course-popularity")
        print("    GET /admin/analytics/dashboard/completion-funnel")
        print("    GET /admin/analytics/vocabulary-effectiveness")
        print()


if __name__ == "__main__":
    asyncio.run(main())
