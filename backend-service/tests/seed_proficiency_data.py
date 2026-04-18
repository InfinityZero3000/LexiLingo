"""
Seed Proficiency Data for nhthang312@gmail.com

Generates realistic, large-scale proficiency data across all 5 tables:
  - user_proficiency_profiles (1 row)
  - user_skill_scores (6 rows — one per SkillType)
  - exercise_attempts (~500 rows — spread over 90 days)
  - user_level_history (4 rows — A1→A2→B1 progression)
  - level_assessment_tests (3 rows — initial + 2 quick assessments)

This simulates a real learner who has been active for ~3 months,
progressing from A1 through A2 and currently at B1.

Usage:
  cd backend-service
  source venv/bin/activate
  python -m tests.seed_proficiency_data          # seed
  python -m tests.seed_proficiency_data --clean   # remove seeded data
"""

import asyncio
import sys
import random
import uuid
from datetime import datetime, timedelta
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.core.config import settings
from app.core.database import Base
from app.models.user import User
from app.models.proficiency import (
    UserProficiencyProfile,
    UserSkillScore,
    UserLevelHistory,
    ExerciseAttempt,
    LevelAssessmentTest,
    SkillType,
)

# ── Constants ────────────────────────────────────────────────────────
TARGET_EMAIL = "nhthang312@gmail.com"
SEED_TAG = "proficiency_seed_v1"  # stored in attempt_metadata for easy cleanup

SKILLS = list(SkillType)
EXERCISE_TYPES = {
    SkillType.VOCABULARY: ["vocab_fill_blank", "vocab_match", "vocab_multiple_choice", "vocab_flashcard"],
    SkillType.GRAMMAR: ["grammar_choice", "grammar_fill_blank", "grammar_correction", "grammar_transform"],
    SkillType.READING: ["reading_comprehension", "reading_true_false", "reading_match_paragraph"],
    SkillType.LISTENING: ["listening_comprehension", "listening_fill_gap", "listening_dictation"],
    SkillType.SPEAKING: ["speaking_repeat", "speaking_describe", "speaking_conversation"],
    SkillType.WRITING: ["writing_sentence", "writing_paragraph", "writing_correction"],
}

# Difficulty distribution shifts as the learner progresses
CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]

random.seed(42)  # Reproducible


# ── Helpers ──────────────────────────────────────────────────────────

def _random_score(base: float, spread: float = 15.0) -> float:
    """Generate a score centered around `base` with gaussian noise, clamped to [0, 100]."""
    return max(0.0, min(100.0, round(random.gauss(base, spread), 1)))


def _pick_difficulty(day: int, total_days: int) -> str:
    """Pick exercise difficulty that shifts upward over time."""
    progress = day / total_days  # 0 → 1
    if progress < 0.25:
        return random.choices(CEFR_LEVELS[:3], weights=[60, 30, 10])[0]
    elif progress < 0.55:
        return random.choices(CEFR_LEVELS[:4], weights=[20, 45, 30, 5])[0]
    elif progress < 0.80:
        return random.choices(CEFR_LEVELS[:4], weights=[5, 25, 50, 20])[0]
    else:
        return random.choices(CEFR_LEVELS[:5], weights=[2, 15, 40, 35, 8])[0]


def _pick_skill(day: int, total_days: int) -> SkillType:
    """Weighted skill selection — more reading/listening added later."""
    progress = day / total_days
    if progress < 0.3:
        # Early: mostly vocab + grammar
        return random.choices(
            SKILLS,
            weights=[35, 35, 10, 10, 5, 5],
        )[0]
    elif progress < 0.6:
        return random.choices(
            SKILLS,
            weights=[25, 25, 18, 18, 7, 7],
        )[0]
    else:
        return random.choices(
            SKILLS,
            weights=[20, 20, 20, 20, 10, 10],
        )[0]


def _accuracy_for_day(day: int, total_days: int, skill: SkillType) -> float:
    """Base accuracy that improves over time, with skill-specific offsets."""
    base = 0.50 + 0.30 * (day / total_days)  # 50% → 80% over time
    offsets = {
        SkillType.VOCABULARY: 0.05,
        SkillType.GRAMMAR: 0.0,
        SkillType.READING: 0.03,
        SkillType.LISTENING: -0.03,
        SkillType.SPEAKING: -0.08,
        SkillType.WRITING: -0.05,
    }
    return min(0.95, max(0.20, base + offsets.get(skill, 0)))


