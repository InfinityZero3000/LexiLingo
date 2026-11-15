"""The one writer of a learner's CEFR level, and what must follow a change.

Two levels live side by side:
  - working level (`users.level` == `UserProficiencyProfile.assessed_level`):
    what the learner studies at. A test sets it, and the learner may pick it.
  - certified level (`users.certified_level`): what a test confirmed. Only a
    test moves it, and only upward. Rank and badges read this one.

Every change goes through `apply_level_change` so the history row, the rank
and the learner-state epoch can never be skipped by one caller; after the
commit the caller runs `publish_level_change` to drop caches outside the DB.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Literal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.clients.ai_service_client import invalidate_learner_card
from app.core.redis import get_redis
from app.models.proficiency import UserLevelHistory, UserProficiencyProfile
from app.models.user import User
from app.services.feature_processor import INSIGHTS_CACHE_PREFIX
from app.services.learner_state import bump_learner_state_epoch
from app.services.rank_service import (
    apply_rank_info_to_user,
    calculate_rank,
    rank_proficiency_level,
)

logger = logging.getLogger(__name__)

CEFR_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
LevelSource = Literal["placement", "exam", "self"]


def normalise_level(value: object) -> str | None:
    text = str(value or "").strip().upper()
    return text if text in CEFR_LEVELS else None


def level_index(level: str | None) -> int:
    return CEFR_LEVELS.index(level) if level in CEFR_LEVELS else 0


def level_verified(user: User) -> bool:
    return level_index(normalise_level(user.level)) <= level_index(
        rank_proficiency_level(user)
    )


def refresh_rank(user: User) -> None:
    apply_rank_info_to_user(
        user,
        calculate_rank(
            numeric_level=user.numeric_level or 1,
            proficiency_level=rank_proficiency_level(user),
        ),
    )


async def get_or_create_profile(db: AsyncSession, user: User) -> UserProficiencyProfile:
    """The learner's proficiency profile, created from their current level.

    Several routes create the profile lazily. Seeding it with a fixed "A1"
    made the next practice batch settle `users.level` onto that A1 — a silent
    demotion for anyone who held a level before their first profile read.
    Flushes, never commits.
    """
    profile = (
        await db.execute(
            select(UserProficiencyProfile).where(
                UserProficiencyProfile.user_id == user.id
            )
        )
    ).scalar_one_or_none()
    if profile is None:
        profile = UserProficiencyProfile(
            user_id=user.id,
            assessed_level=normalise_level(user.level) or "A1",
            overall_score=0.0,
            total_xp=user.total_xp or 0,
            total_exercises_completed=0,
            total_correct_exercises=0,
            total_lessons_completed=0,
        )
        db.add(profile)
        await db.flush()
    return profile


@dataclass(frozen=True)
class LevelChange:
    user_id: UUID
    previous_level: str
    working_level: str
    previous_certified: str | None
    certified_level: str | None

    @property
    def certified_changed(self) -> bool:
        return self.previous_certified != self.certified_level


async def apply_level_change(
    db: AsyncSession,
    user: User,
    profile: UserProficiencyProfile,
    *,
    source: LevelSource,
    working: str | None = None,
    certified: str | None = None,
    score: float | None = None,
    initial: bool = False,
) -> LevelChange | None:
    """Move the working and/or certified level. Never commits.

    A test may only raise the certified level, except the first placement
    (`initial=True`), which sets it outright. The learner (`source="self"`)
    may set the working level anywhere and never touches the certified one.
    Returns None when nothing changed.
    """
    now = datetime.now(UTC)
    previous_level = normalise_level(profile.assessed_level) or normalise_level(user.level) or "A1"
    previous_certified = normalise_level(user.certified_level)

    new_working = normalise_level(working) or previous_level
    new_certified = previous_certified
    if source != "self":
        target = normalise_level(certified)
        if target and (
            initial
            or previous_certified is None
            or level_index(target) > level_index(previous_certified)
        ):
            new_certified = target

    if new_working == previous_level and new_certified == previous_certified:
        # users.level can still be out of step with the profile.
        if user.level != previous_level:
            user.level = previous_level
        return None

    profile.assessed_level = new_working
    user.level = new_working
    user.certified_level = new_certified
    if source != "self" and new_certified != previous_certified:
        profile.placement_level = new_certified
        profile.placement_at = now

    if new_working != previous_level:
        profile.last_level_change_at = now
        if profile.id is None:
            await db.flush()
        if source == "self":
            change_type, reason = "self_set", "Chosen by the learner"
        elif initial:
            change_type, reason = "initial", "Placement test"
        else:
            change_type, reason = "promotion", "Passed the level exam"
        if score is not None:
            reason = f"{reason}: {round(score)}%"
        db.add(
            UserLevelHistory(
                profile_id=profile.id,
                previous_level=previous_level,
                new_level=new_working,
                change_type=change_type,
                overall_score=score,
                exercises_completed=profile.total_exercises_completed or 0,
                accuracy=profile.accuracy if profile.total_exercises_completed else 0.0,
                reason=reason,
            )
        )

    refresh_rank(user)
    # Versions TraceCAG artifacts and ai-service's recommendation cache key,
    # neither of which carries the level itself.
    await bump_learner_state_epoch(db, user.id, now)

    return LevelChange(
        user_id=user.id,
        previous_level=previous_level,
        working_level=new_working,
        previous_certified=previous_certified,
        certified_level=new_certified,
    )


async def publish_level_change(change: LevelChange | None) -> None:
    """After the commit: drop the caches that live outside the database.

    Best-effort, like the learner-card invalidation it wraps — the card has a
    short TTL and the insights cache is recomputed on a miss.
    """
    if change is None:
        return
    await invalidate_learner_card(change.user_id)
    try:
        client = await get_redis()
        if client is not None:
            await client.delete(f"{INSIGHTS_CACHE_PREFIX}{change.user_id}")
    except Exception as exc:
        logger.warning("insights cache drop failed for %s: %s", change.user_id, exc)
