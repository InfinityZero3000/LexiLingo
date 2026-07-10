"""
Seed Analytics Data
===================
Populates database with realistic user activity data so the admin dashboard
has meaningful charts (user growth, DAU/WAU/MAU, course popularity, funnel, etc.)

Run AFTER seed_data.py has already seeded roles, achievements, shop items.
This script handles: users, enrollments, lesson completions, daily activities,
streaks, wallets, XP transactions, game sessions, leaderboard entries, vocabulary.

Dedup strategy (safe to re-run):
  • At startup, deletes ALL @lexilingo.test users + admin*@lexilingo.dev accounts
    and their cascade-linked activity data.
  • Static reference data (courses, vocab, achievements) is NEVER touched.
  • Then recreates fresh test users with new random activity data.

Usage:
    cd backend-service
    venv/bin/python3 -m scripts.seed_analytics
"""

import asyncio
import random
import uuid
from datetime import date, datetime, timedelta, timezone
from sqlalchemy import select, func, delete, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.models import (
    Role, Achievement,
    Course, Lesson,
    User,
    UserCourseProgress, LessonCompletion, DailyActivity, Streak,
    UserWallet, WalletTransaction,
    XPTransaction, GameSession,
    LeaderboardEntry,
    UserAchievement,
    UserVocabulary, VocabularyItem,
)

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────

# Pre-computed bcrypt hash for "Test@123!" (rounds=12)
FIXED_PW_HASH = "$2b$12$GZLH6pFpC5SfowJkboseD.Y3EqbeXeMMEoDUNSWcH/V2zM7Ww9ix."

TODAY = datetime.now(timezone.utc).date()
SEED_DAYS = 90  # activity window

random.seed(42)  # reproducible


# ─────────────────────────────────────────────
# User personas — realistic data templates
# ─────────────────────────────────────────────

FEMALE_NAMES = [
    "Linh", "Hương", "Phương", "Mai", "Thuy", "Lan", "Anh", "Huong", "Trang", "Yen",
    "Ngoc", "Hang", "Hoa", "Thu", "Nhi", "Van", "Loan", "Nhung", "Thao", "Dung",
    "Sarah", "Emma", "Chloe", "Olivia", "Mia", "Sophie", "Lily", "Grace", "Zoe",
]
MALE_NAMES = [
    "Minh", "Hieu", "Nam", "Tuan", "Duc", "Dat", "Hung", "Khai", "Lam", "Vinh",
    "Thanh", "Binh", "Phuc", "Hoan", "Duy", "Long", "Thinh", "Trung", "Khoa", "Vu",
    "James", "Ethan", "Noah", "Lucas", "Oliver", "William", "Henry", "Jack", "Leo",
]
SURNAMES = [
    "Nguyen", "Tran", "Le", "Pham", "Hoang", "Vu", "Dang", "Bui", "Do", "Ho",
    "Phan", "Truong", "Ngo", "Duong", "Dinh", "Ly", "Mai", "Cao", "Trinh", "Luu",
]

CEFR_LEVELS = ["A1", "A1", "A1", "A2", "A2", "B1", "B1", "B1", "B2", "B2", "C1"]
RANKS = {
    "A1": "bronze", "A2": "bronze",
    "B1": "silver", "B2": "gold",
    "C1": "platinum", "C2": "diamond",
}
XP_BY_LEVEL = {
    "A1": (0, 500), "A2": (500, 1500),
    "B1": (1500, 4000), "B2": (4000, 8000),
    "C1": (8000, 15000), "C2": (15000, 30000),
}
GAME_TYPES = [
    "word_scramble", "fill_blank", "matching",
    "spelling_bee", "grammar_quiz", "hangman",
]

# Course enrollment weights (by course title substring → relative probability)
COURSE_WEIGHTS = {
    "English for Beginners":          14,
    "Everyday English":               10,
    "Pre-Intermediate English":        9,
    "Upper-Intermediate English":      7,
    "Advanced English Mastery":        4,
    "IELTS Foundation: Band 3":       12,
    "IELTS Starter: Band 4":          11,
    "IELTS Preparation":               9,
    "IELTS Academic":                  7,
    "IELTS General Training":          8,
    "Business English":                5,
}

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