# ── Main Seed Logic ─────────────────────────────────────────────────

async def seed(database_url: str | None = None):
    url = database_url or settings.DATABASE_URL
    engine = create_async_engine(url, poolclass=NullPool, echo=False)
    async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        # 1. Find or create the test user
        result = await session.execute(select(User).where(User.email == TARGET_EMAIL))
        user = result.scalar_one_or_none()
        if not user:
            # Auto-create for CI / fresh environments
            from app.core.security import get_password_hash
            user = User(
                email=TARGET_EMAIL,
                username="nhthang312",
                hashed_password=get_password_hash("SeedUser_testpass123!"),
                display_name="Nguyen Huu Thang (seed)",
            )
            session.add(user)
            await session.commit()
            await session.refresh(user)
            print(f"  Created test user: {TARGET_EMAIL}")
        else:
            print(f"  Found user: {user.display_name or user.username} (id={user.id})")

        user_id = user.id

        # 2. Clean any existing proficiency data for this user
        await _clean_user_proficiency(session, user_id)
        print("  Cleaned existing proficiency data.")

        # ── Simulation parameters ────────────────────────────────
        TOTAL_DAYS = 90
        NOW = datetime.utcnow()
        START_DATE = NOW - timedelta(days=TOTAL_DAYS)

        # Exercises per day: ramps up 3→8
        def exercises_per_day(day: int) -> int:
            base = 3 + int(5 * (day / TOTAL_DAYS))
            return max(1, base + random.randint(-1, 2))

        # ── Generate exercise attempts ───────────────────────────
        all_attempts: list[ExerciseAttempt] = []
        skill_stats: dict[SkillType, dict] = {s: {"total": 0, "correct": 0, "scores": []} for s in SKILLS}
        total_correct = 0

        for day in range(TOTAL_DAYS):
            date = START_DATE + timedelta(days=day)
            n_exercises = exercises_per_day(day)

            for _ in range(n_exercises):
                skill = _pick_skill(day, TOTAL_DAYS)
                difficulty = _pick_difficulty(day, TOTAL_DAYS)
                acc_prob = _accuracy_for_day(day, TOTAL_DAYS, skill)
                is_correct = random.random() < acc_prob

                if is_correct:
                    score = _random_score(base=75 + 15 * (day / TOTAL_DAYS), spread=10)
                else:
                    score = _random_score(base=25 + 10 * (day / TOTAL_DAYS), spread=12)

                exercise_type = random.choice(EXERCISE_TYPES[skill])
                time_spent = random.randint(5, 120)

                attempt = ExerciseAttempt(
                    user_id=user_id,
                    exercise_type=exercise_type,
                    skill=skill,
                    difficulty_level=difficulty,
                    is_correct=is_correct,
                    score=round(score, 1),
                    time_spent_seconds=time_spent,
                    attempted_at=date + timedelta(
                        hours=random.randint(8, 22),
                        minutes=random.randint(0, 59),
                    ),
                    attempt_metadata={"seed": SEED_TAG, "day": day},
                )
                all_attempts.append(attempt)

                skill_stats[skill]["total"] += 1
                skill_stats[skill]["scores"].append(score)
                if is_correct:
                    skill_stats[skill]["correct"] += 1
                    total_correct += 1

        session.add_all(all_attempts)
        await session.flush()
        print(f"  Seeded {len(all_attempts)} exercise attempts over {TOTAL_DAYS} days.")

        # ── Create proficiency profile ───────────────────────────
        total_exercises = len(all_attempts)
        overall_accuracy = total_correct / total_exercises if total_exercises else 0

        profile = UserProficiencyProfile(
            user_id=user_id,
            assessed_level="B1",
            overall_score=round(
                sum(sum(s["scores"]) / max(1, len(s["scores"])) for s in skill_stats.values()) / len(SKILLS), 2
            ),
            total_xp=total_exercises * 12,  # ~12 avg XP per exercise
            total_exercises_completed=total_exercises,
            total_correct_exercises=total_correct,
            total_lessons_completed=38,  # Simulated lesson count
            last_assessment_at=NOW - timedelta(days=2),
            last_level_change_at=NOW - timedelta(days=15),
            created_at=START_DATE,
            updated_at=NOW,
        )
        session.add(profile)
        await session.flush()
        await session.refresh(profile)
        print(f"  Created proficiency profile (assessed_level=B1, overall_score={profile.overall_score})")

        # ── Create skill scores ──────────────────────────────────
        skill_score_rows = []
        for skill in SKILLS:
            stats = skill_stats[skill]
            avg_score = sum(stats["scores"]) / max(1, len(stats["scores"]))
            accuracy = stats["correct"] / max(1, stats["total"])
            confidence = min(1.0, stats["total"] / 50)

            # Estimate level from score
            if avg_score >= 80:
                est_level = "B2"
            elif avg_score >= 65:
                est_level = "B1"
            elif avg_score >= 50:
                est_level = "A2"
            else:
                est_level = "A1"

            # 7d/30d ago snapshots (slightly lower than current)
            score_7d = max(0, round(avg_score - random.uniform(2, 8), 2))
            score_30d = max(0, round(avg_score - random.uniform(8, 18), 2))

            row = UserSkillScore(
                profile_id=profile.id,
                skill=skill,
                score=round(avg_score, 2),
                confidence=round(confidence, 2),
                estimated_level=est_level,
                exercises_completed=stats["total"],
                correct_exercises=stats["correct"],
                score_7d_ago=score_7d,
                score_30d_ago=score_30d,
                last_updated=NOW,
            )
            skill_score_rows.append(row)

        session.add_all(skill_score_rows)
        await session.flush()
        print("  Created 6 skill score records:")
        for row in skill_score_rows:
            trend = "↑" if row.score > (row.score_7d_ago or 0) else "→"
            acc = row.correct_exercises / max(1, row.exercises_completed)
            print(
                f"     {row.skill.value:12s}  score={row.score:5.1f}  "
                f"level={row.estimated_level}  exercises={row.exercises_completed:3d}  "
                f"accuracy={acc:.0%}  confidence={row.confidence:.2f}  {trend}"
            )

        # ── Create level history ─────────────────────────────────
        level_transitions = [
            {
                "previous": "A1",
                "new": "A1",
                "type": "initial",
                "days_ago": 90,
                "score": 0.0,
                "exercises": 0,
                "accuracy": 0.0,
                "reason": "Initial proficiency profile created at registration.",
            },
            {
                "previous": "A1",
                "new": "A2",
                "type": "promotion",
                "days_ago": 60,
                "score": 55.3,
                "exercises": 150,
                "accuracy": 0.62,
                "reason": "Met A2 requirements: Vocabulary ≥60, Grammar ≥55, 100+ exercises, 60%+ accuracy.",
            },
            {
                "previous": "A2",
                "new": "B1",
                "type": "promotion",
                "days_ago": 15,
                "score": 67.8,
                "exercises": 380,
                "accuracy": 0.68,
                "reason": "Met B1 requirements: Vocabulary ≥70, Grammar ≥65, Reading ≥60, 300+ exercises, 65%+ accuracy, 7+ streak days.",
            },
            {
                "previous": "A2",
                "new": "A1",
                "type": "demotion",
                "days_ago": 45,
                "score": 48.1,
                "exercises": 200,
                "accuracy": 0.54,
                "reason": "Accuracy dropped below A2 threshold after a study break. Demoted to A1.",
            },
        ]

        for t in level_transitions:
            snapshot = {s.value: round(random.uniform(t["score"] * 0.8, t["score"] * 1.2), 1) for s in SKILLS}
            history = UserLevelHistory(
                profile_id=profile.id,
                previous_level=t["previous"],
                new_level=t["new"],
                change_type=t["type"],
                overall_score=t["score"],
                skill_scores_snapshot=snapshot,
                exercises_completed=t["exercises"],
                accuracy=t["accuracy"],
                reason=t["reason"],
                triggered_at=NOW - timedelta(days=t["days_ago"]),
            )
            session.add(history)

        await session.flush()
        print(f"  Created {len(level_transitions)} level history records (A1→A2→B1 with a demotion episode).")

        # ── Create assessment tests ──────────────────────────────
        assessment_tests = [
            {
                "type": "initial",
                "level": "A1",
                "score": 18.5,
                "correct": 4,
                "questions": 20,
                "time": 420,
                "days_ago": 90,
                "changed": False,
                "prev_level": None,
            },
            {
                "type": "quick",
                "level": "A2",
                "score": 52.3,
                "correct": 10,
                "questions": 20,
                "time": 380,
                "days_ago": 55,
                "changed": True,
                "prev_level": "A1",
            },
            {
                "type": "comprehensive",
                "level": "B1",
                "score": 68.7,
                "correct": 13,
                "questions": 20,
                "time": 520,
                "days_ago": 10,
                "changed": True,
                "prev_level": "A2",
            },
        ]

        for t in assessment_tests:
            test = LevelAssessmentTest(
                user_id=user_id,
                test_type=t["type"],
                assessed_level=t["level"],
                overall_score=t["score"],
                skill_scores={
                    s.value: round(random.uniform(t["score"] * 0.7, t["score"] * 1.3), 1)
                    for s in SKILLS
                },
                questions_count=t["questions"],
                correct_count=t["correct"],
                time_taken_seconds=t["time"],
                started_at=NOW - timedelta(days=t["days_ago"]),
                completed_at=NOW - timedelta(days=t["days_ago"]) + timedelta(seconds=t["time"]),
                level_changed=t["changed"],
                previous_level=t["prev_level"],
            )
            session.add(test)

        await session.flush()
        print(f"  Created {len(assessment_tests)} assessment test records.")

        # ── Update user record ───────────────────────────────────
        user.level = "B1"
        user.total_xp = profile.total_xp
        user.numeric_level = 3
        user.rank = "silver"

        await session.commit()
        print(f"\n  Seed complete! User '{TARGET_EMAIL}' now has full proficiency data.")
        print(f"    Level: B1 | XP: {profile.total_xp} | "
              f"Exercises: {total_exercises} | Accuracy: {overall_accuracy:.1%}")

    await engine.dispose()
    return True


