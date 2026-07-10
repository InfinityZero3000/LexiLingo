"""
Seed Empty Tables + Crawl Course/Lesson Content
===============================================

What this script does:
- Checks public tables and detects which ones are empty
- Seeds baseline data for empty tables (idempotent-safe defaults)
- Crawls RSS feeds and creates many courses/lessons from crawled content

Usage:
    cd backend-service
    python -m scripts.seed_empty_tables_and_crawl

Optional flags:
    --target-courses 40        Target number of crawled courses to keep
    --lessons-per-course 8     Number of lessons per crawled course
    --max-feed-items 240       Max total RSS items to ingest
    --force                    Seed even when table is not empty
"""

from __future__ import annotations

import argparse
import json
import random
import re
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import feedparser
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

from app.core.database import AsyncSessionLocal
from app.models import (
    APICacheEntry,
    Achievement,
    ActivityFeed,
    AuditLog,
    ChallengeRewardClaim,
    Course,
    CourseCategory,
    DailyReviewSession,
    ExerciseAttempt,
    GameSession,
    GameWord,
    GrammarItem,
    LeaderboardEntry,
    Lesson,
    LessonAttempt,
    LessonCompletion,
    MediaResource,
    Notification,
    Permission,
    QuestionAttempt,
    QuestionItem,
    Role,
    RolePermission,
    ShopItem,
    Streak,
    TestExam,
    Unit,
    User,
    UserAchievement,
    UserCourseProgress,
    UserFollowing,
    UserInventory,
    UserProgress,
    UserVocabKnowledge,
    UserVocabulary,
    VocabularyDeck,
    VocabularyDeckItem,
    VocabularyItem,
    VocabularyReview,
    WalletTransaction,
)


NOW = datetime.now(timezone.utc)
TODAY = date.today()
random.seed(42)

RSS_SOURCES = [
    "https://feeds.bbci.co.uk/news/education/rss.xml",
    "https://feeds.bbci.co.uk/news/world/rss.xml",
    "https://www.nasa.gov/rss/dyn/breaking_news.rss",
    "https://rss.nytimes.com/services/xml/rss/nyt/World.xml",
    "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml",
    "https://www.theguardian.com/world/rss",
    "https://www.theguardian.com/uk/education/rss",
]

PERMISSION_MATRIX = {
    "courses": ["create", "read", "update", "delete", "manage"],
    "users": ["read", "update", "delete", "manage"],
    "analytics": ["read"],
    "achievements": ["create", "read", "update", "delete"],
    "rbac": ["manage"],
    "content": ["create", "read", "update", "delete"],
}


def strip_html(raw: str | None) -> str:
    if not raw:
        return ""
    clean = re.sub(r"<[^>]+>", " ", raw)
    clean = re.sub(r"\s+", " ", clean).strip()
    return clean


def guess_level(text_value: str, index: int) -> str:
    text_l = text_value.lower()
    if any(x in text_l for x in ["beginner", "basic", "easy", "starter"]):
        return "A1"
    if any(x in text_l for x in ["intermediate", "how to", "guide"]):
        return "A2"
    if any(x in text_l for x in ["advanced", "analysis", "policy", "editorial"]):
        return "B2"
    levels = ["A1", "A2", "B1", "B2", "C1"]
    return levels[index % len(levels)]


def slugify(text_value: str) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", text_value.lower()).strip("-")
    return base[:90] or "item"


def split_words(text_value: str, limit: int = 8) -> list[str]:
    words = [w for w in re.findall(r"[A-Za-z][A-Za-z\-']+", text_value)]
    return words[:limit]


async def count_rows(db: AsyncSession, table_name: str) -> int:
    return int((await db.execute(text(f'SELECT COUNT(*) FROM "{table_name}"'))).scalar() or 0)


async def empty_tables(db: AsyncSession) -> list[str]:
    tables = [
        row[0]
        for row in (
            await db.execute(
                text(
                    """
                    SELECT tablename
                    FROM pg_tables
                    WHERE schemaname='public'
                    ORDER BY tablename
                    """
                )
            )
        ).all()
    ]
    result: list[str] = []
    for table_name in tables:
        if await count_rows(db, table_name) == 0:
            result.append(table_name)
    return result