def pick_name(gender: str) -> tuple[str, str]:
    pool = FEMALE_NAMES if gender == "F" else MALE_NAMES
    first = random.choice(pool)
    last = random.choice(SURNAMES)
    return first, last


def days_ago(n: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=n)


def date_ago(n: int) -> date:
    return TODAY - timedelta(days=n)


def weighted_choice(mapping: dict) -> str:
    keys = list(mapping.keys())
    weights = list(mapping.values())
    return random.choices(keys, weights=weights, k=1)[0]


# ─────────────────────────────────────────────
# 0. Cleanup — remove stale test users
# ─────────────────────────────────────────────

async def cleanup_test_users(db: AsyncSession) -> None:
    """
    Delete all @lexilingo.test users and admin*@lexilingo.dev accounts
    along with their cascade-linked data, so we can re-seed fresh.
    Real users (Google OAuth etc.) are never touched.
    """
    result = await db.execute(
        select(User).where(
            or_(
                User.email.like("%@lexilingo.test"),
                User.email.like("admin%@lexilingo.dev"),
            )
        )
    )
    test_users = result.scalars().all()
    if not test_users:
        print("  No existing test users to clean up.")
        return

    ids = [u.id for u in test_users]
    await db.execute(delete(User).where(User.id.in_(ids)))
    await db.commit()
    print(f"  ️  Removed {len(ids)} old test/admin users (and all cascade-linked data)")


# ─────────────────────────────────────────────
# 1. Ensure base data is present
# ─────────────────────────────────────────────

async def ensure_base_data(db: AsyncSession) -> dict:
    """Make sure roles, courses, achievements exist. Seed them if not."""
    print(" Verifying base data…")

    role_count = await db.scalar(select(func.count(Role.id))) or 0
    if role_count == 0:
        print("  ️  No roles found — running base seed first…")
        from scripts.seed_data import (
            seed_roles, seed_permissions, seed_achievements,
            seed_shop_items,
        )
        roles = await seed_roles(db)
        await seed_permissions(db, roles)
        await seed_achievements(db)
        await seed_shop_items(db)
    else:
        print(f"   Roles: {role_count} (OK)")

    course_count = await db.scalar(select(func.count(Course.id))) or 0
    if course_count == 0:
        print("  ️  No courses found — running course seed…")
        from scripts.seed_courses import main as seed_courses_main
        await seed_courses_main()
    else:
        print(f"   Courses: {course_count} (OK)")

    # Load role + course objects
    roles_res = await db.execute(select(Role))
    roles = {r.slug: r for r in roles_res.scalars().all()}

    courses_res = await db.execute(select(Course).where(Course.is_published == True))
    courses = courses_res.scalars().all()

    achievements_res = await db.execute(select(Achievement))
    achievements = achievements_res.scalars().all()

    vocab_res = await db.execute(select(VocabularyItem))
    vocab_items = vocab_res.scalars().all()

    print()
    return {
        "roles": roles,
        "courses": courses,
        "achievements": achievements,
        "vocab_items": vocab_items,
    }


# ─────────────────────────────────────────────
# 2. Seed users (~70 across 90 days)
# ─────────────────────────────────────────────