async def clean(database_url: str | None = None):
    """Remove all seeded proficiency data for the target user."""
    url = database_url or settings.DATABASE_URL
    engine = create_async_engine(url, poolclass=NullPool, echo=False)
    async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        result = await session.execute(select(User).where(User.email == TARGET_EMAIL))
        user = result.scalar_one_or_none()
        if not user:
            print(f"User '{TARGET_EMAIL}' not found. Nothing to clean.")
            await engine.dispose()
            return

        await _clean_user_proficiency(session, user.id)
        user.level = "A1"
        user.total_xp = 0
        user.numeric_level = 1
        user.rank = "bronze"

        await session.commit()
        print(f"  Cleaned all proficiency data for '{TARGET_EMAIL}'.")

    await engine.dispose()


async def _clean_user_proficiency(session: AsyncSession, user_id: uuid.UUID):
    """Delete all proficiency-related rows for a user."""
    # Must delete children before parents due to FK constraints
    # 1. Find profile
    result = await session.execute(
        select(UserProficiencyProfile).where(UserProficiencyProfile.user_id == user_id)
    )
    profile = result.scalar_one_or_none()

    if profile:
        # Delete skill scores and level history (cascade should handle, but be explicit)
        await session.execute(
            delete(UserSkillScore).where(UserSkillScore.profile_id == profile.id)
        )
        await session.execute(
            delete(UserLevelHistory).where(UserLevelHistory.profile_id == profile.id)
        )
        await session.execute(
            delete(UserProficiencyProfile).where(UserProficiencyProfile.id == profile.id)
        )

    # Delete exercise attempts
    await session.execute(
        delete(ExerciseAttempt).where(ExerciseAttempt.user_id == user_id)
    )

    # Delete assessment tests
    await session.execute(
        delete(LevelAssessmentTest).where(LevelAssessmentTest.user_id == user_id)
    )

    await session.flush()


# ── CLI Entrypoint ───────────────────────────────────────────────────
if __name__ == "__main__":
    if "--clean" in sys.argv:
        asyncio.run(clean())
    else:
        asyncio.run(seed())
