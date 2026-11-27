"""Believable sample data for the admin pages that have no seed of their own.

    python -m scripts.seed_courses_directly   # content first
    python -m scripts.seed_ielts_test         # optional: gives IELTS attempts a paper
    python -m scripts.seed_admin_mock

Sandbox databases only (see seed_guard). Re-running replaces the rows this
script made, and nothing else, so counts stay stable and dates stay current.
Totals agree with each other the way the app keeps them: XP, daily activity,
streaks, weekly leaderboard, course progress and wallet balances are derived
from the same events. System health, backups and AI key state are never faked,
and agent jobs are only seeded as finished, so no worker picks them up.
"""
from __future__ import annotations

import asyncio
import json
import random
import sys
import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import bcrypt
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.banner import Banner
from app.models.content_agent import ContentAgentJob
from app.models.course import Course, Lesson, Unit
from app.models.entitlement import UserEntitlement
from app.models.games import XPTransaction
from app.models.gamification import (
    Achievement, LeaderboardEntry, UserAchievement, UserWallet, WalletTransaction,
)
from app.models.ielts import IeltsAttempt, IeltsTest
from app.models.notification_campaign import NotificationCampaignJob
from app.models.product_event import ProductEvent
from app.models.progress import (
    DailyActivity, LessonAttempt, LessonCompletion, Streak, UserCourseProgress,
)
from app.models.ranking_agent import RankingAgentJob
from app.models.rbac import AuditLog, Role
from app.models.reminder import ReminderDelivery
from app.models.app_setting import AdminGemGrant
from app.models.user import User
from app.models.vocabulary import DifficultyLevel, PartOfSpeech, UserVocabulary, VocabularyItem
from app.services.level_service import calculate_numeric_level
from scripts.seed_guard import check_redis, require_sandbox

# Not in SEED_EMAIL_DOMAINS, so activation and retention count these learners;
# example.com is reserved, so no mail can ever reach them.
MOCK_DOMAIN = "mock.example.com"
_NS = uuid.UUID("6f0c8f0e-2c55-4f0a-9d53-6d9d3a1f7b21")
LEARNERS = 160
WINDOW_DAYS = 90
DAILY_GOAL_XP = 20
AUDIT_KEY = "ai:audit:all"
_AUDIT_MARK = "mock-seed"

_FAMILY = ["Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Phan", "Vũ", "Đặng", "Bùi", "Đỗ", "Hồ", "Ngô"]
_GIVEN = ["Minh Anh", "Gia Bảo", "Khánh Chi", "Quốc Đạt", "Thu Hà", "Đức Huy", "Ngọc Lan", "Tuấn Kiệt",
          "Phương Linh", "Hải Nam", "Bảo Ngọc", "Thanh Phong", "Mai Phương", "Anh Quân", "Diễm Quỳnh",
          "Hoàng Sơn", "Thùy Trang", "Minh Trí", "Cẩm Tú", "Quang Vinh", "Hà Vy", "Xuân Yến"]
_WORDS = [
    ("achieve", PartOfSpeech.VERB, "to reach a goal"), ("benefit", PartOfSpeech.NOUN, "a good effect"),
    ("consider", PartOfSpeech.VERB, "to think about carefully"), ("decline", PartOfSpeech.VERB, "to become smaller"),
    ("efficient", PartOfSpeech.ADJECTIVE, "working without waste"), ("factor", PartOfSpeech.NOUN, "one cause of a result"),
    ("generate", PartOfSpeech.VERB, "to produce"), ("habit", PartOfSpeech.NOUN, "something done regularly"),
    ("improve", PartOfSpeech.VERB, "to make better"), ("journey", PartOfSpeech.NOUN, "travel between places"),
    ("knowledge", PartOfSpeech.NOUN, "what someone knows"), ("likely", PartOfSpeech.ADJECTIVE, "expected to happen"),
    ("maintain", PartOfSpeech.VERB, "to keep in good condition"), ("notice", PartOfSpeech.VERB, "to become aware of"),
    ("obtain", PartOfSpeech.VERB, "to get"), ("purpose", PartOfSpeech.NOUN, "the reason for something"),
    ("quickly", PartOfSpeech.ADVERB, "at high speed"), ("require", PartOfSpeech.VERB, "to need"),
    ("significant", PartOfSpeech.ADJECTIVE, "important or large"), ("tradition", PartOfSpeech.NOUN, "a long-held custom"),
]