async def seed_users(db: AsyncSession, roles: dict) -> list[User]:
    """
    Create ~70 test users with realistic signup distribution:
    - Slow growth early (2-3/week) → accelerating to 7-10/week.
    - Mix of CEFR levels, activity rates, genders.
    """
    print(" Seeding test users…")

    user_role = roles.get("user")
    admin_role = roles.get("admin")
    super_role = roles.get("super_admin")

    # Distribute signups: more recent weeks have more users
    # 13-week window: week 1 oldest, week 13 most recent
    signup_dist = [2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 8, 7]  # per week, oldest→latest
    created_users: list[User] = []
    user_num = 1

    for week_idx, count in enumerate(signup_dist):
        days_back_start = SEED_DAYS - week_idx * 7
        days_back_end   = max(0, days_back_start - 7)

        for _ in range(count):
            gender = random.choice(["M", "F"])
            first, last = pick_name(gender)
            level = random.choice(CEFR_LEVELS)
            lo, hi = XP_BY_LEVEL[level]
            total_xp = random.randint(lo, hi)

            # Determine numeric_level from XP
            numeric_level = max(1, total_xp // 200)

            username = f"{first.lower()}{last.lower()}{user_num}"
            email    = f"{username}@lexilingo.test"

            # signup time: random within the week window
            days_offset = random.randint(days_back_end, days_back_start)
            signed_up   = days_ago(days_offset)

            u = User(
                id=uuid.uuid4(),
                email=email,
                username=username,
                hashed_password=FIXED_PW_HASH,
                display_name=f"{first} {last}",
                native_language="vi",
                target_language="en",
                level=level,
                total_xp=total_xp,
                numeric_level=numeric_level,
                rank=RANKS.get(level, "bronze"),
                is_active=True,
                is_verified=True,
                provider=["local"],
            )
            u.created_at = signed_up  # type: ignore[attr-defined]
            db.add(u)
            created_users.append(u)
            user_num += 1

    # 2 admin users
    for i, (slug, role) in enumerate([("admin", admin_role), ("super_admin", super_role)]):
        if role is None:
            continue
        admin = User(
            id=uuid.uuid4(),
            email=f"admin{i+1}@lexilingo.dev",
            username=f"admin{i+1}",
            hashed_password=FIXED_PW_HASH,
            display_name=f"Admin {i+1}",
            native_language="vi",
            target_language="en",
            level="C1",
            total_xp=20000 + i * 5000,
            numeric_level=100,
            rank="master",
            is_active=True,
            is_verified=True,
            provider=["local"],
            role_id=role.id,
        )
        admin.created_at = days_ago(SEED_DAYS)  # type: ignore[attr-defined]
        db.add(admin)
        created_users.append(admin)

    await db.commit()
    for u in created_users:
        await db.refresh(u)

    print(f"   {len(created_users)} users created\n")
    return created_users


# ─────────────────────────────────────────────
# 3. Course enrollments
# ─────────────────────────────────────────────

async def seed_enrollments(
    db: AsyncSession,
    users: list[User],
    courses: list[Course],
) -> None:
    """Enroll each user in 1-4 courses. Weights mimic realistic IELTS-heavy demand."""
    print(" Seeding course enrollments…")

    # Build weighted course list
    weighted_courses: list[tuple[Course, int]] = []
    for course in courses:
        for substr, w in COURSE_WEIGHTS.items():
            if substr.lower() in course.title.lower():
                weighted_courses.append((course, w))
                break
        else:
            weighted_courses.append((course, 3))

    user_ids = [u.id for u in users]
    existing = await db.scalar(
        select(func.count(UserCourseProgress.id))
        .where(UserCourseProgress.user_id.in_(user_ids))
    ) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} enrollments already exist for these users — skipping\n")
        return

    all_courses = [c for c, _ in weighted_courses]
    all_weights = [w for _, w in weighted_courses]
    count = 0

    for user in users:
        # Number of courses: skewed toward fewer
        n_courses = random.choices([1, 2, 3, 4], weights=[30, 35, 25, 10], k=1)[0]
        chosen = random.choices(all_courses, weights=all_weights, k=min(n_courses, len(all_courses)))
        seen: set[uuid.UUID] = set()

        for course in chosen:
            if course.id in seen:
                continue
            seen.add(course.id)

            # Determine progress
            progress_bucket = random.choices(
                ["none", "started", "halfway", "almost", "done"],
                weights=[15, 30, 25, 20, 10], k=1
            )[0]
            pct = {
                "none":    0.0,
                "started": random.uniform(1, 25),
                "halfway": random.uniform(25, 60),
                "almost":  random.uniform(60, 95),
                "done":    100.0,
            }[progress_bucket]

            total_lessons = max(course.total_lessons or 1, 1)
            lessons_comp  = int(pct / 100 * total_lessons)
            xp_earned     = lessons_comp * random.randint(8, 25)

            # started_at: between user signup and today
            user_days_since = (TODAY - user.created_at.date()).days  # type: ignore[attr-defined]
            enrolled_ago    = random.randint(0, max(user_days_since, 1))
            started_at      = days_ago(enrolled_ago)
            last_active     = days_ago(random.randint(0, min(enrolled_ago, 14)))

            prog = UserCourseProgress(
                user_id=user.id,
                course_id=course.id,
                progress_percentage=round(pct, 1),
                lessons_completed=lessons_comp,
                total_xp_earned=xp_earned,
                started_at=started_at,
                last_activity_at=last_active,
            )
            db.add(prog)
            count += 1

    await db.commit()
    print(f"   {count} enrollment records\n")