async def ensure_categories(db: AsyncSession) -> list[CourseCategory]:
    existing = (await db.execute(select(CourseCategory))).scalars().all()
    if existing:
        return existing

    defaults = [
        ("Grammar", "grammar", "Grammar rules and usage"),
        ("Vocabulary", "vocabulary", "Vocabulary building and retention"),
        ("Business English", "business-english", "English for work and business"),
        ("Conversation", "conversation", "Everyday spoken English"),
        ("Travel English", "travel-english", "Travel and real-life communication"),
        ("Pronunciation", "pronunciation", "Pronunciation and speaking clarity"),
        ("Test Preparation", "test-preparation", "Exam and assessment readiness"),
        ("Cultural English", "cultural-english", "Culture, idioms, and context"),
    ]
    for idx, (name, slug, desc) in enumerate(defaults):
        db.add(
            CourseCategory(
                name=name,
                slug=slug,
                description=desc,
                order_index=idx,
                is_active=True,
                course_count=0,
            )
        )
    await db.flush()
    return (await db.execute(select(CourseCategory).order_by(CourseCategory.order_index))).scalars().all()


def crawl_articles(max_items: int) -> list[dict]:
    items: list[dict] = []
    for source in RSS_SOURCES:
        feed = feedparser.parse(source)
        for e in feed.entries[:80]:
            title = strip_html(getattr(e, "title", ""))
            summary = strip_html(getattr(e, "summary", ""))
            link = getattr(e, "link", "")
            if not title or not link:
                continue
            items.append(
                {
                    "title": title,
                    "summary": summary[:900],
                    "url": link,
                }
            )
            if len(items) >= max_items:
                return items
    return items


def synthetic_articles(max_items: int) -> list[dict]:
    topics = [
        "Daily Conversation",
        "Travel Situations",
        "Workplace Communication",
        "Technology News",
        "Study and University",
        "Food and Lifestyle",
        "Health and Habits",
        "Culture and Society",
        "Environment and Climate",
        "Business and Economy",
    ]
    out: list[dict] = []
    for i in range(max_items):
        topic = topics[i % len(topics)]
        out.append(
            {
                "title": f"{topic} Lesson Topic {i + 1}",
                "summary": (
                    f"This lesson explores {topic.lower()} with practical vocabulary, "
                    "listening prompts, and speaking tasks for English learners."
                ),
                "url": f"https://lexilingo.local/crawled/{i + 1}",
            }
        )
    return out


async def seed_permissions_and_mapping(db: AsyncSession, should_seed: bool) -> None:
    if not should_seed:
        return
    roles = {r.slug: r for r in (await db.execute(select(Role))).scalars().all()}
    if not roles:
        return

    perm_map: dict[str, Permission] = {}
    for resource, actions in PERMISSION_MATRIX.items():
        for action in actions:
            slug = f"{resource}:{action}"
            existing = await db.scalar(select(Permission).where(Permission.slug == slug))
            if existing:
                perm_map[slug] = existing
                continue
            p = Permission(
                name=f"{resource.title()} {action.title()}",
                slug=slug,
                resource=resource,
                action=action,
                description=f"Allows {action} on {resource}.",
            )
            db.add(p)
            await db.flush()
            perm_map[slug] = p

    # user role: read-only
    if "user" in roles:
        for slug in ["courses:read", "content:read"]:
            perm = perm_map.get(slug)
            if not perm:
                continue
            exists = await db.scalar(
                select(RolePermission).where(
                    RolePermission.role_id == roles["user"].id,
                    RolePermission.permission_id == perm.id,
                )
            )
            if not exists:
                db.add(RolePermission(role_id=roles["user"].id, permission_id=perm.id))

    # admin role: no delete on users
    if "admin" in roles:
        for slug, perm in perm_map.items():
            if slug == "users:delete":
                continue
            exists = await db.scalar(
                select(RolePermission).where(
                    RolePermission.role_id == roles["admin"].id,
                    RolePermission.permission_id == perm.id,
                )
            )
            if not exists:
                db.add(RolePermission(role_id=roles["admin"].id, permission_id=perm.id))

    # super_admin: all permissions
    if "super_admin" in roles:
        for perm in perm_map.values():
            exists = await db.scalar(
                select(RolePermission).where(
                    RolePermission.role_id == roles["super_admin"].id,
                    RolePermission.permission_id == perm.id,
                )
            )
            if not exists:
                db.add(RolePermission(role_id=roles["super_admin"].id, permission_id=perm.id))


