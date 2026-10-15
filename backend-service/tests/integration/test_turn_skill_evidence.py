"""A conversation turn credits its CEFR skill score exactly once.

ai-service marks one observation per turn with a `skill` payload. Talking to
Lexi used to move the concept state but neither the speaking nor the writing
score, so hours of conversation left the learner model unchanged on the two
skills a conversation actually exercises.
"""

from datetime import UTC, datetime

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.proficiency import SkillType as ModelSkillType
from app.models.proficiency import UserProficiencyProfile, UserSkillScore
from app.routes.learner_state import _record_turn_skill_evidence
from app.schemas.learner_state import ALLOWED_OBSERVATION_PAYLOAD_KEYS
from app.services.learner_state import ObservationInput


def _observation(user_id, *, event_id: str, payload: dict) -> ObservationInput:
    return ObservationInput(
        event_id=event_id,
        user_id=user_id,
        concept_id="grammar:present_perfect",
        outcome="correct",
        confidence=0.6,
        observed_at=datetime.now(UTC),
        payload=payload,
    )


async def _score(
    db_session: AsyncSession, user_id, skill: ModelSkillType
) -> UserSkillScore | None:
    profile = await db_session.scalar(
        select(UserProficiencyProfile).where(UserProficiencyProfile.user_id == user_id)
    )
    if profile is None:
        return None
    return await db_session.scalar(
        select(UserSkillScore).where(
            UserSkillScore.profile_id == profile.id,
            UserSkillScore.skill == skill,
        )
    )


@pytest.mark.asyncio
async def test_typed_turn_credits_writing(db_session: AsyncSession, test_user):
    event_id = "a" * 64
    await _record_turn_skill_evidence(
        db_session,
        [
            _observation(
                test_user.id,
                event_id=event_id,
                payload={"error_count": 0, "skill": "writing", "score": 100.0},
            )
        ],
        {event_id},
    )

    score = await _score(db_session, test_user.id, ModelSkillType.WRITING)
    assert score is not None
    assert score.exercises_completed == 1
    assert score.score > 0


@pytest.mark.asyncio
async def test_duplicate_delivery_is_not_scored_again(
    db_session: AsyncSession, test_user
):
    """The spool delivers at least once; only newly inserted events count."""
    event_id = "b" * 64
    observation = _observation(
        test_user.id,
        event_id=event_id,
        payload={"error_count": 1, "skill": "speaking", "score": 75.0},
    )

    await _record_turn_skill_evidence(db_session, [observation], {event_id})
    first = await _score(db_session, test_user.id, ModelSkillType.SPEAKING)
    assert first is not None
    assert first.exercises_completed == 1

    # Redelivery: ingest_observations reports it as a duplicate, so the
    # inserted set is empty and nothing must be scored.
    await _record_turn_skill_evidence(db_session, [observation], set())
    await db_session.refresh(first)
    assert first.exercises_completed == 1


@pytest.mark.asyncio
async def test_observations_without_a_skill_payload_are_ignored(
    db_session: AsyncSession, test_user
):
    event_id = "c" * 64
    await _record_turn_skill_evidence(
        db_session,
        [_observation(test_user.id, event_id=event_id, payload={"error_count": 0})],
        {event_id},
    )

    profile = await db_session.scalar(
        select(UserProficiencyProfile).where(
            UserProficiencyProfile.user_id == test_user.id
        )
    )
    # No profile is even created for a turn that carries no skill evidence.
    assert profile is None


@pytest.mark.asyncio
async def test_unknown_skill_label_is_skipped_not_raised(
    db_session: AsyncSession, test_user
):
    event_id = "d" * 64
    await _record_turn_skill_evidence(
        db_session,
        [
            _observation(
                test_user.id,
                event_id=event_id,
                payload={"error_count": 0, "skill": "vibes", "score": 90.0},
            )
        ],
        {event_id},
    )

    profile = await db_session.scalar(
        select(UserProficiencyProfile).where(
            UserProficiencyProfile.user_id == test_user.id
        )
    )
    assert profile is None


def test_skill_payload_keys_are_accepted_by_the_contract():
    """ai-service sends these; an unlisted key fails the whole batch."""
    assert {"skill", "score", "difficulty_level"} <= ALLOWED_OBSERVATION_PAYLOAD_KEYS