# ─────────────────────────────────────────────
# 4. Lesson completions
# ─────────────────────────────────────────────

async def seed_lesson_completions(
    db: AsyncSession,
    users: list[User],
    courses: list[Course],
) -> None:
    """For each enrollment with progress > 0, create lesson completion records."""
    print(" Seeding lesson completions…")

    user_ids = [u.id for u in users]
    existing = await db.scalar(
        select(func.count(LessonCompletion.id))
        .where(LessonCompletion.user_id.in_(user_ids))
    ) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} completions already exist for these users — skipping\n")
        return

    # Load only enrollments for THIS batch of users
    enroll_res = await db.execute(
        select(UserCourseProgress).where(
            UserCourseProgress.progress_percentage > 0,
            UserCourseProgress.user_id.in_(user_ids),
        )
    )
    enrollments = enroll_res.scalars().all()

    # Load lessons by course
    course_lessons: dict[uuid.UUID, list[Lesson]] = {}
    for course in courses:
        lessons_res = await db.execute(
            select(Lesson)
            .where(Lesson.course_id == course.id)
            .order_by(Lesson.order_index)
        )
        course_lessons[course.id] = lessons_res.scalars().all()

    count = 0
    seen: set[tuple] = set()  # (user_id, lesson_id)

    for enr in enrollments:
        lessons = course_lessons.get(enr.course_id, [])
        if not lessons:
            continue

        # How many lessons user has completed
        n = min(enr.lessons_completed, len(lessons))
        if n == 0:
            continue

        for lesson in lessons[:n]:
            key = (enr.user_id, lesson.id)
            if key in seen:
                continue
            seen.add(key)

            score = random.randint(60, 100)
            completed_at = enr.started_at + timedelta(
                days=random.randint(0, max((TODAY - enr.started_at.date()).days, 1))
            )
            lc = LessonCompletion(
                user_id=enr.user_id,
                lesson_id=lesson.id,
                is_passed=score >= (lesson.pass_threshold or 60),
                best_score=score,
                completed_at=completed_at,
            )
            db.add(lc)
            count += 1

        if count % 500 == 0:
            await db.flush()

    await db.commit()
    print(f"   {count} lesson completion records\n")


# ─────────────────────────────────────────────
# 5. Daily activities (90 days × varied users)
# ─────────────────────────────────────────────