async def seed_crawled_courses(
    db: AsyncSession,
    categories: list[CourseCategory],
    target_courses: int,
    lessons_per_course: int,
    max_feed_items: int,
) -> dict:
    from sqlalchemy import cast
    from sqlalchemy.dialects.postgresql import JSONB
    all_courses = (await db.execute(select(Course))).scalars().all()
    crawled_courses = [
        c for c in all_courses
        if isinstance(c.tags, list) and "crawl" in c.tags
    ]

    to_add = max(0, target_courses - len(crawled_courses))
    if to_add <= 0:
        return {"courses_added": 0, "lessons_added": 0}

    articles = crawl_articles(max_feed_items)
    if len(articles) < to_add * lessons_per_course:
        articles.extend(
            synthetic_articles(to_add * lessons_per_course - len(articles))
        )

    course_added = 0
    lesson_added = 0
    article_idx = 0
    added_words = set()
    colors = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#14B8A6"]

    for i in range(to_add):
        category = categories[i % len(categories)] if categories else None
        title_seed = articles[article_idx]["title"] if article_idx < len(articles) else f"Topic {i+1}"
        course_title = title_seed[:100]

        existing = await db.scalar(select(Course).where(Course.title == course_title))
        if existing:
            continue

        level = guess_level(title_seed, i)
        course = Course(
            title=course_title,
            description="Auto-generated from crawled web articles for extensive lesson practice.",
            language="en",
            level=level,
            category_id=category.id if category else None,
            tags=["crawl", "reading", "listening", level.lower()],
            total_xp=0,
            estimated_duration=lessons_per_course * 12,
            total_lessons=lessons_per_course,
            content_version=1,
            is_published=True,
            thumbnail_url=None,
        )
        db.add(course)
        await db.flush()

        unit = Unit(
            course_id=course.id,
            title="Unit 1: Crawled Practice",
            description="Lessons generated from real web content.",
            order_index=1,
            background_color=colors[i % len(colors)],
            total_lessons=lessons_per_course,
        )
        db.add(unit)
        await db.flush()

        course_xp = 0
        for lesson_index in range(lessons_per_course):
            article = articles[article_idx % len(articles)]
            article_idx += 1

            summary = article["summary"] or "No summary available from source feed."
            lesson_title = f"Lesson {lesson_index + 1}: {article['title'][:90]}"
            focus_words = split_words(article["title"] + " " + summary, limit=8)
            xp_reward = random.randint(20, 45)
            course_xp += xp_reward

            content = {
                "source": "rss-crawl",
                "source_url": article["url"],
                "summary": summary,
                "reading_text": summary,
                "tasks": [
                    "Read the text and identify the main idea.",
                    "Extract five key vocabulary words.",
                    "Write three sentences using the new words.",
                    "Record a 60-second spoken summary.",
                ],
                "vocabulary_focus": focus_words,
                "comprehension_questions": [
                    "What is the article mainly about?",
                    "Which detail supports the main point?",
                    "What new word did you learn from this text?",
                ],
            }

            lesson = Lesson(
                course_id=course.id,
                unit_id=unit.id,
                title=lesson_title,
                description=summary[:240],
                order_index=lesson_index + 1,
                prerequisites=[],
                pass_threshold=75,
                content=content,
                content_version=1,
                estimated_minutes=random.randint(8, 15),
                xp_reward=xp_reward,
                total_exercises=6,
                lesson_type="lesson",
            )
            db.add(lesson)
            await db.flush()
            lesson_added += 1

            # Also seed vocab items from lesson title to scale vocabulary by lessons.
            for w in focus_words[:4]:
                w_lower = w.lower()
                if w_lower in added_words:
                    continue
                exists_vocab = await db.scalar(
                    select(VocabularyItem).where(
                        VocabularyItem.word.ilike(w),
                    )
                )
                if exists_vocab:
                    added_words.add(w_lower)
                    continue
                db.add(
                    VocabularyItem(
                        word=w,
                        definition=f"Seeded from crawled lesson context: {lesson_title[:120]}",
                        translation={"vi": "(auto)"},
                        pronunciation=None,
                        audio_url=None,
                        part_of_speech="noun",
                        difficulty_level=guess_level(lesson_title, lesson_index),
                        course_id=course.id,
                        lesson_id=lesson.id,
                        usage_frequency=random.randint(1, 20),
                        tags=["crawl", "auto", "lesson"],
                    )
                )
                added_words.add(w_lower)

        course.total_xp = course_xp
        course_added += 1

    # refresh denormalized counts
    all_categories = (await db.execute(select(CourseCategory))).scalars().all()
    for cat in all_categories:
        cnt = await db.scalar(select(func.count(Course.id)).where(Course.category_id == cat.id))
        cat.course_count = int(cnt or 0)

    return {"courses_added": course_added, "lessons_added": lesson_added}


