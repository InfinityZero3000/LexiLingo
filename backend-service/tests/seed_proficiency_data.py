"""Seed deterministic proficiency data for integration tests.

This module is invoked by CI and local test flows via:
  python -m tests.seed_proficiency_data
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import delete, select

from app.core.database import AsyncSessionLocal
from app.models.proficiency import (
    SkillType,
    UserLevelHistory,
    UserProficiencyProfile,
    UserSkillScore,
)
from app.models.user import User

TARGET_EMAIL = "nhthang2077@gmail.com"
TARGET_USERNAME = "nhthang2077"
TARGET_LEVEL = "B1"
TARGET_EXERCISES = 520
TARGET_CORRECT = 418
TARGET_LESSONS = 42
TARGET_XP = 6200
TARGET_OVERALL_SCORE = 67.5

SKILL_SEED = {
    SkillType.VOCABULARY: {"score": 71.0, "confidence": 0.86, "level": "B1", "done": 92, "ok": 77},
    SkillType.GRAMMAR: {"score": 69.0, "confidence": 0.84, "level": "B1", "done": 90, "ok": 74},
    SkillType.READING: {"score": 66.0, "confidence": 0.81, "level": "B1", "done": 88, "ok": 70},
    SkillType.LISTENING: {"score": 65.0, "confidence": 0.8, "level": "B1", "done": 86, "ok": 68},
    SkillType.SPEAKING: {"score": 63.0, "confidence": 0.79, "level": "B1", "done": 82, "ok": 64},
    SkillType.WRITING: {"score": 61.0, "confidence": 0.78, "level": "B1", "done": 82, "ok": 65},
}


def _make_unique_username() -> str:
    return f"{TARGET_USERNAME}_{uuid4().hex[:8]}"


async def seed() -> None:
    now = datetime.now(timezone.utc)

    async with AsyncSessionLocal() as session:
        # Ensure target user exists.
        user = (
            await session.execute(select(User).where(User.email == TARGET_EMAIL))
        ).scalar_one_or_none()

        if user is None:
            username = TARGET_USERNAME
            username_taken = (
                await session.execute(select(User).where(User.username == username))
            ).scalar_one_or_none()
            if username_taken is not None:
                username = _make_unique_username()

            user = User(
                email=TARGET_EMAIL,
                username=username,
                hashed_password="seeded-test-password",
                display_name="Seeded Proficiency User",
                native_language="vi",
                target_language="en",
                level=TARGET_LEVEL,
                total_xp=TARGET_XP,
                numeric_level=17,
                rank="gold",
                is_onboarding_completed=True,
                is_active=True,
                is_verified=True,
                provider=["local"],
            )
            session.add(user)
            await session.flush()
        else:
            user.level = TARGET_LEVEL
            user.total_xp = TARGET_XP
            if not user.rank:
                user.rank = "gold"

        # Ensure profile exists and is deterministic.
        profile = (
            await session.execute(
                select(UserProficiencyProfile).where(UserProficiencyProfile.user_id == user.id)
            )
        ).scalar_one_or_none()

        if profile is None:
            profile = UserProficiencyProfile(
                user_id=user.id,
                assessed_level=TARGET_LEVEL,
                overall_score=TARGET_OVERALL_SCORE,
                total_xp=TARGET_XP,
                total_exercises_completed=TARGET_EXERCISES,
                total_correct_exercises=TARGET_CORRECT,
                total_lessons_completed=TARGET_LESSONS,
                last_assessment_at=now - timedelta(days=2),
                last_level_change_at=now - timedelta(days=7),
            )
            session.add(profile)
            await session.flush()
        else:
            profile_updates = {
                "assessed_level": TARGET_LEVEL,
                "overall_score": TARGET_OVERALL_SCORE,
                "total_xp": TARGET_XP,
                "total_exercises_completed": TARGET_EXERCISES,
                "total_correct_exercises": TARGET_CORRECT,
                "total_lessons_completed": TARGET_LESSONS,
                "last_assessment_at": now - timedelta(days=2),
                "last_level_change_at": now - timedelta(days=7),
            }
            for field, value in profile_updates.items():
                setattr(profile, field, value)

        # Reset and seed skill scores deterministically.
        await session.execute(
            delete(UserSkillScore).where(UserSkillScore.profile_id == profile.id)
        )
        for skill, value in SKILL_SEED.items():
            session.add(
                UserSkillScore(
                    profile_id=profile.id,
                    skill=skill,
                    score=value["score"],
                    confidence=value["confidence"],
                    estimated_level=value["level"],
                    exercises_completed=value["done"],
                    correct_exercises=value["ok"],
                    score_7d_ago=max(0.0, value["score"] - 2.0),
                    score_30d_ago=max(0.0, value["score"] - 6.0),
                    last_updated=now,
                )
            )

        # Reset and seed level history used by history integration tests.
        await session.execute(
            delete(UserLevelHistory).where(UserLevelHistory.profile_id == profile.id)
        )
        history_rows = [
            UserLevelHistory(
                profile_id=profile.id,
                previous_level="A1",
                new_level="A1",
                change_type="initial",
                overall_score=36.0,
                exercises_completed=40,
                accuracy=0.72,
                reason="Initial proficiency profile created",
                triggered_at=now - timedelta(days=40),
            ),
            UserLevelHistory(
                profile_id=profile.id,
                previous_level="A1",
                new_level="A2",
                change_type="promotion",
                overall_score=49.5,
                exercises_completed=140,
                accuracy=0.78,
                reason="Consistent performance across A1/A2 exercises",
                triggered_at=now - timedelta(days=28),
            ),
            UserLevelHistory(
                profile_id=profile.id,
                previous_level="A2",
                new_level="B1",
                change_type="promotion",
                overall_score=64.0,
                exercises_completed=340,
                accuracy=0.81,
                reason="Met minimum B1 score and exercise requirements",
                triggered_at=now - timedelta(days=15),
            ),
            UserLevelHistory(
                profile_id=profile.id,
                previous_level="B1",
                new_level="A2",
                change_type="demotion",
                overall_score=55.5,
                exercises_completed=380,
                accuracy=0.64,
                reason="Short-term regression in grammar and speaking accuracy",
                triggered_at=now - timedelta(days=10),
            ),
            UserLevelHistory(
                profile_id=profile.id,
                previous_level="A2",
                new_level="B1",
                change_type="promotion",
                overall_score=TARGET_OVERALL_SCORE,
                exercises_completed=TARGET_EXERCISES,
                accuracy=TARGET_CORRECT / TARGET_EXERCISES,
                reason="Recovered and stabilized above B1 thresholds",
                triggered_at=now - timedelta(days=7),
            ),
        ]
        session.add_all(history_rows)

        await session.commit()

    print("Seed completed: tests.seed_proficiency_data")


if __name__ == "__main__":
    asyncio.run(seed())