async def seed_daily_activities(
    db: AsyncSession,
    users: list[User],
) -> None:
    """
    Create daily_activities for up to 90 days.
    Engagement tiers:
      - High  (20 %): 55-70 % of days active
      - Mid   (40 %): 25-40 % of days active
      - Low   (40 %): 5-15  % of days active
    → Results in realistic DAU ~12-20 of ~70 users.
    """
    print(" Seeding daily activities…")

    user_ids = [u.id for u in users]
    existing = await db.scalar(
        select(func.count(DailyActivity.id))
        .where(DailyActivity.user_id.in_(user_ids))
    ) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} activity records already exist for these users — skipping\n")
        return

    # Assign each user an engagement tier
    tiers: dict[uuid.UUID, float] = {}
    for u in users:
        roll = random.random()
        if roll < 0.20:
            tiers[u.id] = random.uniform(0.55, 0.70)  # high
        elif roll < 0.60:
            tiers[u.id] = random.uniform(0.25, 0.40)  # mid
        else:
            tiers[u.id] = random.uniform(0.05, 0.15)  # low

    count = 0
    batch: list[DailyActivity] = []

    for u in users:
        activity_rate = tiers[u.id]
        # User can only have activity from signup date onward
        user_joined = u.created_at.date()  # type: ignore[attr-defined]
        days_available = (TODAY - user_joined).days + 1

        for d in range(min(days_available, SEED_DAYS)):
            if random.random() > activity_rate:
                continue  # user not active this day

            act_date = date_ago(d)
            xp         = random.randint(10, 140)
            lessons    = random.choices([0, 1, 2, 3], weights=[30, 40, 20, 10], k=1)[0]
            study_mins = random.randint(5, 55)
            vocab_rev  = random.randint(0, 25)
            goal_xp    = 20
            goal_met   = xp >= goal_xp

            batch.append(DailyActivity(
                user_id=u.id,
                activity_date=act_date,
                xp_earned=xp,
                lessons_completed=lessons,
                study_time_minutes=study_mins,
                vocabulary_reviewed=vocab_rev,
                daily_goal_met=goal_met,
                daily_goal_xp=goal_xp,
            ))
            count += 1

            if len(batch) >= 500:
                db.add_all(batch)
                await db.flush()
                batch.clear()

    if batch:
        db.add_all(batch)

    await db.commit()
    print(f"   {count} daily activity records ({SEED_DAYS}-day window)\n")


# ─────────────────────────────────────────────
# 6. Streaks
# ─────────────────────────────────────────────

async def seed_streaks(db: AsyncSession, users: list[User]) -> None:
    print(" Seeding streaks…")

    user_ids = [u.id for u in users]
    existing = await db.scalar(
        select(func.count(Streak.id))
        .where(Streak.user_id.in_(user_ids))
    ) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} streak records already exist for these users — skipping\n")
        return

    count = 0
    for u in users:
        level = getattr(u, "level", "A1")
        # More active levels have longer streaks
        max_streak = {"A1": 10, "A2": 15, "B1": 25, "B2": 40, "C1": 60, "C2": 90}.get(level, 10)
        current  = random.randint(0, max_streak)
        longest  = random.randint(current, max_streak + 10)
        total_active = random.randint(longest, longest + 30)

        s = Streak(
            user_id=u.id,
            current_streak=current,
            longest_streak=longest,
            last_activity_date=date_ago(0 if current > 0 else random.randint(1, 7)),
            total_days_active=total_active,
            freeze_count=random.randint(0, 3),
        )
        db.add(s)
        count += 1

    await db.commit()
    print(f"   {count} streak records\n")


# ─────────────────────────────────────────────
# 7. Wallets + transactions
# ─────────────────────────────────────────────