def _id(*parts: object) -> uuid.UUID:
    return uuid.uuid5(_NS, ":".join(str(p) for p in parts))


def _at(day: date, rng: random.Random, now: datetime) -> datetime:
    """A time on that day, evenings busiest, never in the future."""
    hour = rng.choices(range(24), weights=[1, 1, 1, 1, 1, 2, 4, 6, 5, 4, 4, 5, 7, 5, 4, 4, 5, 6, 8, 11, 13, 12, 8, 3])[0]
    moment = datetime.combine(day, time(hour, rng.randrange(60), rng.randrange(60)), tzinfo=timezone.utc)
    return min(moment, now - timedelta(minutes=rng.randrange(1, 30)))


def _signup_day(today: date, rng: random.Random) -> date:
    # Growth: recent days draw more signups; weekends draw more than midweek.
    days = [today - timedelta(days=n) for n in range(WINDOW_DAYS)]
    weights = [(1.0 + (WINDOW_DAYS - n) / 30) * (1.35 if d.weekday() >= 5 else 1.0) for n, d in enumerate(days)]
    return rng.choices(days, weights=weights)[0]


async def _clear_own_rows(db: AsyncSession) -> None:
    # Learner-owned rows go with the learners (ON DELETE CASCADE).
    await db.execute(delete(User).where(User.email.like(f"%@{MOCK_DOMAIN}")))
    for model, kind, count in (
        (AdminGemGrant, "grant", 40), (AuditLog, "audit", 80), (Banner, "banner", 5),
        (RankingAgentJob, "ranking", 6), (NotificationCampaignJob, "campaign", 6), (ContentAgentJob, "content", 8),
    ):
        await db.execute(delete(model).where(model.id.in_([_id(kind, n) for n in range(count)])))
    await db.flush()


async def _vocabulary(db: AsyncSession) -> list[uuid.UUID]:
    ids = list((await db.execute(select(VocabularyItem.id).limit(60))).scalars())
    if len(ids) >= len(_WORDS):
        return ids
    for word, part, definition in _WORDS:
        found = await db.scalar(
            select(VocabularyItem.id).where(VocabularyItem.word == word, VocabularyItem.part_of_speech == part)
        )
        if found is None:
            found = _id("word", word)
            db.add(VocabularyItem(id=found, word=word, definition=definition, part_of_speech=part,
                                  difficulty_level=DifficultyLevel.B1))
        ids.append(found)
    await db.flush()
    return list(dict.fromkeys(ids))


async def _catalogue(db: AsyncSession) -> list[tuple[Course, list[Lesson]]]:
    courses = (await db.execute(select(Course).where(Course.is_published.is_(True)).order_by(Course.title))).scalars().all()
    result = []
    for course in courses:
        lessons = (await db.execute(
            select(Lesson).join(Unit, Lesson.unit_id == Unit.id)
            .where(Lesson.course_id == course.id).order_by(Unit.order_index, Lesson.order_index)
        )).scalars().all()
        if lessons:
            result.append((course, list(lessons)))
    if not result:
        raise SystemExit("No published course with lessons. Run: python -m scripts.seed_courses_directly")
    return result


def _streak(days: list[date], today: date) -> tuple[int, int]:
    longest = run = 0
    previous: date | None = None
    for day in days:
        run = run + 1 if previous and day - previous == timedelta(days=1) else 1
        longest, previous = max(longest, run), day
    alive = previous is not None and today - previous <= timedelta(days=1)
    return (run if alive else 0), longest


