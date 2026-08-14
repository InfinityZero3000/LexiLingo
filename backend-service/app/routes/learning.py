"""
Learning Session Routes
Endpoints for lesson attempts and learning sessions (Start/Submit/Complete)
"""

import hashlib
import logging
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from datetime import datetime, timedelta, timezone
from uuid import UUID

from app.core.database import get_db
from app.core.cache import build_cache_key, delete_cached
from app.core.config import settings
from app.core.dependencies import get_current_user
from app.models.learner_state import LearnerObservationEvent
from app.services.learner_state import (
    ObservationInput,
    apply_observation_event,
    ingest_observations,
)
from app.services.streak_service import update_user_streak
from app.models.user import User
from app.models.course import Course, Unit, Lesson
from app.models.progress import (
    UserProgress,
    UserCourseProgress,
    LessonAttempt,
    QuestionAttempt,
    Streak,
    DailyActivity,
    LessonCompletion
)
from app.schemas.progress import (
    LessonStartRequest,
    LessonStartResponse,
    AnswerSubmitRequest,
    AnswerSubmitResponse,
    LessonCompleteRequest,
    LessonCompleteResponse,
    CourseRoadmapResponse,
    UnitProgressRoadmap,
    LessonProgressItem,
)
from app.schemas.course import LessonContentResponse, Exercise, ExerciseOption
from app.schemas.response import ApiResponse
from app.services import check_achievements_for_user
from app.services.proficiency_service import ProficiencyService
from app.schemas.proficiency import ExerciseResult, ProficiencyLevel
from app.routes.proficiency import record_exercise_results_for_user
from app.crud.progress import ProgressCRUD
from app.services.level_service import (
    LevelService,
    calculate_numeric_level,
    check_numeric_level_up
)
from app.services.rank_service import (
    apply_rank_info_to_user,
    calculate_rank as calc_rank
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/learning", tags=["Learning Sessions"])


def _sanitize_lesson_context(value):
    if isinstance(value, dict):
        return {
            key: _sanitize_lesson_context(item)
            for key, item in value.items()
            if key not in {"correct_answer", "is_correct", "answer"}
        }
    if isinstance(value, list):
        return [_sanitize_lesson_context(item) for item in value]
    return value


@router.post("/lessons/{lesson_id}/start", response_model=ApiResponse[LessonStartResponse])
async def start_lesson(
    lesson_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Start a new lesson or resume existing attempt"""
    
    # Check if lesson exists
    result = await db.execute(select(Lesson).where(Lesson.id == lesson_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lesson not found")
    
    # Check for active attempt (not finished)
    result = await db.execute(
        select(LessonAttempt).where(
            and_(
                LessonAttempt.user_id == current_user.id,
                LessonAttempt.lesson_id == lesson_id,
                LessonAttempt.finished_at == None
            )
        )
    )
    existing = result.scalar_one_or_none()
    
    if existing:
        return ApiResponse(
            success=True,
            message="Resumed lesson",
            data=LessonStartResponse(
                attempt_id=existing.id,
                lesson_id=existing.lesson_id,
                started_at=existing.started_at,
                total_questions=existing.total_questions,
                lives_remaining=existing.lives_remaining,
                hints_available=max(
                    0,
                    3 + existing.bonus_hints - existing.hints_used,
                )
            )
        )
    
    # Determine total questions dynamically from lesson content or demo fallback
    total_questions = lesson.exercise_count
    if total_questions == 0:
        if settings.is_production:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "Lesson content is missing exercises",
            )
        total_questions = len(_generate_demo_exercises(lesson.title))

    # Create new attempt
    new_attempt = LessonAttempt(
        user_id=current_user.id,
        lesson_id=lesson_id,
        started_at=datetime.now(timezone.utc),
        total_questions=total_questions,
        lives_remaining=3,
        hints_used=0,
        bonus_hints=0,
        passed=False,
        score=0,
        xp_earned=0,
        time_spent_ms=0,
        correct_answers=0
    )
    
    db.add(new_attempt)
    await db.commit()
    await db.refresh(new_attempt)
    
    return ApiResponse(
        success=True,
        message="Lesson started",
        data=LessonStartResponse(
            attempt_id=new_attempt.id,
            lesson_id=new_attempt.lesson_id,
            started_at=new_attempt.started_at,
            total_questions=new_attempt.total_questions,
            lives_remaining=3,
            hints_available=3
        )
    )


@router.get("/lessons/{lesson_id}/content", response_model=ApiResponse[LessonContentResponse])
async def get_lesson_content(
    lesson_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get lesson content with exercises for learning session"""
    
    # Get lesson
    result = await db.execute(select(Lesson).where(Lesson.id == lesson_id))
    lesson = result.scalar_one_or_none()
    
    if not lesson:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lesson not found")
    
    # Parse exercises from lesson.content (JSON field)
    exercises = []
    if lesson.content and isinstance(lesson.content, dict):
        raw_exercises = lesson.content.get('exercises', [])
        for idx, ex in enumerate(raw_exercises):
            # Parse options if present
            options = None
            if 'options' in ex and ex['options']:
                options = [
                    ExerciseOption(
                        id=str(i),
                        text=opt if isinstance(opt, str) else opt.get('text', ''),
                        is_correct=(opt == ex.get('correct_answer')) if isinstance(opt, str) else opt.get('is_correct', False)
                    )
                    for i, opt in enumerate(ex['options'])
                ]
            
            exercises.append(Exercise(
                id=ex.get('id', str(idx + 1)),
                type=ex.get('type', 'multiple_choice'),
                ui_type=ex.get('ui_type'),
                phase=ex.get('phase'),
                question=ex.get('question', ''),
                options=options,
                correct_answer=str(ex.get('correct_answer', '')),
                explanation=ex.get('explanation'),
                hint=ex.get('hint'),
                audio_url=ex.get('audio_url'),
                image_url=ex.get('image_url'),
                difficulty=ex.get('difficulty', 1),
                points=ex.get('points', 10)
            ))
    
    # If no exercises in DB, generate default exercises for demo
    if not exercises:
        if settings.is_production:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "Lesson content is missing exercises",
            )
        exercises = _generate_demo_exercises(lesson.title)
    
    return ApiResponse(
        success=True,
        message="Lesson content retrieved",
        data=LessonContentResponse(
            id=lesson.id,
            title=lesson.title,
            description=lesson.description,
            outcome=lesson.outcome,
            lesson_type=lesson.lesson_type,
            order_index=lesson.order_index,
            xp_reward=lesson.xp_reward,
            pass_threshold=lesson.pass_threshold,
            estimated_minutes=lesson.estimated_minutes,
            total_exercises=len(exercises),
            exercises=exercises
        )
    )


@router.get("/lessons/{lesson_id}/context")
async def get_lesson_context(
    lesson_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return real lesson context without answer material or demo fallback."""
    result = await db.execute(select(Lesson).where(Lesson.id == lesson_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lesson not found")

    raw_content = lesson.content if isinstance(lesson.content, dict) else {}
    content = _sanitize_lesson_context(raw_content)
    return ApiResponse(
        success=True,
        message="Lesson context retrieved",
        data={
            "id": str(lesson.id),
            "title": lesson.title,
            "description": lesson.description,
            "level": content.get("level"),
            "vocabulary": content.get("vocabulary", []),
            "grammar_points": content.get("grammar_points", []),
            "objectives": content.get("objectives", []),
            "content": content,
            "updated_at": lesson.updated_at.isoformat() if lesson.updated_at else None,
        },
    )


def _generate_demo_exercises(lesson_title: str) -> List[Exercise]:
    """Generate placeholder exercises when DB content is empty.
    Uses lesson title as seed to vary which set is shown per lesson.
    """
    title_hash = sum(ord(c) for c in lesson_title) % 5

    exercise_sets = [
        # Set 0: Grammar-focused
        [
            Exercise(
                id="1", type="multiple_choice", ui_type="multiple_choice",
                question="Choose the correct verb form: 'She ___ to work every day.'",
                options=[
                    ExerciseOption(id="0", text="go", is_correct=False),
                    ExerciseOption(id="1", text="goes", is_correct=True),
                    ExerciseOption(id="2", text="going", is_correct=False),
                    ExerciseOption(id="3", text="gone", is_correct=False),
                ],
                correct_answer="goes",
                explanation="Third-person singular (she/he/it) takes verb+s/es in simple present.",
                difficulty=1, points=10
            ),
            Exercise(
                id="2", type="true_false", ui_type="true_or_false",
                question="'They goes to school' is grammatically correct.",
                options=[ExerciseOption(id="0", text="True", is_correct=False), ExerciseOption(id="1", text="False", is_correct=True)],
                correct_answer="False",
                explanation="'They' is plural and takes the base verb 'go', not 'goes'.",
                difficulty=1, points=10
            ),
            Exercise(
                id="3", type="fill_blank", ui_type="fill_in_the_blank",
                question="Complete: 'I {blank} studying English right now.'",
                correct_answer="am",
                explanation="Present continuous with 'I' uses 'am + verb-ing'.",
                hint="First-person singular form of 'to be'.",
                difficulty=2, points=15
            ),
            Exercise(
                id="4", type="translate", ui_type="translation_choice",
                question="Choose the correct translation: 'Anh ấy là giáo viên.'",
                options=[
                    ExerciseOption(id="0", text="He is a teacher.", is_correct=True),
                    ExerciseOption(id="1", text="She is a teacher.", is_correct=False),
                    ExerciseOption(id="2", text="They are teachers.", is_correct=False),
                ],
                correct_answer="He is a teacher.",
                explanation="'Anh ấy' means 'He' in Vietnamese.",
                difficulty=1, points=10
            ),
            Exercise(
                id="5", type="fill_blank", ui_type="dialogue_completion",
                question="A: Are you a student? B: Yes, I {blank}.",
                correct_answer="am",
                explanation="Short affirmative answer to 'Are you…?' is 'Yes, I am.'",
                difficulty=1, points=10
            ),
        ],
        # Set 1: Vocabulary-focused
        [
            Exercise(
                id="1", type="multiple_choice", ui_type="vocabulary_flashcard",
                question="Learn the word: 'Persevere' (kiên trì)",
                options=[ExerciseOption(id="0", text="Got it!", is_correct=True)],
                correct_answer="Got it!",
                explanation="To persevere means to continue in spite of difficulty.",
                difficulty=1, points=10
            ),
            Exercise(
                id="2", type="matching", ui_type="match_word_to_meaning",
                question="Match the words with their meanings.",
                options=[
                    ExerciseOption(id="0", text="happy"),
                    ExerciseOption(id="1", text="sad"),
                    ExerciseOption(id="2", text="vui vẻ"),
                    ExerciseOption(id="3", text="buồn bã"),
                ],
                correct_answer="happy:vui vẻ, sad:buồn bã",
                explanation="Happy = vui vẻ, Sad = buồn bã in Vietnamese.",
                difficulty=1, points=10
            ),
            Exercise(
                id="3", type="fill_blank", ui_type="fill_in_the_blank",
                question="Complete: 'The {blank} of a word tells you its meaning.'",
                correct_answer="definition",
                explanation="A definition explains what a word means.",
                hint="This is what you find in a dictionary.",
                difficulty=2, points=15
            ),
            Exercise(
                id="4", type="true_false", ui_type="true_or_false",
                question="'Enormous' and 'huge' are synonyms.",
                options=[ExerciseOption(id="0", text="True", is_correct=True), ExerciseOption(id="1", text="False", is_correct=False)],
                correct_answer="True",
                explanation="Both 'enormous' and 'huge' mean very large in size.",
                difficulty=1, points=10
            ),
            Exercise(
                id="5", type="multiple_choice", ui_type="collocation_choice",
                question="Complete the phrase: '___ a decision'",
                options=[
                    ExerciseOption(id="0", text="make", is_correct=True),
                    ExerciseOption(id="1", text="do", is_correct=False),
                    ExerciseOption(id="2", text="take", is_correct=False),
                ],
                correct_answer="make",
                explanation="The correct collocation is 'make a decision'.",
                difficulty=2, points=15
            ),
        ],
        # Set 2: Listening / Pronunciation focused
        [
            Exercise(
                id="1", type="multiple_choice", ui_type="multiple_choice",
                question="Which word has a different vowel sound? 'cat / bat / care / hat'",
                options=[
                    ExerciseOption(id="0", text="cat", is_correct=False),
                    ExerciseOption(id="1", text="bat", is_correct=False),
                    ExerciseOption(id="2", text="care", is_correct=True),
                    ExerciseOption(id="3", text="hat", is_correct=False),
                ],
                correct_answer="care",
                explanation="'care' has the /eər/ sound; the others have the short /æ/ vowel sound.",
                difficulty=2, points=15
            ),
            Exercise(
                id="2", type="translate", ui_type="speaking_repeat",
                question="Repeat the sentence: 'Could you please speak more slowly?'",
                correct_answer="Could you please speak more slowly",
                explanation="Practice clear pronunciation of polite requests.",
                difficulty=2, points=15
            ),
            Exercise(
                id="3", type="fill_blank", ui_type="dictation",
                question="Listen and write: '{blank}'",
                correct_answer="Nice to meet you",
                explanation="A common phrase when meeting someone for the first time.",
                difficulty=1, points=10
            ),
            Exercise(
                id="4", type="true_false", ui_type="true_or_false",
                question="In English, the letter 'c' always sounds like /k/.",
                options=[ExerciseOption(id="0", text="True", is_correct=False), ExerciseOption(id="1", text="False", is_correct=True)],
                correct_answer="False",
                explanation="'c' can sound like /s/ (as in 'city') or /k/ (as in 'cat').",
                difficulty=2, points=15
            ),
            Exercise(
                id="5", type="translate", ui_type="pronunciation_practice",
                question="Practice pronouncing: 'I would like a cup of coffee, please.'",
                correct_answer="I would like a cup of coffee please",
                explanation="Focus on linking words naturally in natural speech.",
                difficulty=2, points=15
            ),
        ],
        # Set 3: Reading / Writing focused
        [
            Exercise(
                id="1", type="multiple_choice", ui_type="reading_comprehension",
                question="Read and answer: 'Anna wakes up at 7am. She has breakfast and then goes to work.' What does Anna do first after waking up?",
                options=[
                    ExerciseOption(id="0", text="Goes to work", is_correct=False),
                    ExerciseOption(id="1", text="Has breakfast", is_correct=True),
                    ExerciseOption(id="2", text="Takes a shower", is_correct=False),
                ],
                correct_answer="Has breakfast",
                explanation="The text states she has breakfast before going to work.",
                difficulty=1, points=10
            ),
            Exercise(
                id="2", type="fill_blank", ui_type="short_writing_answer",
                question="Write a sentence using the word 'however' to contrast two ideas.",
                correct_answer="However",
                explanation="'However' is used to introduce a contrast or opposing point.",
                hint="Start your sentence with 'However,'",
                difficulty=3, points=20
            ),
            Exercise(
                id="3", type="multiple_choice", ui_type="multiple_choice",
                question="Which linking word shows contrast?",
                options=[
                    ExerciseOption(id="0", text="therefore", is_correct=False),
                    ExerciseOption(id="1", text="furthermore", is_correct=False),
                    ExerciseOption(id="2", text="however", is_correct=True),
                    ExerciseOption(id="3", text="consequently", is_correct=False),
                ],
                correct_answer="however",
                explanation="'However' introduces a contrasting idea, unlike 'therefore' (result) or 'furthermore' (addition).",
                difficulty=2, points=15
            ),
            Exercise(
                id="4", type="fill_blank", ui_type="grammar_correction",
                question="Correct the error: 'He don't like coffee.' → '{blank}'",
                correct_answer="He doesn't like coffee",
                explanation="Third-person singular negative uses 'doesn't' (does not), not 'don't'.",
                difficulty=2, points=15
            ),
            Exercise(
                id="5", type="reorder", ui_type="arrange_the_sentence",
                question="Arrange: 'morning / every / reads / she / the / newspaper'",
                options=[
                    ExerciseOption(id="0", text="she"),
                    ExerciseOption(id="1", text="reads"),
                    ExerciseOption(id="2", text="the"),
                    ExerciseOption(id="3", text="newspaper"),
                    ExerciseOption(id="4", text="every"),
                    ExerciseOption(id="5", text="morning"),
                ],
                correct_answer="she reads the newspaper every morning",
                explanation="Standard word order: Subject + Verb + Object + Time.",
                difficulty=2, points=15
            ),
        ],
        # Set 4: Conversation / Communication focused
        [
            Exercise(
                id="1", type="fill_blank", ui_type="dialogue_completion",
                question="A: What do you do for a living? B: I {blank} as an engineer.",
                correct_answer="work",
                explanation="'Work as + profession' is the standard pattern for talking about your job.",
                difficulty=1, points=10
            ),
            Exercise(
                id="2", type="multiple_choice", ui_type="multiple_choice",
                question="Which response is most polite when someone thanks you?",
                options=[
                    ExerciseOption(id="0", text="Yeah, whatever.", is_correct=False),
                    ExerciseOption(id="1", text="You're welcome!", is_correct=True),
                    ExerciseOption(id="2", text="I know.", is_correct=False),
                    ExerciseOption(id="3", text="So what?", is_correct=False),
                ],
                correct_answer="You're welcome!",
                explanation="'You're welcome!' is the standard polite response to 'Thank you'.",
                difficulty=1, points=10
            ),
            Exercise(
                id="3", type="matching", ui_type="categorization",
                question="Categorize: formal vs informal greetings",
                options=[
                    ExerciseOption(id="0", text="Good morning"),
                    ExerciseOption(id="1", text="Hey!"),
                    ExerciseOption(id="2", text="Formal"),
                    ExerciseOption(id="3", text="Informal"),
                ],
                correct_answer="Good morning:Formal, Hey!:Informal",
                explanation="'Good morning' is formal; 'Hey!' is informal/casual.",
                difficulty=1, points=10
            ),
            Exercise(
                id="4", type="true_false", ui_type="true_or_false",
                question="'Could you help me?' is more polite than 'Help me!'",
                options=[ExerciseOption(id="0", text="True", is_correct=True), ExerciseOption(id="1", text="False", is_correct=False)],
                correct_answer="True",
                explanation="Using 'Could you…?' adds politeness and formality compared to a direct command.",
                difficulty=1, points=10
            ),
            Exercise(
                id="5", type="fill_blank", ui_type="fill_in_the_blank",
                question="Complete: 'I'm {blank} to hear that.' (expressing sympathy)",
                correct_answer="sorry",
                explanation="'I'm sorry to hear that' is a standard expression of sympathy.",
                hint="This word expresses regret or sympathy.",
                difficulty=1, points=10
            ),
        ],
    ]

    return exercise_sets[title_hash]


@router.post("/attempts/{attempt_id}/answer", response_model=ApiResponse[AnswerSubmitResponse])
async def submit_answer(
    attempt_id: UUID,
    request: AnswerSubmitRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Submit answer for a question"""
    
    # Get attempt
    result = await db.execute(
        select(LessonAttempt).where(
            and_(
                LessonAttempt.id == attempt_id,
                LessonAttempt.user_id == current_user.id
            )
        )
    )
    attempt = result.scalar_one_or_none()
    
    if not attempt:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Attempt not found")
    if attempt.finished_at is not None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Lesson completed")
    
    # Get lesson to validate answer
    lesson_result = await db.execute(select(Lesson).where(Lesson.id == attempt.lesson_id))
    lesson = lesson_result.scalar_one_or_none()
    
    # Validate answer against lesson content
    is_correct, correct_answer, explanation, concept_id = await _validate_answer(
        lesson=lesson,
        question_id=str(request.question_id),
        question_type=request.question_type.value,
        user_answer=request.user_answer
    )

    if concept_id:
        await _emit_concept_observation(
            db,
            user_id=current_user.id,
            concept_id=concept_id,
            is_correct=is_correct,
        )

    # Calculate XP based on correctness, hint usage, and time
    xp = 10 if is_correct else 0
    if request.hint_used:
        xp = max(0, xp - 3)
    # Bonus XP for fast answers (under 10 seconds)
    if is_correct and request.time_spent_ms < 10000:
        xp += 2
    
    # Record question attempt
    import json
    qa = QuestionAttempt(
        lesson_attempt_id=attempt_id,
        question_id=str(request.question_id),
        question_type=request.question_type.value,
        user_answer=json.dumps(request.user_answer) if isinstance(request.user_answer, dict) else str(request.user_answer),
        is_correct=is_correct,
        time_spent_ms=request.time_spent_ms,
        hint_used=request.hint_used,
        confidence_score=request.confidence_score
    )
    db.add(qa)
    
    # Update attempt
    if is_correct:
        attempt.correct_answers += 1
    else:
        attempt.lives_remaining = max(0, attempt.lives_remaining - 1)
    
    if request.hint_used:
        attempt.hints_used += 1
    
    attempt.score = int((attempt.correct_answers / attempt.total_questions) * 100)
    attempt.xp_earned += xp
    attempt.time_spent_ms += request.time_spent_ms
    
    await db.commit()
    await db.refresh(qa)
    
    return ApiResponse(
        success=True,
        message="Correct! Well done!" if is_correct else "Incorrect. Keep trying!",
        data=AnswerSubmitResponse(
            question_attempt_id=qa.id,
            is_correct=is_correct,
            correct_answer=correct_answer if not is_correct else None,
            explanation=explanation,
            xp_earned=xp,
            lives_remaining=attempt.lives_remaining,
            hints_remaining=max(
                0,
                3 + attempt.bonus_hints - attempt.hints_used,
            ),
            current_score=float(attempt.score)
        )
    )


async def _emit_concept_observation(
    db: AsyncSession,
    *,
    user_id: UUID,
    concept_id: str,
    is_correct: bool,
) -> None:
    """Feed a lesson-exercise answer into the unified learner_concept_state
    engine (same one vocabulary review uses — app/crud/vocabulary.py
    submit_review). Applied synchronously in this request's transaction so
    mastery is immediately queryable, not just eventually via the outbox
    worker. Best-effort: any failure here must never break answer submission."""
    now = datetime.now(timezone.utc)
    event_id = hashlib.sha256(
        f"{user_id}:{concept_id}:{now.isoformat()}".encode("utf-8")
    ).hexdigest()
    try:
        # SAVEPOINT: a failure here must roll back only this observation,
        # not abort the outer transaction that still needs to persist the
        # QuestionAttempt/lesson-progress writes that follow in the caller.
        async with db.begin_nested():
            await ingest_observations(
                db,
                [
                    ObservationInput(
                        event_id=event_id,
                        user_id=user_id,
                        concept_id=concept_id,
                        outcome="correct" if is_correct else "incorrect",
                        confidence=0.8,
                        observed_at=now,
                    )
                ],
            )
            event_db_id = await db.scalar(
                select(LearnerObservationEvent.id).where(
                    LearnerObservationEvent.event_id == event_id
                )
            )
            if event_db_id is not None:
                await apply_observation_event(db, event_db_id, now=now)
    except Exception:
        logger.exception(
            "Failed to record concept observation for user=%s concept=%s",
            user_id,
            concept_id,
        )


async def _validate_answer(
    lesson: Optional[Lesson],
    question_id: str,
    question_type: str,
    user_answer: any
) -> tuple[bool, str, str, Optional[str]]:
    """
    Validate user answer against lesson content.
    Returns (is_correct, correct_answer, explanation, concept_id)
    """
    correct_answer = ""
    explanation = "Keep practicing!"

    # Try to find the exercise in lesson content
    if lesson and lesson.content and isinstance(lesson.content, dict):
        exercises = lesson.content.get('exercises', [])
        for ex in exercises:
            if str(ex.get('id', '')) == question_id:
                correct_answer = str(ex.get('correct_answer', ''))
                explanation = ex.get('explanation', 'Check the correct answer and try again.')

                is_correct = _answers_match(
                    user_answer,
                    correct_answer,
                    question_type,
                    ex.get("ui_type"),
                )
                return is_correct, correct_answer, explanation, ex.get("concept_id")

    # Fallback: look up in the dynamic demo exercise set for this lesson
    if lesson and not settings.is_production:
        demo_ex_list = _generate_demo_exercises(lesson.title)
        for demo_ex in demo_ex_list:
            if demo_ex.id == question_id:
                correct_answer = demo_ex.correct_answer
                explanation = demo_ex.explanation or "Check the correct answer and try again."
                is_correct = _answers_match(
                    user_answer,
                    correct_answer,
                    question_type,
                    demo_ex.ui_type,
                )
                return is_correct, correct_answer, explanation, None

    # Last resort: direct comparison
    is_correct = _normalize_answer(user_answer, question_type) == _normalize_answer(correct_answer, question_type)
    return is_correct, correct_answer, explanation, None


async def _find_next_lesson(db: AsyncSession, current_lesson: Lesson) -> Optional[UUID]:
    """Return the UUID of the next lesson after current_lesson.

    Checks same-unit lessons by order_index first, then falls back to the
    first lesson of the next unit (ordered by order_index).
    """
    unit_result = await db.execute(select(Unit).where(Unit.id == current_lesson.unit_id))
    unit = unit_result.scalar_one_or_none()
    if not unit:
        return None

    next_in_unit = await db.execute(
        select(Lesson)
        .where(
            and_(
                Lesson.unit_id == unit.id,
                Lesson.order_index > current_lesson.order_index,
            )
        )
        .order_by(Lesson.order_index)
        .limit(1)
    )
    nxt = next_in_unit.scalar_one_or_none()
    if nxt:
        return nxt.id

    next_unit = await db.execute(
        select(Unit)
        .where(
            and_(
                Unit.course_id == unit.course_id,
                Unit.order_index > unit.order_index,
            )
        )
        .order_by(Unit.order_index)
        .limit(1)
    )
    nu = next_unit.scalar_one_or_none()
    if not nu:
        return None

    first_in_next = await db.execute(
        select(Lesson)
        .where(Lesson.unit_id == nu.id)
        .order_by(Lesson.order_index)
        .limit(1)
    )
    first = first_in_next.scalar_one_or_none()
    return first.id if first else None


def _normalize_answer(answer: any, question_type: str) -> str:
    """Normalize answer for comparison"""
    if answer is None:
        return ""
    
    # Convert to string
    ans_str = str(answer).strip().lower()
    
    # Handle matching/categorization pairs normalization by sorting
    if question_type == 'matching' or (':' in ans_str and (',' in ans_str or len(ans_str.split(':')) > 2)):
        try:
            pairs = []
            for part in ans_str.split(','):
                if ':' in part:
                    k, v = part.split(':', 1)
                    pairs.append((k.strip(), v.strip()))
            pairs.sort()
            return ', '.join(f"{k}:{v}" for k, v in pairs)
        except Exception:
            pass

    # Remove punctuation for certain types
    if question_type in ['fill_blank', 'translate']:
        import re
        ans_str = re.sub(r'[^\w\s]', '', ans_str)
    
    # Handle boolean types
    if question_type == 'true_false':
        if ans_str in ['true', 'yes', '1', 'đúng']:
            return 'true'
        elif ans_str in ['false', 'no', '0', 'sai']:
            return 'false'
    
    return ans_str


def _answers_match(
    user_answer: any,
    correct_answer: any,
    question_type: str,
    ui_type: Optional[str] = None,
) -> bool:
    if str(ui_type or "").lower() in {
        "speaking_repeat",
        "pronunciation_practice",
    }:
        return _speaking_answers_match(user_answer, correct_answer)

    return _normalize_answer(user_answer, question_type) == _normalize_answer(
        correct_answer,
        question_type,
    )


def _speaking_answers_match(
    user_answer: any,
    correct_answer: any,
    approval_threshold: float = 0.85,
) -> bool:
    user_normalized = _normalize_answer(user_answer, "translate")
    correct_normalized = _normalize_answer(correct_answer, "translate")
    if not user_normalized or not correct_normalized:
        return False

    similarity = _text_similarity(user_normalized, correct_normalized)
    return similarity >= approval_threshold


def _text_similarity(first: str, second: str) -> float:
    if first == second:
        return 1.0 if first else 0.0
    if not first or not second:
        return 0.0

    previous = list(range(len(second) + 1))
    for first_index, first_character in enumerate(first):
        current = [first_index + 1]
        for second_index, second_character in enumerate(second):
            substitution_cost = 0 if first_character == second_character else 1
            current.append(
                min(
                    current[second_index] + 1,
                    previous[second_index + 1] + 1,
                    previous[second_index] + substitution_cost,
                )
            )
        previous = current

    longest_length = max(len(first), len(second))
    return (longest_length - previous[-1]) / longest_length


@router.post("/attempts/{attempt_id}/complete", response_model=ApiResponse[LessonCompleteResponse])
async def complete_lesson(
    attempt_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Complete lesson attempt"""
    
    result = await db.execute(
        select(LessonAttempt).where(
            and_(
                LessonAttempt.id == attempt_id,
                LessonAttempt.user_id == current_user.id
            )
        )
    )
    attempt = result.scalar_one_or_none()
    
    if not attempt:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Attempt not found")
    if attempt.finished_at is not None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Already completed")
    
    # Get lesson info for course_id
    result = await db.execute(select(Lesson).where(Lesson.id == attempt.lesson_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lesson not found")
    
    # Complete
    attempt.finished_at = datetime.now(timezone.utc)
    pass_threshold = lesson.pass_threshold or 80.0
    attempt.passed = attempt.score >= pass_threshold
    
    # Stars
    if attempt.score >= 90:
        stars = 3
    elif attempt.score >= 80:
        stars = 2
    elif attempt.score >= 70:
        stars = 1
    else:
        stars = 0
    
    # Update UserProgress
    result = await db.execute(
        select(UserProgress).where(
            and_(
                UserProgress.user_id == current_user.id,
                UserProgress.lesson_id == attempt.lesson_id
            )
        )
    )
    progress = result.scalar_one_or_none()
    
    if not progress:
        progress = UserProgress(
            user_id=current_user.id,
            lesson_id=attempt.lesson_id,
            course_id=lesson.course_id,
            status="completed" if attempt.passed else "in_progress",
            score=attempt.score,
            completed_at=datetime.now(timezone.utc) if attempt.passed else None,
            time_spent_seconds=attempt.time_spent_ms // 1000,
            attempts=1
        )
        db.add(progress)
    else:
        if attempt.passed:
            progress.status = "completed"
            progress.completed_at = datetime.now(timezone.utc)
        progress.score = max(progress.score, attempt.score)
        progress.time_spent_seconds += attempt.time_spent_ms // 1000
        progress.attempts += 1
    
    # Update LessonCompletion (Phase 3 completion table)
    lesson_completion, xp_earned_first_time = await ProgressCRUD.mark_lesson_complete(
        db,
        str(current_user.id),
        str(attempt.lesson_id),
        float(attempt.score),
        pass_threshold
    )
    
    # Decide performance-based XP to award for first-time pass
    xp_to_award = 0
    if attempt.passed and xp_earned_first_time > 0:
        xp_to_award = attempt.xp_earned or lesson.xp_reward or 0
        
    # Recalculate and update course progress percentage
    new_progress = await ProgressCRUD.calculate_course_progress(
        db, str(current_user.id), str(lesson.course_id)
    )
    course_progress = await ProgressCRUD.update_course_progress(
        db,
        str(current_user.id),
        str(lesson.course_id),
        new_progress,
        xp_to_award
    )
    
    # --- Update User.total_xp and level/rank services ---
    if xp_to_award > 0:
        old_xp = current_user.total_xp or 0
        new_xp = old_xp + xp_to_award
        current_user.total_xp = new_xp
        
        # Update numeric level
        new_numeric_level = calculate_numeric_level(new_xp)
        current_user.numeric_level = new_numeric_level
        
        # Check CEFR tier change
        tier_up, _ = LevelService.check_level_up(old_xp, new_xp)
        if tier_up:
            cefr_status = LevelService.calculate_level_status(new_xp)
            current_user.level = cefr_status.current_tier.code
        
        # Check numeric level up
        leveled, _, _ = check_numeric_level_up(old_xp, new_xp)
        
        # Check rank change
        new_rank_info = calc_rank(new_numeric_level, current_user.level)
        apply_rank_info_to_user(current_user, new_rank_info)
        
        # --- Update DailyActivity ---
        from datetime import date as date_type
        today = date_type.today()
        daily_result = await db.execute(
            select(DailyActivity).where(
                and_(
                    DailyActivity.user_id == current_user.id,
                    DailyActivity.activity_date == today,
                )
            )
        )
        daily_activity = daily_result.scalar_one_or_none()
        
        if daily_activity:
            daily_activity.xp_earned = (daily_activity.xp_earned or 0) + xp_to_award
            daily_activity.lessons_completed = (daily_activity.lessons_completed or 0) + 1
        else:
            daily_activity = DailyActivity(
                user_id=current_user.id,
                activity_date=today,
                xp_earned=xp_to_award,
                lessons_completed=1,
            )
            db.add(daily_activity)
    elif attempt.passed:
        # If passed but no new XP was awarded (already passed before),
        # still increment completed lessons in DailyActivity for active engagement.
        from datetime import date as date_type
        today = date_type.today()
        daily_result = await db.execute(
            select(DailyActivity).where(
                and_(
                    DailyActivity.user_id == current_user.id,
                    DailyActivity.activity_date == today,
                )
            )
        )
        daily_activity = daily_result.scalar_one_or_none()
        
        if daily_activity:
            daily_activity.lessons_completed = (daily_activity.lessons_completed or 0) + 1
        else:
            daily_activity = DailyActivity(
                user_id=current_user.id,
                activity_date=today,
                xp_earned=0,
                lessons_completed=1,
            )
            db.add(daily_activity)
            
    # Update streak
    await update_user_streak(db, current_user.id)
    
    # Check achievements after lesson completion
    unlocked_achievements = []
    try:
        unlocked_achievements = await check_achievements_for_user(
            db, current_user.id, "lesson_complete"
        )
        # Also check XP-based achievements
        xp_achievements = await check_achievements_for_user(
            db, current_user.id, "xp_earned"
        )
        unlocked_achievements.extend(xp_achievements)
        
        # Check for perfect score achievements
        if attempt.score == 100:
            perfect_achievements = await check_achievements_for_user(
                db, current_user.id, "quiz_complete"
            )
            unlocked_achievements.extend(perfect_achievements)
    except Exception as e:
        # Don't fail the lesson completion if achievement check fails
        logger.warning("Achievement check error: %s", e)
    
    await db.commit()

    # CEFR proficiency tracking: one aggregate ExerciseResult per completed
    # lesson. Best-effort — a failure here must not fail the lesson the
    # user just finished. complete_lesson's own "Already completed" guard
    # above (finished_at check) is the idempotency boundary: this only
    # runs once per attempt.
    try:
        course_result = await db.execute(
            select(Course).where(Course.id == lesson.course_id)
        )
        course = course_result.scalar_one_or_none()
        if course and course.level in {lvl.value for lvl in ProficiencyLevel}:
            await record_exercise_results_for_user(
                db,
                current_user,
                [
                    ExerciseResult(
                        exercise_type="lesson",
                        skill=ProficiencyService.infer_skill_from_tags(course.tags),
                        difficulty_level=ProficiencyLevel(course.level),
                        is_correct=attempt.passed,
                        score=float(attempt.score),
                        time_spent_seconds=attempt.time_spent_ms // 1000,
                        lesson_id=str(attempt.lesson_id),
                        course_id=str(lesson.course_id),
                    )
                ],
                award_xp=False,  # lesson completion above already awarded XP
            )
    except Exception as e:
        logger.warning("Proficiency update error: %s", e)

    await delete_cached(build_cache_key("achievements_me", user_id=str(current_user.id)))
    await delete_cached(build_cache_key("wallet", user_id=str(current_user.id)))
    await delete_cached(build_cache_key("progress_me", user_id=str(current_user.id)))
    await delete_cached(build_cache_key("progress_xp", user_id=str(current_user.id)))
    await delete_cached(build_cache_key("progress_streak", user_id=str(current_user.id)))

    time_sec = attempt.time_spent_ms // 1000
    accuracy = (attempt.correct_answers / attempt.total_questions * 100) if attempt.total_questions > 0 else 0

    next_lesson_id = None
    if attempt.passed:
        next_lesson_id = await _find_next_lesson(db, lesson)

    return ApiResponse(
        success=True,
        message="Congratulations!" if attempt.passed else "Keep practicing!",
        data=LessonCompleteResponse(
            attempt_id=attempt.id,
            passed=attempt.passed,
            final_score=attempt.score,
            total_xp_earned=attempt.xp_earned,
            time_spent_seconds=time_sec,
            accuracy=accuracy,
            stars_earned=stars,
            next_lesson_unlocked=next_lesson_id,
            # check_achievements_for_user returns rich dicts (id, name, badge…)
            # but both this schema and the Flutter model expect bare ids. Passing
            # the dicts raised ValidationError, so completing a lesson 500'd for
            # any learner who actually unlocked something — the reward moment.
            achievements_unlocked=[a["id"] for a in unlocked_achievements],
            total_questions=attempt.total_questions,
            correct_answers=attempt.correct_answers,
            wrong_answers=attempt.total_questions - attempt.correct_answers,
            hints_used=attempt.hints_used
        )
    )


@router.get("/courses/{course_id}/roadmap", response_model=ApiResponse[CourseRoadmapResponse])
async def get_course_roadmap(
    course_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get course roadmap for UI visualization"""
    
    # Get course with units and lessons
    result = await db.execute(
        select(Course)
        .options(selectinload(Course.units).selectinload(Unit.lessons))
        .where(Course.id == course_id)
    )
    course = result.scalar_one_or_none()
    
    if not course:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Course not found")
    
    # Lessons whose content has no exercises are not playable (start/content
    # both reject them) — hide them so they can't dead-end the unlock chain.
    playable_lessons = {
        unit.id: sorted(
            (lesson for lesson in unit.lessons if lesson.exercise_count > 0),
            key=lambda lesson: lesson.order_index,
        )
        for unit in course.units
    }

    # Get progress for all lessons
    lesson_ids = [
        lesson.id for lessons in playable_lessons.values() for lesson in lessons
    ]
    result = await db.execute(
        select(UserProgress).where(
            and_(
                UserProgress.user_id == current_user.id,
                UserProgress.lesson_id.in_(lesson_ids)
            )
        )
    )
    progress_map = {p.lesson_id: p for p in result.scalars().all()}
    
    # Get streak
    result = await db.execute(select(Streak).where(Streak.user_id == current_user.id))
    streak = result.scalar_one_or_none()
    current_streak = streak.current_streak if streak else 0

    # Get total XP earned for this course
    cp_result = await db.execute(
        select(UserCourseProgress).where(
            and_(
                UserCourseProgress.user_id == current_user.id,
                UserCourseProgress.course_id == course_id,
            )
        )
    )
    course_progress = cp_result.scalar_one_or_none()
    total_xp_earned = course_progress.total_xp_earned if course_progress else 0

    # Build roadmap
    units_roadmap = []
    completed_units = 0
    completed_lessons_count = 0

    sorted_units = [
        unit
        for unit in sorted(course.units, key=lambda unit: unit.order_index)
        if playable_lessons[unit.id]
    ]
    for unit_number, unit in enumerate(sorted_units, start=1):
        lessons_items = []
        unit_completed = 0

        sorted_lessons = playable_lessons[unit.id]
        for lesson_index, lesson in enumerate(sorted_lessons):
            progress = progress_map.get(lesson.id)

            previous_lesson = (
                sorted_lessons[lesson_index - 1]
                if lesson_index > 0
                else None
            )
            previous_progress = (
                progress_map.get(previous_lesson.id)
                if previous_lesson
                else None
            )
            is_locked = previous_lesson is not None and not (
                previous_progress and previous_progress.status == "completed"
            )

            is_completed = (progress.status == "completed") if progress else False
            if is_completed:
                unit_completed += 1
                completed_lessons_count += 1

            is_current = not is_locked and not is_completed

            lesson_item = LessonProgressItem(
                lesson_id=lesson.id,
                lesson_number=lesson_index + 1,
                title=lesson.title,
                description=lesson.description,
                is_locked=is_locked,
                is_current=is_current,
                is_completed=is_completed,
                best_score=progress.score if progress else None,
                stars_earned=_calc_stars(progress.score) if progress and progress.score else 0,
                attempts_count=progress.attempts if progress else 0,
                completion_percentage=100.0 if is_completed else 0.0,
                icon_url=None,  # Lesson model doesn't have icon_url
                background_color="#4CAF50" if is_completed else "#9E9E9E" if is_locked else "#2196F3"
            )
            lessons_items.append(lesson_item)

        unit_comp = (
            unit_completed / len(sorted_lessons) * 100
            if sorted_lessons
            else 0
        )
        is_unit_current = any(l.is_current for l in lessons_items)

        if unit_comp >= 100:
            completed_units += 1

        unit_roadmap = UnitProgressRoadmap(
            unit_id=unit.id,
            unit_number=unit_number,
            title=unit.title,
            description=unit.description,
            total_lessons=len(sorted_lessons),
            completed_lessons=unit_completed,
            completion_percentage=unit_comp,
            is_current=is_unit_current,
            lessons=lessons_items,
            icon_url=unit.icon_url,
            background_color=unit.background_color or "#2196F3"
        )
        units_roadmap.append(unit_roadmap)
    
    total_lessons = len(lesson_ids)
    overall_comp = (completed_lessons_count / total_lessons * 100) if total_lessons > 0 else 0
    
    return ApiResponse(
        success=True,
        message="Roadmap retrieved",
        data=CourseRoadmapResponse(
            course_id=course.id,
            course_title=course.title,
            level=course.level,
            total_units=len(sorted_units),
            completed_units=completed_units,
            total_lessons=total_lessons,
            completed_lessons=completed_lessons_count,
            completion_percentage=overall_comp,
            total_xp_earned=total_xp_earned,
            current_streak=current_streak,
            units=units_roadmap
        )
    )


def _calc_stars(score: float) -> int:
    """Calculate stars"""
    if score >= 90:
        return 3
    elif score >= 80:
        return 2
    elif score >= 70:
        return 1
    return 0