async def seed_wallets(db: AsyncSession, users: list[User]) -> None:
    print(" Seeding user wallets…")

    user_ids = [u.id for u in users]
    existing = await db.scalar(
        select(func.count(UserWallet.id))
        .where(UserWallet.user_id.in_(user_ids))
    ) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} wallets already exist for these users — skipping\n")
        return

    wallets: list[UserWallet] = []
    txns: list[WalletTransaction] = []

    for u in users:
        total_earned = random.randint(20, 500)
        total_spent  = random.randint(0, total_earned // 2)
        balance      = total_earned - total_spent

        w = UserWallet(
            user_id=u.id,
            gems=balance,
            total_gems_earned=total_earned,
            total_gems_spent=total_spent,
        )
        db.add(w)
        await db.flush()

        # 2-4 wallet transactions per user
        for _ in range(random.randint(2, 4)):
            earn = random.randint(5, 40)
            txns.append(WalletTransaction(
                wallet_id=w.id,
                user_id=u.id,
                transaction_type="earn",
                amount=earn,
                balance_after=balance,
                source="lesson_complete",
                description="Completed a lesson",
            ))

    db.add_all(txns)
    await db.commit()
    print(f"   {len(wallets) or 'all'} wallets + {len(txns)} transactions\n")


# ─────────────────────────────────────────────
# 8. XP transactions
# ─────────────────────────────────────────────

async def seed_xp_transactions(
    db: AsyncSession,
    users: list[User],
) -> None:
    """Create ~5-15 XP records per user spanning their activity period."""
    print(" Seeding XP transactions…")

    existing = await db.scalar(select(func.count(XPTransaction.id))) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} XP transactions already exist — skipping\n")
        return

    sources = [
        ("lesson",          "lesson_complete",   (15, 50)),
        ("game",            "word_scramble",      (5, 30)),
        ("game",            "spelling_bee",       (5, 25)),
        ("daily_challenge", "daily_goal",         (10, 20)),
        ("news",            "article_read",       (3, 15)),
    ]

    batch: list[XPTransaction] = []
    for u in users:
        n = random.randint(5, 15)
        user_days = (TODAY - u.created_at.date()).days + 1  # type: ignore[attr-defined]

        for _ in range(n):
            src_type, src_detail, (lo, hi) = random.choice(sources)
            base   = random.randint(lo, hi)
            mult   = random.choice([1.0, 1.0, 1.0, 1.5, 2.0])
            amount = int(base * mult)
            lvl    = getattr(u, "numeric_level", 1)

            tx = XPTransaction(
                user_id=u.id,
                amount=amount,
                base_amount=base,
                multiplier=mult,
                source=src_type,
                source_detail=src_detail,
                level_before=max(1, lvl - 1),
                level_after=lvl,
                leveled_up=(random.random() < 0.05),
            )
            tx.created_at = days_ago(random.randint(0, min(user_days, SEED_DAYS)))  # type: ignore
            batch.append(tx)

        if len(batch) >= 300:
            db.add_all(batch)
            await db.flush()
            batch.clear()

    if batch:
        db.add_all(batch)

    await db.commit()
    total = await db.scalar(select(func.count(XPTransaction.id))) or 0
    print(f"   {total} XP transaction records\n")


# ─────────────────────────────────────────────
# 9. Game sessions
# ─────────────────────────────────────────────

async def seed_game_sessions(
    db: AsyncSession,
    users: list[User],
) -> None:
    """Create 3-8 game sessions per active user."""
    print(" Seeding game sessions…")

    existing = await db.scalar(select(func.count(GameSession.id))) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} game sessions already exist — skipping\n")
        return

    categories = ["animals", "food", "sports", "travel", "technology", "academic", "emotions"]
    batch: list[GameSession] = []

    for u in users:
        n = random.randint(3, 8)
        user_days = max((TODAY - u.created_at.date()).days, 1)  # type: ignore[attr-defined]
        level = getattr(u, "level", "A1")

        for _ in range(n):
            total_q    = random.randint(5, 20)
            correct    = random.randint(int(total_q * 0.4), total_q)
            score      = int(correct / total_q * 100)
            duration   = random.randint(30, 600)
            xp         = correct * random.randint(2, 8)
            played_ago = random.randint(0, min(user_days, SEED_DAYS))
            started    = days_ago(played_ago)

            gs = GameSession(
                user_id=u.id,
                game_type=random.choice(GAME_TYPES),
                score=score,
                total_questions=total_q,
                correct_answers=correct,
                xp_earned=xp,
                cefr_level=level,
                category=random.choice(categories),
                duration_seconds=duration,
                started_at=started,
                completed_at=started + timedelta(seconds=duration),
                xp_awarded=True,
            )
            batch.append(gs)

        if len(batch) >= 300:
            db.add_all(batch)
            await db.flush()
            batch.clear()

    if batch:
        db.add_all(batch)

    await db.commit()
    total = await db.scalar(select(func.count(GameSession.id))) or 0
    print(f"   {total} game session records\n")


# ─────────────────────────────────────────────
# 10. Leaderboard entries (current week + 3 past weeks)
# ─────────────────────────────────────────────