async def _learner(
    db: AsyncSession, n: int, rng: random.Random, now: datetime, password_hash: str, role_id: uuid.UUID | None,
    catalogue: list[tuple[Course, list[Lesson]]], words: list[uuid.UUID], achievements: list[Achievement],
) -> User:
    today = now.date()
    joined = _signup_day(today, rng)
    joined_at = _at(joined, rng, now)
    verified = rng.random() < 0.81
    onboarded = verified and rng.random() < 0.86
    enrolled = onboarded and rng.random() < 0.83
    started = enrolled and rng.random() < 0.90
    finisher = started and rng.random() < 0.84
    commitment = rng.betavariate(1.6, 3.2)  # most learners are casual, a few are daily
    name = f"{rng.choice(_FAMILY)} {rng.choice(_GIVEN)}"
    user = User(
        id=_id("user", n), email=f"learner{n:03d}@{MOCK_DOMAIN}", username=f"mock_learner_{n:03d}",
        display_name=name, hashed_password=password_hash, role_id=role_id,
        level=rng.choices(["A1", "A2", "B1", "B2", "C1"], weights=[34, 29, 22, 11, 4])[0],
        is_verified=verified, is_onboarding_completed=onboarded, is_active=rng.random() < 0.97,
        provider=["google"] if verified and rng.random() < 0.55 else ["local"],
        created_at=joined_at, updated_at=joined_at, last_login=joined_at,
    )
    db.add(user)
    await db.flush()

    # Days this learner came back: likelier for the committed, fading with age.
    active = [joined]
    for offset in range(1, (today - joined).days + 1):
        day = joined + timedelta(days=offset)
        chance = commitment * (0.35 + 0.65 * 0.965 ** offset) * (1.15 if day.weekday() < 5 else 0.85)
        if rng.random() < chance:
            active.append(day)
    if not onboarded:
        active = active[:1]

    xp_by_day: dict[date, int] = defaultdict(int)
    lessons_by_day: dict[date, int] = defaultdict(int)
    if enrolled:
        course, lessons = rng.choices(catalogue, weights=[len(catalogue) - i for i in range(len(catalogue))])[0]
        passed = 0
        earned = 0
        if started:
            queue = list(lessons)
            for day in active:
                if not queue:
                    break
                lesson = queue[0]
                score = rng.randint(max(lesson.pass_threshold or 80, 80), 100) if finisher and rng.random() < 0.86 \
                    else rng.randint(35, 74)
                ok = score >= (lesson.pass_threshold or 80)
                moment = _at(day, rng, now)
                total = 10
                db.add(LessonAttempt(
                    id=_id("attempt", n, day, lesson.id), user_id=user.id, lesson_id=lesson.id,
                    started_at=moment - timedelta(minutes=rng.randint(3, 14)), finished_at=moment, score=score,
                    passed=ok, xp_earned=(lesson.xp_reward or 0) if ok else 0, total_questions=total,
                    correct_answers=round(total * score / 100), device_type=rng.choice(["web", "android", "ios"]),
                    time_spent_ms=rng.randint(180_000, 840_000),
                ))
                if not ok:
                    continue
                queue.pop(0)
                passed += 1
                xp = lesson.xp_reward or 0
                earned += xp
                xp_by_day[day] += xp
                lessons_by_day[day] += 1
                db.add(LessonCompletion(id=_id("completion", n, lesson.id), user_id=user.id, lesson_id=lesson.id,
                                        is_passed=True, best_score=score, completed_at=moment))
                db.add(XPTransaction(id=_id("xp", n, lesson.id), user_id=user.id, amount=xp, base_amount=xp,
                                     multiplier=1.0, source="lesson", source_id=str(lesson.id), created_at=moment))
        db.add(UserCourseProgress(
            id=_id("progress", n, course.id), user_id=user.id, course_id=course.id, lessons_completed=passed,
            progress_percentage=round(passed / len(lessons) * 100, 1), total_xp_earned=earned,
            started_at=joined_at, last_activity_at=_at(active[-1], rng, now),
        ))

    # Short practice on the other active days, so activity is not lessons only.
    if onboarded:
        for day in active:
            if rng.random() < 0.45:
                source, detail = rng.choice([("game", "word_scramble"), ("game", "matching"), ("news", None),
                                             ("daily_challenge", None)])
                xp = rng.choice([5, 8, 10, 15, 20])
                xp_by_day[day] += xp
                db.add(XPTransaction(id=_id("practice", n, day), user_id=user.id, amount=xp, base_amount=xp,
                                     multiplier=1.0, source=source, source_id=f"mock:{n}:{day}",
                                     source_detail=detail, created_at=_at(day, rng, now)))

    for day in active:
        xp = xp_by_day[day]
        reviewed = rng.randint(0, 14) if onboarded else 0
        db.add(DailyActivity(
            id=_id("day", n, day), user_id=user.id, activity_date=day, xp_earned=xp,
            lessons_completed=lessons_by_day[day], vocabulary_reviewed=reviewed,
            study_time_minutes=lessons_by_day[day] * rng.randint(4, 11) + reviewed // 2 + rng.randint(1, 6),
            daily_goal_xp=DAILY_GOAL_XP, daily_goal_met=xp >= DAILY_GOAL_XP,
        ))

    user.total_xp = sum(xp_by_day.values())
    user.numeric_level = calculate_numeric_level(user.total_xp)
    user.last_login = _at(active[-1], rng, now)
    current, longest = _streak(active, today)
    db.add(Streak(id=_id("streak", n), user_id=user.id, current_streak=current, longest_streak=longest,
                  total_days_active=len(active), last_activity_date=active[-1]))

    weeks: dict[date, list[int]] = defaultdict(lambda: [0, 0])
    for day in active:
        week = day - timedelta(days=day.weekday())
        weeks[week][0] += xp_by_day[day]
        weeks[week][1] += lessons_by_day[day]
    for week, (xp, count) in weeks.items():
        if xp:
            start = datetime.combine(week, time.min, tzinfo=timezone.utc)
            db.add(LeaderboardEntry(id=_id("week", n, week), user_id=user.id, week_start=start,
                                    week_end=start + timedelta(days=7), xp_earned=xp, lessons_completed=count,
                                    league=rng.choices(["bronze", "silver", "gold"], weights=[70, 22, 8])[0]))

    if onboarded:
        for index, word in enumerate(rng.sample(words, k=min(len(words), rng.randint(2, 14)))):
            reviews = rng.randint(0, 12)
            correct = rng.randint(reviews // 2, reviews)
            status = "mastered" if reviews >= 8 and correct >= reviews - 1 else "reviewing" if reviews >= 3 else "learning"
            db.add(UserVocabulary(id=_id("saved", n, index), user_id=user.id, vocabulary_id=word, status=status,
                                  total_reviews=reviews, correct_reviews=correct, added_at=joined_at,
                                  next_review_date=now + timedelta(days=rng.randint(-3, 21))))

    done = sum(lessons_by_day.values())
    for achievement in achievements:
        if done and achievement.condition_type == "lessons_completed" and done >= achievement.condition_value:
            db.add(UserAchievement(id=_id("badge", n, achievement.id), user_id=user.id,
                                   achievement_id=achievement.id, progress=achievement.condition_value,
                                   unlocked_at=_at(active[-1], rng, now)))

    # A wallet whose balance is the sum of its ledger.
    wallet_id = _id("wallet", n)
    balance = earned_gems = spent = 0
    ledger = [("reward", 100, "starter_reward", joined)]
    ledger += [("earn", 5, "lesson_complete", d) for d in active if lessons_by_day[d]]
    for day in active[3::6]:
        ledger.append(("spend", -rng.choice([20, 30, 50]), "shop_purchase", day))
    rows = []
    for index, (kind, amount, source, day) in enumerate(sorted(ledger, key=lambda row: row[3])):
        if balance + amount < 0:
            continue
        balance += amount
        earned_gems += max(amount, 0)
        spent += max(-amount, 0)
        stamp = datetime.combine(day, time(12), tzinfo=timezone.utc) + timedelta(seconds=index)
        rows.append(WalletTransaction(id=_id("gem", n, index), wallet_id=wallet_id, user_id=user.id,
                                      transaction_type=kind, amount=amount, balance_after=balance, source=source,
                                      created_at=min(stamp, now)))
    db.add(UserWallet(id=wallet_id, user_id=user.id, gems=balance, total_gems_earned=earned_gems,
                      total_gems_spent=spent))
    await db.flush()
    db.add_all(rows)

    names = ["app_opened", "lesson_started", "lesson_completed", "paywall_viewed", "content_interaction", "quiz_submitted"]
    for day in [d for d in active if (today - d).days <= 30]:
        for index in range(rng.randint(1, 5)):
            moment = _at(day, rng, now)
            db.add(ProductEvent(id=_id("event", n, day, index), event_id=_id("event-id", n, day, index),
                                user_id=user.id, event_name=rng.choices(names, weights=[40, 24, 18, 6, 8, 4])[0],
                                properties={}, source=rng.choice(["web", "android"]), client_timestamp=moment,
                                created_at=moment))

    if onboarded:
        for back in range(14):
            if rng.random() < 0.12:
                day = today - timedelta(days=back)
                when = _at(day, rng, now)
                outcome = rng.choices(["sent", "skipped", "failed", "dry_run"], weights=[76, 14, 4, 6])[0]
                db.add(ReminderDelivery(
                    id=_id("reminder", n, day), user_id=user.id, channel=rng.choice(["push", "email"]),
                    status=outcome, due_count=rng.randint(3, 25), dedupe_key=f"mock:{n}:{day}", scheduled_for=when,
                    sent_at=when if outcome == "sent" else None, created_at=when,
                    error="device token expired" if outcome == "failed" else None,
                ))
    return user


async def _admin_rows(db: AsyncSession, rng: random.Random, now: datetime, learners: list[User]) -> None:
    staff = await db.scalar(
        select(User.id).join(Role, User.role_id == Role.id).where(Role.level >= 1).order_by(User.created_at)
    )

    def ago(days: float) -> datetime:
        return now - timedelta(days=days)

    for n in range(24):
        gift = rng.random() < 0.75
        db.add(AdminGemGrant(
            id=_id("grant", n), actor_id=staff, user_id=rng.choice(learners).id, kind="gift" if gift else "adjust",
            amount=rng.choice([20, 50, 100]) if gift else rng.choice([-30, 40]),
            reason=rng.choice(["Event reward", "Bug report thank-you", "Lost streak compensation", "Support ticket"]),
            created_at=ago(rng.uniform(0, 30)),
        ))

    actions = [("create", "courses"), ("update", "lessons"), ("update", "shop"), ("create", "banners"),
               ("update", "users"), ("delete", "vocabulary"), ("assign_role", "users"), ("update", "achievements")]
    for n in range(60):
        action, resource = rng.choice(actions)
        db.add(AuditLog(id=_id("audit", n), user_id=staff, action=action, resource_type=resource,
                        resource_id=str(_id("audited", n)), details=json.dumps({"sample": True}),
                        ip_address="203.0.113.10", user_agent="mock-seed", created_at=ago(rng.uniform(0, 28))))

    # Only "hero" is rendered by the app today.
    banners = [("Back-to-school: 7-day streak challenge", "hero", True), ("IELTS Reading practice is here", "hero", True),
               ("Invite a friend, earn gems", "hero", True), ("Premium: half price this week", "hero", False)]
    for n, (title, position, active) in enumerate(banners):
        db.add(Banner(id=_id("banner", n), title=title, description="Sample campaign", position=position,
                      image_url=f"https://picsum.photos/seed/lexi-{n}/1200/400", priority=10 - n, is_active=active,
                      start_at=ago(10 - n), end_at=now + timedelta(days=20 + n), created_by_id=staff,
                      created_at=ago(12 - n)))

    outcomes = ["completed", "completed", "completed", "failed", "cancelled"]
    for kind, model, types in (
        ("ranking", RankingAgentJob, ["league_reset", "xp_event", "achievement_batch"]),
        ("campaign", NotificationCampaignJob, ["targeted_push", "in_app_broadcast", "scheduled_push"]),
    ):
        for n in range(5):
            outcome = outcomes[n]
            created = ago(3 + n * 6)
            job_type = types[n % len(types)]
            # Only a finished campaign has delivered anything.
            sent = 120 - n * 7 if outcome == "completed" else 0
            stats = {"sent": sent, "failed": n if sent else 0, "skipped": 4 if sent else 0,
                     "total": sent + n + 4 if sent else 0}
            extra = {"delivery_stats": stats} if kind == "campaign" else {"created_entity_ids": {}}
            db.add(model(
                id=_id(kind, n), requested_by_id=staff, job_type=job_type, status=outcome,
                config={"job_type": job_type}, warnings=[], blocking_errors=[],
                progress={"stage": outcome, "percent": 100 if outcome == "completed" else 40, "counters": {}},
                error_message="Sample failure: segment was empty" if outcome == "failed" else None,
                created_at=created, updated_at=created + timedelta(minutes=4), started_at=created,
                completed_at=created + timedelta(minutes=4), **extra,
            ))

    # No "completed" here: a real one carries a preview artifact the QA page opens.
    for n, outcome in enumerate(["failed", "cancelled", "failed", "cancelled", "failed", "cancelled"]):
        created = ago(2 + n * 4)
        db.add(ContentAgentJob(
            id=_id("content", n), requested_by_id=staff, status=outcome, request_hash=f"mock-{n:02d}", revision=1,
            config={"title": f"Sample course draft {n + 1}", "level": ["A2", "B1", "B2"][n % 3]},
            progress={"stage": outcome, "percent": 55}, source_manifest=[],
            warnings=[], blocking_errors=[], created_entity_ids={},
            error_message="Sample failure: provider rate limit" if outcome == "failed" else None,
            created_at=created, updated_at=created + timedelta(minutes=9), started_at=created,
            completed_at=created + timedelta(minutes=9),
        ))

    papers = list((await db.execute(select(IeltsTest.id))).scalars())
    if papers:
        for n, learner in enumerate(rng.sample(learners, 28)):
            sat = ago(rng.uniform(0.1, 45))
            done = n % 5 != 0
            bands = {k: rng.choice([5.0, 5.5, 6.0, 6.5, 7.0, 7.5]) for k in ("listening_band", "reading_band")}
            db.add(IeltsAttempt(
                id=_id("ielts", n), user_id=learner.id, test_id=papers[n % len(papers)],
                status="submitted" if done else "in_progress", skill_scope="full", started_at=sat,
                submitted_at=sat + timedelta(minutes=rng.randint(90, 165)) if done else None,
                time_spent_seconds=rng.randint(3600, 9600) if done else rng.randint(300, 2400),
                **(bands if done else {}),
            ))

    for n, learner in enumerate(rng.sample(learners, 14)):
        lapsed = n % 4 == 0
        db.add(UserEntitlement(
            id=_id("premium", n), user_id=learner.id, entitlement_id="premium",
            product_id=rng.choice(["premium_monthly", "premium_yearly"]), status="expired" if lapsed else "active",
            expires_at=ago(rng.uniform(1, 20)) if lapsed else now + timedelta(days=rng.randint(3, 340)),
            source="revenuecat", synced_at=ago(rng.uniform(0, 3)),
        ))


async def seed(db: AsyncSession, now: datetime | None = None) -> int:
    """Replace the mock rows inside the caller's transaction; returns learners made."""
    await require_sandbox(db)
    now = now or datetime.now(timezone.utc)
    rng = random.Random(20261126)
    await _clear_own_rows(db)
    catalogue = await _catalogue(db)
    words = await _vocabulary(db)
    achievements = list((await db.execute(select(Achievement).order_by(Achievement.name))).scalars())
    role_id = await db.scalar(select(Role.id).where(Role.slug == "user"))
    # Nobody can sign in as these: the password is random and thrown away.
    password_hash = bcrypt.hashpw(uuid.uuid4().hex.encode(), bcrypt.gensalt(4)).decode()
    learners = [
        await _learner(db, n, rng, now, password_hash, role_id, catalogue, words, achievements)
        for n in range(LEARNERS)
    ]
    await _admin_rows(db, rng, now, learners)
    await db.flush()
    return len(learners)


def ai_audit_events(now: datetime, count: int = 600) -> list[str]:
    rng = random.Random(7)
    endpoints = [("lexi.stream", 1400, 60), ("tts.synthesize", 280, 22), ("stt.transcribe", 2100, 8),
                 ("grammar.correction", 900, 7), ("topic.send_message", 780, 3)]
    events = []
    for n in range(count):
        endpoint, latency, _ = rng.choices(endpoints, weights=[w for *_, w in endpoints])[0]
        failed = rng.random() < 0.025
        event = {
            "request_id": f"{_AUDIT_MARK}-{n}", "endpoint": endpoint, "status": "error" if failed else "success",
            "latency_ms": round(rng.lognormvariate(0, 0.35) * latency), "user_id": str(_id("user", n % LEARNERS)),
            "received_at": (now - timedelta(minutes=n * 31)).isoformat(),
        }
        if failed:
            event["error"] = rng.choice(["upstream timeout", "rate limited by provider", "invalid model response"])
        if endpoint == "grammar.correction" and not failed:
            event["correction_score"] = round(rng.uniform(0.72, 0.98), 2)
        events.append(json.dumps(event))
    return events


async def seed_ai_audit(redis: object, now: datetime) -> int:
    """AI quality reads a Redis list. Only this script's own entries are replaced."""
    for row in await redis.lrange(AUDIT_KEY, 0, -1):
        if _AUDIT_MARK in (row.decode() if isinstance(row, bytes) else row):
            await redis.lrem(AUDIT_KEY, 0, row)
    events = ai_audit_events(now)
    await redis.rpush(AUDIT_KEY, *events)
    await redis.expire(AUDIT_KEY, 14 * 24 * 3600)
    return len(events)


async def main() -> None:
    from app.core.database import AsyncSessionLocal
    from app.core.redis import RedisClient

    async with AsyncSessionLocal() as db:
        count = await seed(db)
        await db.commit()
    print(f"Mock learners: {count} (@{MOCK_DOMAIN}) with 90 days of activity")
    check_redis()
    await RedisClient.connect()
    redis = await RedisClient.get_instance()
    if redis is None:
        print("Redis unavailable: AI quality events skipped")
    else:
        print(f"AI quality events: {await seed_ai_audit(redis, datetime.now(timezone.utc))}")
    await RedisClient.close()


if __name__ == "__main__":
    asyncio.run(main())