async def seed_content_tables(db: AsyncSession, should_seed: bool) -> None:
    if not should_seed:
        return
    grammar_topics = [
        ("Articles A/An/The", "A1", "grammar"),
        ("Present Simple", "A1", "grammar"),
        ("Present Continuous", "A1", "grammar"),
        ("Past Simple", "A2", "grammar"),
        ("Future with Will", "A2", "grammar"),
        ("Comparatives", "A2", "grammar"),
        ("Superlatives", "A2", "grammar"),
        ("Present Perfect", "B1", "grammar"),
        ("Conditionals Type 1", "B1", "grammar"),
        ("Relative Clauses", "B1", "grammar"),
        ("Passive Voice", "B2", "grammar"),
        ("Conditionals Type 2/3", "B2", "grammar"),
    ]
    grammar_records: list[GrammarItem] = []
    for title, level, topic in grammar_topics:
        g = GrammarItem(
            title=title,
            level=level,
            topic=topic,
            summary=f"Core pattern for {title.lower()}.",
            content=f"Explanation and guided examples for {title}.",
            examples=[f"Example sentence for {title}."],
            tags=[level.lower(), topic],
            is_active=True,
        )
        db.add(g)
        grammar_records.append(g)
    await db.flush()

    questions: list[QuestionItem] = []
    for g in grammar_records:
        for i in range(4):
            prompt = f"[{g.level}] {g.title}: Choose the best answer ({i + 1})."
            q = QuestionItem(
                prompt=prompt,
                question_type="mcq",
                options=["Option A", "Option B", "Option C", "Option D"],
                answer={"correct": "Option A"},
                explanation="Option A is set as the seeded correct answer.",
                difficulty_level=g.level,
                tags=[g.topic or "grammar", g.level.lower()],
                is_active=True,
                grammar_id=g.id,
            )
            db.add(q)
            questions.append(q)
    await db.flush()

    by_level: dict[str, list[str]] = {}
    for q in questions:
        by_level.setdefault(q.difficulty_level, []).append(str(q.id))

    for level, q_ids in by_level.items():
        db.add(
            TestExam(
                title=f"Seeded {level} Placement Test",
                description=f"Auto-generated exam for {level} grammar coverage.",
                level=level,
                duration_minutes=25,
                passing_score=70,
                question_ids=q_ids[:20],
                is_published=True,
            )
        )