async def seed_leaderboard(
    db: AsyncSession,
    users: list[User],
) -> None:
    """One leaderboard entry per user for the current week + 3 prior weeks."""
    print(" Seeding leaderboard entries…")

    user_ids = [u.id for u in users]
    existing = await db.scalar(
        select(func.count(LeaderboardEntry.id))
        .where(LeaderboardEntry.user_id.in_(user_ids))
    ) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} leaderboard entries already exist for these users — skipping\n")
        return

    LEAGUES = ["bronze", "silver", "gold", "platinum", "diamond"]
    batch: list[LeaderboardEntry] = []

    # Seed 4 weeks (current + 3 prior)
    for week_offset in range(4):
        # Monday of the week
        week_end   = TODAY - timedelta(days=TODAY.weekday()) - timedelta(weeks=week_offset)
        week_start = week_end - timedelta(days=7)

        # Sort users by XP desc to determine ranks
        ranked_users = sorted(users, key=lambda u: getattr(u, "total_xp", 0), reverse=True)

        for rank_pos, u in enumerate(ranked_users, start=1):
            user_xp   = getattr(u, "total_xp", 0)
            level     = getattr(u, "level", "A1")
            league    = RANKS.get(level, "bronze")
            xp_week   = random.randint(20, min(user_xp // 4 + 50, 800))
            lessons_w = random.randint(0, 10)

            e = LeaderboardEntry(
                user_id=u.id,
                week_start=datetime.combine(week_start, datetime.min.time()).replace(tzinfo=timezone.utc),
                week_end=datetime.combine(week_end, datetime.min.time()).replace(tzinfo=timezone.utc),
                league=league,
                xp_earned=xp_week,
                lessons_completed=lessons_w,
                current_rank=rank_pos,
                is_promoted=random.random() < 0.10,
                is_demoted=random.random() < 0.05,
            )
            batch.append(e)

        if len(batch) >= 300:
            db.add_all(batch)
            await db.flush()
            batch.clear()

    if batch:
        db.add_all(batch)

    await db.commit()
    total = await db.scalar(select(func.count(LeaderboardEntry.id))) or 0
    print(f"   {total} leaderboard entries (4 weeks)\n")


# ─────────────────────────────────────────────
# 11. User vocabulary (SRS data)
# ─────────────────────────────────────────────

async def seed_user_vocabulary(
    db: AsyncSession,
    users: list[User],
    vocab_items: list[VocabularyItem],
) -> None:
    """Give ~30 % of users some vocabulary learning records for the vocab chart."""
    print(" Seeding user vocabulary records…")

    user_ids = [u.id for u in users]
    existing = await db.scalar(
        select(func.count(UserVocabulary.id))
        .where(UserVocabulary.user_id.in_(user_ids))
    ) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} user_vocabulary records already exist for these users — skipping\n")
        return

    if not vocab_items:
        print("  ️  No vocab items found — skipping\n")
        return

    STATUSES = ["learning", "reviewing", "mastered", "archived"]
    STATUS_WEIGHTS = [35, 30, 25, 10]
    batch: list[UserVocabulary] = []
    count = 0

    for u in users:
        if random.random() > 0.35:  # 35 % of users have vocab records
            continue

        n_words = random.randint(8, 40)
        chosen  = random.sample(vocab_items, min(n_words, len(vocab_items)))

        for vocab in chosen:
            status = random.choices(STATUSES, weights=STATUS_WEIGHTS, k=1)[0]
            total_reviews = random.randint(1, 20)
            correct_rev   = random.randint(0, total_reviews)
            streak        = random.randint(0, 7)

            uv = UserVocabulary(
                user_id=u.id,
                vocabulary_id=vocab.id,
                status=status,
                ease_factor=round(random.uniform(1.3, 3.0), 2),
                interval=random.randint(1, 60),
                repetitions=total_reviews,
                total_reviews=total_reviews,
                correct_reviews=correct_rev,
                streak=streak,
                longest_streak=max(streak, random.randint(0, 10)),
                total_xp_earned=correct_rev * 5,
            )
            batch.append(uv)
            count += 1

        if len(batch) >= 300:
            db.add_all(batch)
            await db.flush()
            batch.clear()

    if batch:
        db.add_all(batch)

    await db.commit()
    print(f"   {count} user vocabulary records\n")


# ─────────────────────────────────────────────
# 12. User achievements (earned badges)
# ─────────────────────────────────────────────

async def seed_user_achievements(
    db: AsyncSession,
    users: list[User],
    achievements: list[Achievement],
) -> None:
    """Award 1-5 random achievements to each user."""
    print(" Seeding user achievements…")

    user_ids = [u.id for u in users]
    existing = await db.scalar(
        select(func.count(UserAchievement.id))
        .where(UserAchievement.user_id.in_(user_ids))
    ) or 0
    if existing > 0:
        print(f"  ⏭️  {existing} user_achievement records already exist for these users — skipping\n")
        return

    if not achievements:
        print("  ️  No achievements found — skipping\n")
        return

    batch: list[UserAchievement] = []
    count = 0
    seen: set[tuple] = set()

    for u in users:
        n  = random.randint(1, min(5, len(achievements)))
        chosen = random.sample(achievements, n)
        user_days = max((TODAY - u.created_at.date()).days, 1)  # type: ignore[attr-defined]

        for ach in chosen:
            key = (u.id, ach.id)
            if key in seen:
                continue
            seen.add(key)

            ua = UserAchievement(
                user_id=u.id,
                achievement_id=ach.id,
                progress=100,
                is_showcased=random.random() < 0.3,
                unlocked_at=days_ago(random.randint(0, min(user_days, SEED_DAYS))),
            )
            batch.append(ua)
            count += 1

    db.add_all(batch)
    await db.commit()
    print(f"   {count} user achievement records\n")


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

async def main() -> None:
    print("=" * 65)
    print("LexiLingo — Analytics Data Seeding")
    print("=" * 65)
    print()

    async with AsyncSessionLocal() as db:
        try:
            print(" Cleaning up old test users…")
            await cleanup_test_users(db)
            refs       = await ensure_base_data(db)
            users      = await seed_users(db, refs["roles"])
            await seed_enrollments(db, users, refs["courses"])
            await seed_lesson_completions(db, users, refs["courses"])
            await seed_daily_activities(db, users)
            await seed_streaks(db, users)
            await seed_wallets(db, users)
            await seed_xp_transactions(db, users)
            await seed_game_sessions(db, users)
            await seed_leaderboard(db, users)
            await seed_user_vocabulary(db, users, refs["vocab_items"])
            await seed_user_achievements(db, users, refs["achievements"])

            # ── Final summary ─────────────────────────────────────
            async def cnt(model):
                return await db.scalar(select(func.count(model.id))) or 0

            print("=" * 65)
            print(" Analytics Database Summary:")
            print(f"  Users                  : {await cnt(User)}")
            print(f"  Course enrollments     : {await cnt(UserCourseProgress)}")
            print(f"  Lesson completions     : {await cnt(LessonCompletion)}")
            print(f"  Daily activity records : {await cnt(DailyActivity)}")
            print(f"  Streaks                : {await cnt(Streak)}")
            print(f"  User wallets           : {await cnt(UserWallet)}")
            print(f"  XP transactions        : {await cnt(XPTransaction)}")
            print(f"  Game sessions          : {await cnt(GameSession)}")
            print(f"  Leaderboard entries    : {await cnt(LeaderboardEntry)}")
            print(f"  User vocabulary        : {await cnt(UserVocabulary)}")
            print(f"  User achievements      : {await cnt(UserAchievement)}")
            print()
            print("  Admin charts now have data for:")
            print("    User growth (90-day trend)")
            print("    DAU / WAU / MAU engagement")
            print("    Course popularity (top 6)")
            print("    Completion funnel")
            print("    Vocabulary effectiveness")
            print("    Leaderboard")
            print("=" * 65)

        except Exception as exc:
            import traceback
            print(f"\n Error: {exc}")
            traceback.print_exc()
            await db.rollback()
            raise


if __name__ == "__main__":
    asyncio.run(main())
