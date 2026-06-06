"""
Learning Session Routes
Endpoints for lesson attempts and learning sessions (Start/Submit/Complete)
"""

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
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.course import Course, Unit, Lesson
from app.models.progress import (
    UserProgress,
    LessonAttempt,
    QuestionAttempt,
    Streak
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

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/learning", tags=["Learning Sessions"])


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
    
    # Create new attempt
    new_attempt = LessonAttempt(
        user_id=current_user.id,
        lesson_id=lesson_id,
        started_at=datetime.now(timezone.utc),
        total_questions=10,  # TODO: Get from lesson content
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
        exercises = _generate_demo_exercises(lesson.title)
    
    return ApiResponse(
        success=True,
        message="Lesson content retrieved",
        data=LessonContentResponse(
            id=lesson.id,
            title=lesson.title,
            description=lesson.description,
            lesson_type=lesson.lesson_type,
            order_index=lesson.order_index,
            xp_reward=lesson.xp_reward,
            pass_threshold=lesson.pass_threshold,
            estimated_minutes=lesson.estimated_minutes,
            total_exercises=len(exercises),
            exercises=exercises
        )
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
    is_correct, correct_answer, explanation = await _validate_answer(
        lesson=lesson,
        question_id=str(request.question_id),
        question_type=request.question_type.value,
        user_answer=request.user_answer
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


async def _validate_answer(
    lesson: Optional[Lesson],
    question_id: str,
    question_type: str,
    user_answer: any
) -> tuple[bool, str, str]:
    """
    Validate user answer against lesson content.
    Returns (is_correct, correct_answer, explanation)
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

                user_ans_normalized = _normalize_answer(user_answer, question_type)
                correct_ans_normalized = _normalize_answer(correct_answer, question_type)

                is_correct = user_ans_normalized == correct_ans_normalized
                return is_correct, correct_answer, explanation

    # Fallback: look up in the dynamic demo exercise set for this lesson
    if lesson:
        demo_ex_list = _generate_demo_exercises(lesson.title)
        for demo_ex in demo_ex_list:
            if demo_ex.id == question_id:
                correct_answer = demo_ex.correct_answer
                explanation = demo_ex.explanation or "Check the correct answer and try again."
                user_ans_normalized = _normalize_answer(user_answer, question_type)
                correct_ans_normalized = _normalize_answer(correct_answer, question_type)
                is_correct = user_ans_normalized == correct_ans_normalized
                return is_correct, correct_answer, explanation

    # Last resort: direct comparison
    is_correct = _normalize_answer(user_answer, question_type) == _normalize_answer(correct_answer, question_type)
    return is_correct, correct_answer, explanation


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
    attempt.passed = attempt.score >= 70.0
    
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
    
    # Update streak
    await _update_streak(db, current_user.id)
    
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

    await delete_cached(build_cache_key("achievements_me", user_id=str(current_user.id)))
    await delete_cached(build_cache_key("wallet", user_id=str(current_user.id)))

    time_sec = attempt.time_spent_ms // 1000
    accuracy = (attempt.correct_answers / attempt.total_questions * 100) if attempt.total_questions > 0 else 0

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
            next_lesson_unlocked=None,  # TODO
            achievements_unlocked=unlocked_achievements,
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
    
    # Get progress for all lessons
    lesson_ids = [lesson.id for unit in course.units for lesson in unit.lessons]
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
    
    # Build roadmap
    units_roadmap = []
    completed_units = 0
    completed_lessons_count = 0

    sorted_units = sorted(course.units, key=lambda unit: unit.order_index)
    for unit_number, unit in enumerate(sorted_units, start=1):
        lessons_items = []
        unit_completed = 0

        sorted_lessons = sorted(
            unit.lessons,
            key=lambda lesson: lesson.order_index
        )
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
    
    total_lessons = sum(len(u.lessons) for u in course.units)
    overall_comp = (completed_lessons_count / total_lessons * 100) if total_lessons > 0 else 0
    
    return ApiResponse(
        success=True,
        message="Roadmap retrieved",
        data=CourseRoadmapResponse(
            course_id=course.id,
            course_title=course.title,
            level=course.level,
            total_units=len(course.units),
            completed_units=completed_units,
            total_lessons=total_lessons,
            completed_lessons=completed_lessons_count,
            completion_percentage=overall_comp,
            total_xp_earned=0,  # TODO: Calculate from attempts
            current_streak=current_streak,
            units=units_roadmap
        )
    )


async def _update_streak(db: AsyncSession, user_id: UUID):
    """Update streak"""
    result = await db.execute(select(Streak).where(Streak.user_id == user_id))
    streak = result.scalar_one_or_none()
    
    today = datetime.now(timezone.utc).date()
    
    if not streak:
        streak = Streak(
            user_id=user_id,
            current_streak=1,
            longest_streak=1,
            last_activity_date=today
        )
        db.add(streak)
    else:
        last = streak.last_activity_date
        if last == today:
            pass
        elif last == today - timedelta(days=1):
            streak.current_streak += 1
            streak.longest_streak = max(streak.longest_streak, streak.current_streak)
            streak.last_activity_date = today
        else:
            streak.current_streak = 1
            streak.last_activity_date = today


def _calc_stars(score: float) -> int:
    """Calculate stars"""
    if score >= 90:
        return 3
    elif score >= 80:
        return 2
    elif score >= 70:
        return 1
    return 0