async def seed_remaining_empty_tables(db: AsyncSession, empty_set: set[str], force: bool) -> None:
    users = (await db.execute(select(User))).scalars().all()
    lessons = (await db.execute(select(Lesson))).scalars().all()
    courses = (await db.execute(select(Course))).scalars().all()
    vocab_items = (await db.execute(select(VocabularyItem))).scalars().all()
    wallets = (await db.execute(select(WalletTransaction.user_id).limit(1))).all()

    def can_seed(table_name: str) -> bool:
        return force or table_name in empty_set

    if can_seed("game_words"):
        words = [
            ("adapt", "To change for a new purpose", "A2", "general"),
            ("insight", "A deep understanding", "B1", "business"),
            ("sustain", "To maintain over time", "B2", "environment"),
            ("negotiate", "To discuss for agreement", "B1", "business"),
            ("commute", "To travel regularly for work", "A2", "daily"),
            ("resilient", "Able to recover quickly", "B2", "mindset"),
            ("predict", "To say what will happen", "A2", "general"),
            ("accurate", "Correct and precise", "B1", "study"),
            ("fluency", "Smoothness in language use", "B1", "language"),
            ("collaborate", "To work together", "B1", "work"),
        ]
        for word, definition, level, category in words:
            db.add(
                GameWord(
                    word=word,
                    definition=definition,
                    hint=f"Category: {category}",
                    example_sentence=f"Use '{word}' in your own sentence.",
                    ipa_pronunciation=None,
                    cefr_level=level,
                    category=category,
                    synonyms=[],
                    vietnamese_translation="(auto)",
                    letter_count=len(word),
                    xp_value=10,
                )
            )

    if can_seed("notifications") and users:
        for user in users[: min(30, len(users))]:
            db.add(
                Notification(
                    user_id=user.id,
                    title="Welcome to your learning plan",
                    body="You have new lessons and vocabulary ready for today.",
                    type="system",
                    data={"seed": True},
                    is_read=False,
                )
            )

    if can_seed("user_following") and len(users) >= 3:
        for user in users[: min(20, len(users))]:
            targets = random.sample([u for u in users if u.id != user.id], k=min(2, max(0, len(users) - 1)))
            for t in targets:
                db.add(UserFollowing(follower_id=user.id, following_id=t.id))

    if can_seed("activity_feeds") and users:
        for user in users[: min(40, len(users))]:
            db.add(
                ActivityFeed(
                    user_id=user.id,
                    activity_type="lesson_complete",
                    activity_data={"seed": True},
                    message="Completed a seeded lesson and earned XP.",
                    is_public=True,
                )
            )

    if can_seed("wallet_transactions") and users:
        from app.models import UserWallet

        user_wallets = (await db.execute(select(UserWallet))).scalars().all()
        for wallet in user_wallets:
            gain = random.randint(10, 120)
            db.add(
                WalletTransaction(
                    wallet_id=wallet.id,
                    user_id=wallet.user_id,
                    transaction_type="earn",
                    amount=gain,
                    balance_after=wallet.gems + gain,
                    source="seed",
                    reference_id=None,
                    description="Seeded reward transaction",
                )
            )

    if can_seed("user_inventory"):
        shop_items = (await db.execute(select(ShopItem))).scalars().all()
        if users and shop_items:
            for user in users[: min(25, len(users))]:
                item = random.choice(shop_items)
                db.add(
                    UserInventory(
                        user_id=user.id,
                        shop_item_id=item.id,
                        quantity=random.randint(1, 3),
                        is_active=False,
                        activated_at=None,
                        expires_at=None,
                    )
                )

    if can_seed("challenge_reward_claims") and users:
        for user in users[: min(20, len(users))]:
            db.add(
                ChallengeRewardClaim(
                    user_id=user.id,
                    challenge_id="daily_listen_10m",
                    claim_date=NOW - timedelta(days=random.randint(0, 7)),
                    xp_reward=20,
                    gems_reward=2,
                )
            )

    if can_seed("daily_review_sessions") and users and vocab_items:
        for user in users[: min(20, len(users))]:
            picked = random.sample(vocab_items, k=min(8, len(vocab_items)))
            total_words = len(picked)
            completed_words = random.randint(max(1, total_words // 2), total_words)
            db.add(
                DailyReviewSession(
                    user_id=user.id,
                    review_date=TODAY - timedelta(days=random.randint(0, 5)),
                    total_words=total_words,
                    completed_words=completed_words,
                    correct_count=random.randint(max(1, completed_words // 2), completed_words),
                    started_at=NOW - timedelta(minutes=random.randint(20, 100)),
                    completed_at=NOW - timedelta(minutes=random.randint(1, 15)),
                    is_completed=True,
                    vocab_list=[str(v.id) for v in picked],
                )
            )

    if can_seed("user_vocab_knowledge") and users and vocab_items:
        for user in users[: min(25, len(users))]:
            sample = random.sample(vocab_items, k=min(15, len(vocab_items)))
            for v in sample:
                strength = round(random.uniform(0.2, 0.95), 2)
                db.add(
                    UserVocabKnowledge(
                        user_id=user.id,
                        vocab_id=v.id,
                        strength=strength,
                        ease_factor=round(random.uniform(1.8, 2.9), 2),
                        interval_days=random.randint(1, 20),
                        last_review_date=NOW - timedelta(days=random.randint(1, 15)),
                        next_review_date=NOW + timedelta(days=random.randint(1, 10)),
                        review_count=random.randint(1, 20),
                        consecutive_correct=random.randint(0, 8),
                        review_history={"seed": True},
                        mastery_level="mastered" if strength >= 0.8 else "reviewing",
                    )
                )

    if can_seed("vocabulary_reviews"):
        user_vocab = (await db.execute(select(UserVocabulary))).scalars().all()
        for uv in user_vocab[: min(250, len(user_vocab))]:
            db.add(
                VocabularyReview(
                    user_vocabulary_id=uv.id,
                    quality=random.randint(2, 5),
                    time_spent_ms=random.randint(1500, 9000),
                    ease_factor_after=uv.ease_factor,
                    interval_after=uv.interval,
                    reviewed_at=NOW - timedelta(days=random.randint(0, 30)),
                )
            )

    if can_seed("vocabulary_decks") and users:
        for user in users[: min(12, len(users))]:
            db.add(
                VocabularyDeck(
                    user_id=user.id,
                    name="Daily Essentials",
                    description="Seeded deck for routine review",
                    is_public=False,
                    color="#2196F3",
                )
            )
        await db.flush()

    if can_seed("vocabulary_deck_items"):
        decks = (await db.execute(select(VocabularyDeck))).scalars().all()
        user_vocab = (await db.execute(select(UserVocabulary))).scalars().all()
        uv_by_user: dict = {}
        for uv in user_vocab:
            uv_by_user.setdefault(uv.user_id, []).append(uv)
        for deck in decks:
            items = uv_by_user.get(deck.user_id, [])
            for idx, uv in enumerate(items[:8]):
                db.add(VocabularyDeckItem(deck_id=deck.id, user_vocabulary_id=uv.id, order=idx))

    if can_seed("user_progress") and users and lessons:
        for user in users[: min(20, len(users))]:
            sample_lessons = random.sample(lessons, k=min(8, len(lessons)))
            for lesson in sample_lessons:
                db.add(
                    UserProgress(
                        user_id=user.id,
                        lesson_id=lesson.id,
                        course_id=lesson.course_id,
                        status=random.choice(["in_progress", "completed"]),
                        score=random.randint(55, 100),
                        completed_at=NOW - timedelta(days=random.randint(0, 30)),
                        time_spent_seconds=random.randint(180, 1800),
                        attempts=random.randint(1, 4),
                    )
                )

    if can_seed("lesson_attempts") and users and lessons:
        for user in users[: min(15, len(users))]:
            sample_lessons = random.sample(lessons, k=min(6, len(lessons)))
            for lesson in sample_lessons:
                started = NOW - timedelta(days=random.randint(0, 30), minutes=random.randint(20, 80))
                finished = started + timedelta(minutes=random.randint(6, 18))
                score = random.randint(50, 100)
                db.add(
                    LessonAttempt(
                        user_id=user.id,
                        lesson_id=lesson.id,
                        started_at=started,
                        finished_at=finished,
                        score=score,
                        passed=score >= 70,
                        xp_earned=random.randint(10, 45),
                        total_questions=10,
                        correct_answers=random.randint(5, 10),
                        hints_used=random.randint(0, 3),
                        lives_remaining=random.randint(1, 5),
                        time_spent_ms=random.randint(200000, 1100000),
                        avg_response_time_ms=random.randint(3500, 11000),
                        device_type=random.choice(["web", "android", "ios"]),
                    )
                )

    if can_seed("question_attempts"):
        lesson_attempts = (await db.execute(select(LessonAttempt))).scalars().all()
        for la in lesson_attempts[: min(120, len(lesson_attempts))]:
            for q_idx in range(4):
                is_correct = random.random() > 0.28
                db.add(
                    QuestionAttempt(
                        lesson_attempt_id=la.id,
                        question_id=f"seed-q-{q_idx + 1}",
                        question_type="mcq",
                        user_answer="Option A",
                        correct_answer="Option A",
                        is_correct=is_correct,
                        time_spent_ms=random.randint(3500, 12000),
                        hint_used=not is_correct and random.random() > 0.5,
                        attempt_number=1,
                        confidence_score=round(random.uniform(0.4, 0.95), 2),
                        difficulty_rating=random.choice(["easy", "medium", "hard"]),
                    )
                )

    if can_seed("game_sessions") and users:
        for user in users[: min(30, len(users))]:
            for _ in range(random.randint(1, 3)):
                start = NOW - timedelta(days=random.randint(0, 25), minutes=random.randint(5, 35))
                end = start + timedelta(minutes=random.randint(2, 10))
                total_q = random.randint(5, 12)
                correct = random.randint(2, total_q)
                db.add(
                    GameSession(
                        user_id=user.id,
                        game_type=random.choice([
                            "word_scramble",
                            "fill_blank",
                            "matching",
                            "spelling_bee",
                            "grammar_quiz",
                            "hangman",
                        ]),
                        score=correct,
                        total_questions=total_q,
                        correct_answers=correct,
                        xp_earned=correct * 5,
                        cefr_level=random.choice(["A1", "A2", "B1", "B2"]),
                        category=random.choice(["daily", "travel", "business"]),
                        duration_seconds=int((end - start).total_seconds()),
                        started_at=start,
                        completed_at=end,
                        xp_awarded=True,
                        session_data={"seed": True},
                    )
                )

    if can_seed("media_resources"):
        resources = [
            ("image", "https://images.example.com/course-1.jpg", "course-1.jpg", "image/jpeg"),
            ("image", "https://images.example.com/course-2.jpg", "course-2.jpg", "image/jpeg"),
            ("audio", "https://audio.example.com/lesson-1.mp3", "lesson-1.mp3", "audio/mpeg"),
        ]
        for r_type, url, filename, mime in resources:
            db.add(
                MediaResource(
                    resource_type=r_type,
                    url=url,
                    filename=filename,
                    duration=120 if r_type == "audio" else None,
                    size=10240,
                    mime_type=mime,
                    reference_count=random.randint(1, 8),
                )
            )

    if can_seed("api_cache_entries"):
        db.add(
            APICacheEntry(
                cache_key=f"seed:news:{TODAY.isoformat()}",
                api_name="seed",
                data=json.dumps({"status": "ok", "seeded": True}),
                hit_count=1,
            )
        )

    if can_seed("audit_logs") and users:
        db.add(
            AuditLog(
                user_id=users[0].id,
                action="seed",
                resource_type="database",
                resource_id="seed_empty_tables_and_crawl",
                details=json.dumps({"seed": True}),
                ip_address="127.0.0.1",
                user_agent="seed-script",
            )
        )


async def execute(args: argparse.Namespace) -> None:
    async with AsyncSessionLocal() as db:
        empty_before = await empty_tables(db)
        print(f"Empty tables before: {len(empty_before)}")
        if empty_before:
            print(" - " + "\n - ".join(empty_before))

        categories = await ensure_categories(db)

        await seed_permissions_and_mapping(
            db,
            should_seed=(args.force or "permissions" in empty_before or "role_permissions" in empty_before),
        )

        crawl_stats = await seed_crawled_courses(
            db,
            categories=categories,
            target_courses=args.target_courses,
            lessons_per_course=args.lessons_per_course,
            max_feed_items=args.max_feed_items,
        )

        await seed_content_tables(
            db,
            should_seed=(args.force or "grammar_items" in empty_before or "question_bank" in empty_before or "test_exams" in empty_before),
        )

        await seed_remaining_empty_tables(db, set(empty_before), args.force)
        await db.commit()

        empty_after = await empty_tables(db)
        print("\nSeed summary")
        print(f" - Crawled courses added: {crawl_stats['courses_added']}")
        print(f" - Crawled lessons added: {crawl_stats['lessons_added']}")
        print(f" - Empty tables after: {len(empty_after)}")
        if empty_after:
            print(" - Remaining empty tables:")
            for t in empty_after:
                print(f"   * {t}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Seed empty tables and crawl courses/lessons")
    parser.add_argument("--target-courses", type=int, default=30)
    parser.add_argument("--lessons-per-course", type=int, default=8)
    parser.add_argument("--max-feed-items", type=int, default=260)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    asyncio_args = parse_args()
    import asyncio

    asyncio.run(execute(asyncio_args))