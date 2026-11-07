"""A formal test result is a floor: later activity may raise the level, never erase it."""


from unittest.mock import patch

from sqlalchemy import select

from app.models.proficiency import UserProficiencyProfile
from app.models.vocabulary import UserVocabulary, VocabularyItem
from app.routes.proficiency import record_exercise_results_for_user
from app.schemas.proficiency import ExerciseResult, ProficiencyLevel, SkillType
from app.services.proficiency_service import ProficiencyService
from app.services.rank_service import calculate_rank


def _overall(floor):
    return ProficiencyService.calculate_overall_level(
        skill_scores={SkillType.VOCABULARY: 10.0},
        exercises_completed=1,
        lessons_completed=0,
        accuracy=1.0,
        skill_confidences={SkillType.VOCABULARY: 0.02},
        floor=floor,
    )[0]


def test_floor_holds_when_evidence_is_weak():
    assert _overall(None) == ProficiencyLevel.A1
    assert _overall(ProficiencyLevel.B2) == ProficiencyLevel.B2


def test_floor_never_lowers_a_level_evidence_already_reached():
    assert _overall(ProficiencyLevel.A1) == ProficiencyLevel.A1


async def _place(db_session, user, level):
    user.level = level
    profile = UserProficiencyProfile(
        user_id=user.id, assessed_level=level, placement_level=level
    )
    db_session.add(profile)
    await db_session.commit()
    return profile


async def test_next_lesson_does_not_erase_placement(db_session, test_user):
    await _place(db_session, test_user, "B2")

    await record_exercise_results_for_user(
        db_session,
        test_user,
        [
            ExerciseResult(
                exercise_type="multiple_choice",
                skill=SkillType.VOCABULARY,
                difficulty_level=ProficiencyLevel.A1,
                is_correct=True,
                score=100,
            )
        ],
    )

    await db_session.refresh(test_user)
    profile = (
        await db_session.execute(
            select(UserProficiencyProfile).where(UserProficiencyProfile.user_id == test_user.id)
        )
    ).scalar_one()
    assert profile.assessed_level == "B2"
    assert test_user.level == "B2"


async def test_vocabulary_review_leaves_cefr_level_alone(
    db_session, test_user, async_client, auth_headers
):
    await _place(db_session, test_user, "B2")
    item = VocabularyItem(
        word="alpha", definition="first", part_of_speech="noun", difficulty_level="A1"
    )
    db_session.add(item)
    await db_session.commit()
    uv = UserVocabulary(user_id=test_user.id, vocabulary_id=item.id)
    db_session.add(uv)
    await db_session.commit()

    response = await async_client.post(
        f"/api/v1/vocabulary/review/{uv.id}",
        json={"quality": 4, "time_spent_ms": 1000},
        headers=auth_headers,
    )

    assert response.status_code == 200, response.text
    await db_session.refresh(test_user)
    assert test_user.level == "B2"


async def test_no_route_lets_a_client_claim_an_exam_pass(
    db_session, test_user, async_client, auth_headers
):
    # passed/score were client-supplied; nothing on the server graded them.
    response = await async_client.post(
        "/api/v1/proficiency/exam-gated/submit",
        json={"exam_level": "A2", "passed": True, "score": 100},
        headers=auth_headers,
    )

    assert response.status_code in (404, 405)


async def test_rank_is_recomputed_when_users_level_drifts_from_profile(db_session, test_user):
    test_user.level = "B1"
    db_session.add(UserProficiencyProfile(user_id=test_user.id, assessed_level="A1"))
    await db_session.commit()

    with patch("app.routes.proficiency.calculate_rank", wraps=calculate_rank) as spy:
        await record_exercise_results_for_user(
            db_session,
            test_user,
            [
                ExerciseResult(
                    exercise_type="multiple_choice",
                    skill=SkillType.VOCABULARY,
                    difficulty_level=ProficiencyLevel.A1,
                    is_correct=True,
                    score=100,
                )
            ],
        )

    assert test_user.level == "A1"
    spy.assert_called_once()
    assert spy.call_args.kwargs["proficiency_level"] == "A1"
