"""Game content routes — GET endpoints that return game data and create sessions."""
import random
import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.crud.games import create_game_session
from app.models.games import GameWord
from app.models.user import User
from app.routes.game_data import (
    FILL_BLANK_BANK,
    GRAMMAR_QUIZ_BANK,
    HANGMAN_FALLBACK_WORDS,
    TIMER_BY_LEVEL,
    XP_BY_LEVEL,
    _ensure_seeded,
    _session_id,
)

router = APIRouter(prefix="/games", tags=["Games"])


# ============================================================================
# Game 1: Word Scramble
# ============================================================================

@router.get("/word-scramble")
async def get_word_scramble(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    count: int = Query(10, ge=3, le=20, description="Number of words to return"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await _ensure_seeded(db)

    result = await db.execute(select(GameWord).where(GameWord.cefr_level == level))
    words = result.scalars().all()

    if not words:
        result = await db.execute(select(GameWord).limit(count + 5))
        words = result.scalars().all()

    selected = random.sample(words, min(count, len(words)))

    items: List[dict] = []
    for w in selected:
        letters = list(w.word.upper())
        shuffled = letters.copy()
        attempts = 0
        while shuffled == letters and len(letters) > 1 and attempts < 20:
            random.shuffle(shuffled)
            attempts += 1

        items.append({
            "word_id": str(w.id),
            "word": w.word,
            "shuffled_letters": shuffled,
            "hint": w.hint,
            "definition": w.definition,
            "xp_value": w.xp_value,
            "cefr_level": w.cefr_level,
        })

    session = await create_game_session(
        db,
        user_id=current_user.id,
        game_type="word_scramble",
        cefr_level=level,
        expected_items=[
            {"id": item["word_id"], "answer": item["word"], "xp_value": item["xp_value"]}
            for item in items
        ],
    )

    return {
        "session_id": _session_id(session),
        "game": "word_scramble",
        "cefr_level": level,
        "timer_seconds": TIMER_BY_LEVEL.get(level, 60),
        "base_xp_per_word": XP_BY_LEVEL.get(level, 10),
        "streak_bonus_threshold": 3,
        "words": items,
        "total": len(items),
    }


# ============================================================================
# Game 2: Matching
# ============================================================================

@router.get("/matching")
async def get_matching_game(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    count: int = Query(6, description="Number of pairs: 4, 6, or 8"),
    variant: str = Query("definition", description="Match type: definition | synonym | vietnamese"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await _ensure_seeded(db)

    if count not in (4, 6, 8):
        count = 6

    result = await db.execute(select(GameWord).where(GameWord.cefr_level == level))
    all_words = result.scalars().all()

    if not all_words:
        result = await db.execute(select(GameWord))
        all_words = result.scalars().all()

    valid: List[GameWord] = []
    for w in all_words:
        if variant == "synonym" and w.synonyms and len(w.synonyms) > 0:
            valid.append(w)
        elif variant == "vietnamese" and w.vietnamese_translation:
            valid.append(w)
        else:
            valid.append(w)

    if not valid:
        valid = all_words
        variant = "definition"

    selected = random.sample(valid, min(count, len(valid)))

    pairs: List[dict] = []
    for w in selected:
        if variant == "synonym" and w.synonyms and len(w.synonyms) > 0:
            match_text = w.synonyms[0]
        elif variant == "vietnamese" and w.vietnamese_translation:
            match_text = w.vietnamese_translation
        else:
            match_text = w.definition

        pairs.append({"word_id": str(w.id), "word": w.word, "match_text": match_text, "variant": variant})

    words_column = [p["word"] for p in pairs]
    definitions_column = [p["match_text"] for p in pairs]
    random.shuffle(words_column)
    random.shuffle(definitions_column)

    timer = {"A1": 60, "A2": 60, "B1": 45, "B2": 45, "C1": 30, "C2": 30}.get(level, 45)
    session = await create_game_session(
        db,
        user_id=current_user.id,
        game_type="matching",
        cefr_level=level,
        expected_items=[
            {
                "id": pair["word_id"],
                "answer": pair["match_text"],
                "xp_value": next(w.xp_value for w in selected if str(w.id) == pair["word_id"]),
            }
            for pair in pairs
        ],
        session_metadata={"variant": variant},
    )

    return {
        "session_id": _session_id(session),
        "game": "matching",
        "cefr_level": level,
        "variant": variant,
        "timer_seconds": timer,
        "time_bonus_threshold": 0.5,
        "base_xp": sum(w.xp_value for w in selected),
        "pairs": pairs,
        "words_column": words_column,
        "definitions_column": definitions_column,
        "total_pairs": len(pairs),
    }


# ============================================================================
# Game 3: Spelling Bee
# ============================================================================

@router.get("/spelling-bee")
async def get_spelling_bee(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    count: int = Query(8, ge=3, le=15, description="Number of words"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await _ensure_seeded(db)

    result = await db.execute(select(GameWord).where(GameWord.cefr_level == level))
    words = result.scalars().all()

    if not words:
        result = await db.execute(select(GameWord))
        words = result.scalars().all()

    selected = random.sample(words, min(count, len(words)))

    items: List[dict] = []
    for w in selected:
        items.append({
            "word_id": str(w.id),
            "word": w.word,
            "ipa_pronunciation": w.ipa_pronunciation,
            "definition": w.definition,
            "example_sentence": w.example_sentence,
            "xp_value": w.xp_value,
            "audio_url": None,
        })

    session = await create_game_session(
        db,
        user_id=current_user.id,
        game_type="spelling_bee",
        cefr_level=level,
        expected_items=[
            {"id": item["word_id"], "answer": item["word"], "xp_value": item["xp_value"]}
            for item in items
        ],
    )

    return {
        "session_id": _session_id(session),
        "game": "spelling_bee",
        "cefr_level": level,
        "timer_seconds": TIMER_BY_LEVEL.get(level, 90),
        "words": items,
        "total": len(items),
    }


# ============================================================================
# Game 4: Hangman
# ============================================================================

@router.get("/hangman")
async def get_hangman_word(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    category: Optional[str] = Query(None, description="Optional category filter"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await _ensure_seeded(db)

    query = select(GameWord).where(GameWord.cefr_level == level)
    if category:
        query = query.where(GameWord.category == category)

    result = await db.execute(query)
    words = result.scalars().all()

    if not words and category:
        result = await db.execute(select(GameWord).where(GameWord.cefr_level == level))
        words = result.scalars().all()

    if not words:
        base_query = select(GameWord)
        if category:
            base_query = base_query.where(GameWord.category == category)
        result = await db.execute(base_query)
        words = result.scalars().all()

    if words:
        word_obj = random.choice(words)
        hint2_cost = max(1, word_obj.xp_value // 4)
        hint3_cost = max(1, word_obj.xp_value // 3)
        session = await create_game_session(
            db,
            user_id=current_user.id,
            game_type="hangman",
            cefr_level=word_obj.cefr_level,
            category=word_obj.category,
            expected_items=[{"id": str(word_obj.id), "answer": word_obj.word, "xp_value": word_obj.xp_value}],
            session_metadata={"hint_costs": [hint2_cost, hint3_cost], "max_lives": 6},
        )
        return {
            "session_id": _session_id(session),
            "word_id": str(word_obj.id),
            "word": word_obj.word,
            "category": word_obj.category,
            "hint": word_obj.hint,
            "definition": word_obj.definition,
            "letter_count": word_obj.letter_count,
            "xp_value": word_obj.xp_value,
            "base_xp": word_obj.xp_value,
            "max_lives": 6,
            "hints": {
                "hint1_free": word_obj.hint or "",
                "hint2_xp_cost": hint2_cost,
                "hint2_definition": word_obj.definition or "",
                "hint3_xp_cost": hint3_cost,
            },
            "cefr_level": word_obj.cefr_level,
        }

    # Final fallback: hardcoded minimal word set
    matching_fallback = [w for w in HANGMAN_FALLBACK_WORDS if w["cefr_level"] == level]
    pool = matching_fallback if matching_fallback else HANGMAN_FALLBACK_WORDS
    word_obj = random.choice(pool)
    hint2_cost = max(1, word_obj["xp_value"] // 4)
    hint3_cost = max(1, word_obj["xp_value"] // 3)
    fallback_word_id = str(uuid.uuid4())
    session = await create_game_session(
        db,
        user_id=current_user.id,
        game_type="hangman",
        cefr_level=word_obj["cefr_level"],
        category=word_obj["category"],
        expected_items=[{"id": fallback_word_id, "answer": word_obj["word"], "xp_value": word_obj["xp_value"]}],
        session_metadata={"hint_costs": [hint2_cost, hint3_cost], "max_lives": 6},
    )

    return {
        "session_id": _session_id(session),
        "word_id": fallback_word_id,
        "word": word_obj["word"],
        "category": word_obj["category"],
        "hint": word_obj["hint"],
        "definition": word_obj["definition"],
        "letter_count": word_obj["letter_count"],
        "xp_value": word_obj["xp_value"],
        "base_xp": word_obj["xp_value"],
        "max_lives": 6,
        "hints": {
            "hint1_free": word_obj["hint"],
            "hint2_xp_cost": hint2_cost,
            "hint2_definition": word_obj["definition"],
            "hint3_xp_cost": hint3_cost,
        },
        "cefr_level": word_obj["cefr_level"],
    }


# ============================================================================
# Game 5: Fill in the Blank
# ============================================================================

@router.get("/fill-blank")
async def get_fill_blank(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    count: int = Query(8, ge=3, le=15, description="Number of questions"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    pool = FILL_BLANK_BANK.get(level) or FILL_BLANK_BANK.get("B1", [])
    selected = random.sample(pool, min(count, len(pool)))

    questions: List[dict] = []
    for i, q in enumerate(selected, start=1):
        shuffled_options = q["options"].copy()
        random.shuffle(shuffled_options)
        questions.append({
            "id": i,
            "sentence": q["sentence"],
            "options": shuffled_options,
            "correct_answer": q["correct_answer"],
            "grammar_tip": q["grammar_tip"],
            "cefr_level": q["cefr_level"],
        })

    session = await create_game_session(
        db,
        user_id=current_user.id,
        game_type="fill_blank",
        cefr_level=level,
        expected_items=[
            {"id": str(question["id"]), "answer": question["correct_answer"], "xp_value": XP_BY_LEVEL.get(level, 15)}
            for question in questions
        ],
    )

    return {
        "session_id": _session_id(session),
        "game": "fill_blank",
        "cefr_level": level,
        "timer_seconds_per_question": 15,
        "total_xp": len(questions) * XP_BY_LEVEL.get(level, 15),
        "questions": questions,
        "total": len(questions),
    }


# ============================================================================
# Game 6: Grammar Quiz
# ============================================================================

@router.get("/grammar-quiz")
async def get_grammar_quiz(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    topic: Optional[str] = Query(None, description="Grammar topic filter (optional)"),
    count: int = Query(10, ge=3, le=15, description="Number of questions"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    pool = GRAMMAR_QUIZ_BANK.get(level) or GRAMMAR_QUIZ_BANK.get("B1", [])

    if topic:
        filtered = [q for q in pool if q.get("topic") == topic]
        if filtered:
            pool = filtered

    selected = random.sample(pool, min(count, len(pool)))

    questions: List[dict] = []
    for i, q in enumerate(selected, start=1):
        shuffled_options = q["options"].copy()
        random.shuffle(shuffled_options)
        questions.append({
            "id": i,
            "question": q["question"],
            "options": shuffled_options,
            "correct_answer": q["correct_answer"],
            "explanation": q["explanation"],
            "topic": q["topic"],
            "cefr_level": q["cefr_level"],
        })

    session = await create_game_session(
        db,
        user_id=current_user.id,
        game_type="grammar_quiz",
        cefr_level=level,
        expected_items=[
            {"id": str(question["id"]), "answer": question["correct_answer"], "xp_value": XP_BY_LEVEL.get(level, 15)}
            for question in questions
        ],
        session_metadata={"topic": topic or "mixed"},
    )

    return {
        "session_id": _session_id(session),
        "game": "grammar_quiz",
        "cefr_level": level,
        "topic": topic or "mixed",
        "timer_seconds_per_question": 12,
        "total_xp": len(questions) * XP_BY_LEVEL.get(level, 15),
        "questions": questions,
        "total": len(questions),
    }


# ============================================================================
# Game Categories Metadata
# ============================================================================

@router.get("/categories")
async def get_game_categories(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get distinct word categories and their word counts from the game_words table."""
    await _ensure_seeded(db)

    result = await db.execute(
        select(GameWord.category, func.count(GameWord.id).label("count"))
        .group_by(GameWord.category)
    )
    rows = result.all()

    return {
        "categories": [
            {"id": row.category, "label": row.category.replace("_", " ").title(), "count": row.count}
            for row in rows
        ]
    }
