"""Integration tests: activities outside lessons/games move the CEFR skill scores.

Before this pipeline existed, only lesson and game completion wrote
UserSkillScore, so a learner who reviewed hundreds of flashcards or spoke to
Lexi for an hour still showed zero in every skill but the two those flows
happened to infer.
"""

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.learner_state import LearnerConceptState, LearnerObservationEvent
from app.models.proficiency import SkillType as ModelSkillType
from app.models.proficiency import UserProficiencyProfile, UserSkillScore
from app.models.vocabulary import UserVocabulary, VocabularyItem, VocabularyStatus
from app.routes.proficiency import record_exercise_results_for_user
from app.routes.vocabulary import _record_review_proficiency
from app.schemas.proficiency import ExerciseResult, ProficiencyLevel, SkillType
from app.services.proficiency_service import ProficiencyService


async def _skill_score(
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


async def _seed_user_vocab(db_session: AsyncSession, user_id) -> UserVocabulary:
    vocab_item = VocabularyItem(
        word="Departure Lounge",
        definition="where you wait before a flight",
        part_of_speech="noun",
        difficulty_level="B1",
    )
    db_session.add(vocab_item)
    await db_session.flush()

    user_vocab = UserVocabulary(
        user_id=user_id,
        vocabulary_id=vocab_item.id,
        status=VocabularyStatus.LEARNING,
        next_review_date=datetime.now(UTC) + timedelta(days=1),
    )
    db_session.add(user_vocab)
    await db_session.commit()
    await db_session.refresh(user_vocab)
    return user_vocab


@pytest.mark.asyncio
async def test_flashcard_review_moves_the_vocabulary_skill_score(
    db_session: AsyncSession, test_user
):
    user_vocab = await _seed_user_vocab(db_session, test_user.id)

    await _record_review_proficiency(db_session, test_user, user_vocab, quality=5)

    score = await _skill_score(db_session, test_user.id, ModelSkillType.VOCABULARY)
    assert score is not None
    assert score.score > 0
    assert score.exercises_completed == 1
    assert score.correct_exercises == 1


@pytest.mark.asyncio
async def test_flashcard_review_does_not_award_xp_twice(
    db_session: AsyncSession, test_user
):
    """The route grants XP itself; the proficiency pass must not add more."""
    user_vocab = await _seed_user_vocab(db_session, test_user.id)
    xp_before = test_user.total_xp or 0

    await _record_review_proficiency(db_session, test_user, user_vocab, quality=5)

    assert (test_user.total_xp or 0) == xp_before


@pytest.mark.asyncio
async def test_flashcard_review_does_not_schedule_the_concept_twice(
    db_session: AsyncSession, test_user
):
    """submit_review owns the schedule; the proficiency pass must not re-observe.

    Passing concept_id here would have the same answer counted as two
    separate pieces of spaced-repetition evidence.
    """
    user_vocab = await _seed_user_vocab(db_session, test_user.id)

    await _record_review_proficiency(db_session, test_user, user_vocab, quality=5)

    events = (
        await db_session.scalars(
            select(LearnerObservationEvent).where(
                LearnerObservationEvent.user_id == test_user.id
            )
        )
    ).all()
    assert events == []


@pytest.mark.asyncio
async def test_exercise_with_concept_id_feeds_both_engines(
    db_session: AsyncSession, test_user
):
    """One call updates the CEFR score and the BKT/FSRS schedule together."""
    await record_exercise_results_for_user(
        db_session,
        test_user,
        [
            ExerciseResult(
                exercise_type="pronunciation",
                skill=SkillType.SPEAKING,
                difficulty_level=ProficiencyLevel.B1,
                is_correct=True,
                score=88.0,
                concept_id="vocab:departure_lounge",
            )
        ],
        award_xp=False,
    )

    score = await _skill_score(db_session, test_user.id, ModelSkillType.SPEAKING)
    assert score is not None
    assert score.score > 0

    state = await db_session.scalar(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == test_user.id,
            LearnerConceptState.concept_id == "vocab:departure_lounge",
        )
    )
    assert state is not None
    assert state.attempt_count == 1
    assert state.correct_count == 1


@pytest.mark.asyncio
async def test_exercise_without_concept_id_still_scores_the_skill(
    db_session: AsyncSession, test_user
):
    await record_exercise_results_for_user(
        db_session,
        test_user,
        [
            ExerciseResult(
                exercise_type="news_quiz",
                skill=SkillType.READING,
                difficulty_level=ProficiencyLevel.B2,
                is_correct=False,
                score=40.0,
            )
        ],
        award_xp=False,
    )

    score = await _skill_score(db_session, test_user.id, ModelSkillType.READING)
    assert score is not None
    assert score.exercises_completed == 1
    assert score.correct_exercises == 0

    events = (
        await db_session.scalars(
            select(LearnerObservationEvent).where(
                LearnerObservationEvent.user_id == test_user.id
            )
        )
    ).all()
    assert events == []


def test_lesson_skill_beats_course_skill_beats_tag_guess():
    resolve = ProficiencyService.resolve_lesson_skill

    # Most specific label wins.
    assert resolve("listening", "reading", ["grammar"]) is SkillType.LISTENING
    # Lesson unlabelled: inherit the course.
    assert resolve(None, "reading", ["grammar"]) is SkillType.READING
    # Neither labelled: fall back to the old tag guess.
    assert resolve(None, None, ["grammar"]) is SkillType.GRAMMAR
    # Nothing to go on at all lands on vocabulary, as it always did.
    assert resolve(None, None, None) is SkillType.VOCABULARY
    # A junk label must not shadow a usable one further down the chain.
    assert resolve("not_a_skill", "speaking", None) is SkillType.SPEAKING
    assert resolve("  Writing  ", None, None) is SkillType.WRITING


def test_fill_blank_counts_as_grammar_not_vocabulary():
    """Regression: game_type used to be split on "_" and keyword-matched,
    which scored the grammar question bank as vocabulary."""
    assert ProficiencyService.skill_for_game("fill_blank") is SkillType.GRAMMAR
    assert ProficiencyService.skill_for_game("grammar_quiz") is SkillType.GRAMMAR
    assert ProficiencyService.skill_for_game("spelling_bee") is SkillType.VOCABULARY
    assert ProficiencyService.skill_for_game("hangman") is SkillType.VOCABULARY
    assert ProficiencyService.skill_for_game("word_scramble") is SkillType.VOCABULARY
    assert ProficiencyService.skill_for_game("matching") is SkillType.VOCABULARY
    assert ProficiencyService.skill_for_game(None) is SkillType.VOCABULARY
    assert ProficiencyService.skill_for_game("brand_new_game") is SkillType.VOCABULARY
