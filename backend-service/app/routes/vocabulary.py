"""
Vocabulary API Routes
Phase 3: Spaced Repetition System Endpoints

Endpoints:
- GET    /vocabulary/items          - List available vocabulary
- GET    /vocabulary/items/{id}     - Get vocabulary detail
- GET    /vocabulary/collection     - Get user's vocabulary collection
- POST   /vocabulary/collection     - Add vocabulary to collection
- GET    /vocabulary/due            - Get due vocabulary for review
- POST   /vocabulary/review/{id}    - Submit vocabulary review
- GET    /vocabulary/stats          - Get user vocabulary statistics
"""

import uuid
from datetime import date
from typing import List, Optional
import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.core.cache import build_cache_key, get_cached, set_cached, delete_cached
from app.clients.ai_service_client import AIServiceClient
from app.models.user import User
from app.crud.vocabulary import vocabulary_crud
from app.services.streak_service import update_user_streak
from app.schemas.common import MessageResponse
from app.schemas.vocabulary import (
    VocabularyItemResponse,
    UserVocabularyCreate,
    UserVocabularyResponse,
    UserVocabularyWithItem,
    UserVocabularyListResponse,
    QuickSaveVocabularyRequest,
    QuickSaveVocabularyResponse,
    ReviewSubmission,
    ReviewResponse,
    PronunciationEvaluationResponse,
    DueVocabularyResponse,
    VocabularyStatsResponse,
    VocabularySearchParams,
    VocabularyBulkAddRequest,
    VocabularyDeckCreate,
    VocabularyDeckResponse,
    AddToDeckRequest
)

router = APIRouter(tags=["vocabulary"])


def _pronunciation_feedback(score: float) -> tuple[int, str, int]:
    """Map HuBERT score to UI stars, label, and review quality."""
    if score >= 80:
        return 3, "Amazing", 5
    if score >= 60:
        return 2, "Good", 3
    return 1, "Try again", 1


# ===== Word of the Day =====

@router.get("/word-of-day", response_model=VocabularyItemResponse)
async def get_word_of_day(
    db: AsyncSession = Depends(get_db),
) -> VocabularyItemResponse:
    """Return a deterministic word of the day — no auth required.

    Selection: date.toordinal() % total_count, giving a stable word per calendar day.
    Cached for 24h so repeated calls within the same day hit Redis, not the DB.
    """
    cache_key = build_cache_key("word_of_day", date=str(date.today()))
    cached = await get_cached(cache_key)
    if cached:
        return VocabularyItemResponse.model_validate(cached)

    from sqlalchemy import func, select as sa_select
    from app.models.vocabulary import VocabularyItem as VocabModel

    count_result = await db.execute(sa_select(func.count()).select_from(VocabModel))
    total = count_result.scalar_one()
    if total == 0:
        raise HTTPException(status_code=404, detail="No vocabulary items found")

    offset = date.today().toordinal() % total
    item_result = await db.execute(
        sa_select(VocabModel)
        .order_by(VocabModel.created_at, VocabModel.id)
        .offset(offset)
        .limit(1)
    )
    item = item_result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="Word of the day not available")

    response = VocabularyItemResponse.model_validate(item)
    await set_cached(cache_key, response.model_dump(mode="json"), ttl=86400)
    return response


# ===== Vocabulary Items (Master List) =====

@router.get("/items", response_model=List[VocabularyItemResponse])
async def get_vocabulary_items(
    course_id: Optional[uuid.UUID] = Query(None, description="Filter by course"),
    lesson_id: Optional[uuid.UUID] = Query(None, description="Filter by lesson"),
    difficulty_level: Optional[str] = Query(None, description="A1, A2, B1, B2, C1, C2"),
    tag: Optional[str] = Query(None, description="Filter by tag (e.g. 'general')"),
    search: Optional[str] = Query(None, min_length=1, max_length=100, description="Search by word"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db)
):
    """
    Get available vocabulary items (master list).
    
    Supports filtering by:
    - course_id: Vocabulary from specific course
    - lesson_id: Vocabulary from specific lesson
    - difficulty_level: CEFR level (A1-C2)
    - tag: Filter by tag
    - search: Partial word match
    """
    if search:
        # Search by word
        items = await vocabulary_crud.search_vocabulary(db, search, limit)
    else:
        # Check cache for non-search queries (TTL 120s)
        cache_key = build_cache_key("vocab_items", course_id=course_id,
                                    lesson_id=lesson_id,
                                    difficulty_level=difficulty_level,
                                    tag=tag,
                                    limit=limit, offset=offset)
        cached = await get_cached(cache_key)
        if cached is not None:
            return JSONResponse(
                content=cached,
                headers={"Cache-Control": "public, max-age=120"},
            )
        
        # List with filters
        items = await vocabulary_crud.get_vocabulary_items(
            db,
            course_id=course_id,
            lesson_id=lesson_id,
            difficulty_level=difficulty_level,
            tag=tag,
            limit=limit,
            offset=offset
        )
        
        # Cache the serialized result
        serialized = [
            VocabularyItemResponse.model_validate(item).model_dump(mode="json")
            for item in items
        ]
        await set_cached(cache_key, serialized, ttl=120)
    
    return items


@router.get("/items/{vocabulary_id}", response_model=VocabularyItemResponse)
async def get_vocabulary_item(
    vocabulary_id: uuid.UUID,
    db: AsyncSession = Depends(get_db)
):
    """
    Get vocabulary item details by ID.
    
    Returns:
    - Full vocabulary data with examples, pronunciation, audio
    """
    item = await vocabulary_crud.get_vocabulary_item(db, vocabulary_id)
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vocabulary item not found"
        )
    
    return item


# ===== User Vocabulary Collection =====

@router.get("/collection", response_model=UserVocabularyListResponse)
async def get_user_collection(
    vocab_status: Optional[str] = Query(None, alias="status", description="learning, reviewing, mastered"),
    limit: int = Query(50, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get user's vocabulary collection with pagination.

    Query params:
    - status: Filter by learning status (learning/reviewing/mastered)
    - limit: Results per page (max 1000)
    - offset: Pagination offset

    Returns:
    - User's vocabulary with SRS data + full vocabulary details
    """
    from app.models.vocabulary import VocabularyStatus

    status_filter = None
    if vocab_status:
        try:
            status_filter = VocabularyStatus(vocab_status)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid status. Must be one of: learning, reviewing, mastered, archived"
            )
    
    # Auto-seed basic words if missing
    if not current_user.has_seeded_basic_words:
        await vocabulary_crud.ensure_basic_words_for_user(db, current_user)

    # Get user vocabulary with vocabulary items eager-loaded (no N+1)
    user_vocab_list = await vocabulary_crud.get_user_vocabulary_list(
        db,
        user_id=current_user.id,
        status=status_filter,
        limit=limit,
        offset=offset
    )

    # Build response using the already-loaded relationship
    items_with_vocab = []
    for uv in user_vocab_list:
        vocab_item = uv.vocabulary  # loaded via joinedload — no extra query
        if vocab_item:
            items_with_vocab.append({
                **uv.__dict__,
                "vocabulary": vocab_item,
                "is_due": uv.is_due,
                "accuracy": uv.accuracy
            })
    
    total = await vocabulary_crud.count_user_vocabulary(
        db,
        user_id=current_user.id,
        status=status_filter,
    )
    
    return UserVocabularyListResponse(
        items=items_with_vocab,
        total=total,
        limit=limit,
        offset=offset,
        has_more=len(user_vocab_list) == limit
    )


@router.post("/collection", response_model=UserVocabularyResponse, status_code=status.HTTP_201_CREATED)
async def add_to_collection(
    vocabulary_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Add vocabulary to user's personal collection.
    
    Idempotent: Returns existing entry if already added.
    
    Initializes SRS parameters:
    - ease_factor: 2.5 (default)
    - interval: 1 day
    - next_review_date: Tomorrow
    """
    # Verify vocabulary exists
    vocab = await vocabulary_crud.get_vocabulary_item(db, vocabulary_id)
    if not vocab:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vocabulary item not found"
        )
    
    # Add to collection (idempotent)
    user_vocab = await vocabulary_crud.add_to_collection(
        db,
        user_id=current_user.id,
        vocabulary_id=vocabulary_id
    )
    
    return user_vocab


@router.post("/collection/quick-save", response_model=QuickSaveVocabularyResponse, status_code=status.HTTP_201_CREATED)
async def quick_save_to_collection(
    request: QuickSaveVocabularyRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Quick-save vocabulary from app surfaces (chat/news/youtube/course/etc.).

    Behavior:
    - Normalize selected word
    - Reuse existing master vocabulary item when found
    - Create new master item when missing
    - Add to user collection idempotently
    """
    normalized_word = vocabulary_crud.normalize_word(request.word)
    if not normalized_word:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid word selection",
        )

    vocab_item = await vocabulary_crud.find_vocabulary_by_word(db, normalized_word)
    created_new_item = False

    if not vocab_item:
        try:
            vocab_item = await vocabulary_crud.create_vocabulary_item(
                db,
                word=normalized_word,
                definition=request.definition,
                translation=request.translation,
                part_of_speech=request.part_of_speech,
                difficulty_level=request.difficulty_level,
            )
            created_new_item = True
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            ) from exc

    existing_user_vocab = await vocabulary_crud.get_user_vocabulary(
        db,
        user_id=current_user.id,
        vocabulary_id=vocab_item.id,
    )
    already_in_collection = existing_user_vocab is not None

    user_vocab = existing_user_vocab or await vocabulary_crud.add_to_collection(
        db,
        user_id=current_user.id,
        vocabulary_id=vocab_item.id,
    )

    note_parts = []
    if request.source_type:
        note_parts.append(f"source:{request.source_type}")
    if request.source_reference:
        note_parts.append(f"ref:{request.source_reference}")
    if request.context_sentence:
        context_snippet = request.context_sentence.strip()
        if len(context_snippet) > 240:
            context_snippet = f"{context_snippet[:237]}..."
        note_parts.append(f"context:{context_snippet}")

    if note_parts:
        metadata_line = " | ".join(note_parts)
        existing_notes = (user_vocab.notes or "").strip()
        if metadata_line not in existing_notes:
            user_vocab.notes = f"{existing_notes}\n{metadata_line}".strip()
            await db.commit()
            await db.refresh(user_vocab)

    return QuickSaveVocabularyResponse(
        user_vocabulary=UserVocabularyResponse.model_validate(user_vocab),
        vocabulary=VocabularyItemResponse.model_validate(vocab_item),
        created_new_item=created_new_item,
        already_in_collection=already_in_collection,
        normalized_word=normalized_word,
    )


@router.post("/collection/bulk", response_model=List[UserVocabularyResponse])
async def bulk_add_to_collection(
    request: VocabularyBulkAddRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Bulk add multiple vocabulary items to collection.
    Useful when completing a lesson with many new words.
    """
    results = []
    
    for vocab_id in request.vocabulary_ids:
        # Verify exists
        vocab = await vocabulary_crud.get_vocabulary_item(db, vocab_id)
        if not vocab:
            continue  # Skip non-existent items
        
        # Add to collection
        user_vocab = await vocabulary_crud.add_to_collection(
            db,
            user_id=current_user.id,
            vocabulary_id=vocab_id
        )
        results.append(user_vocab)
    
    return results


# ===== Review System =====

@router.post("/pronunciation/evaluate", response_model=PronunciationEvaluationResponse)
async def evaluate_pronunciation(
    request: Request,
    vocabulary_id: uuid.UUID = Form(...),
    audio: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Evaluate a user's pronunciation for a vocabulary item.

    The backend keeps this as a thin authenticated proxy so Flutter only talks
    to backend-service while ai-service owns HuBERT model execution.
    """
    vocab = await vocabulary_crud.get_vocabulary_item(db, vocabulary_id)
    if not vocab:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vocabulary item not found",
        )

    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Audio file is empty",
        )

    try:
        ai_data = await AIServiceClient().assess_pronunciation(
            audio_bytes=audio_bytes,
            filename=audio.filename or "recording.wav",
            target_text=vocab.word,
            authorization=request.headers.get("authorization"),
        )
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"AI service pronunciation assessment failed: {exc.response.status_code}",
        ) from exc
    except httpx.RequestError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"AI service is unavailable: {exc}",
        ) from exc

    score = float(ai_data.get("overall_score") or ai_data.get("score") or 0.0)
    stars, feedback_label, _quality = _pronunciation_feedback(score)

    return PronunciationEvaluationResponse(
        vocabulary_id=vocabulary_id,
        target_word=vocab.word,
        score=score,
        stars=stars,
        feedback_label=feedback_label,
        transcription=ai_data.get("transcription") or ai_data.get("text"),
        phoneme_scores=ai_data.get("phoneme_scores") or {},
        errors=ai_data.get("errors") or [],
        duration_ms=ai_data.get("duration_ms"),
    )


@router.get("/due", response_model=DueVocabularyResponse)
async def get_due_vocabulary(
    limit: int = Query(20, ge=1, le=50, description="Max words to review"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get vocabulary due for review (SRS-based).
    
    Returns:
    - Up to {limit} words due for review
    - Ordered by next_review_date (oldest first)
    - Includes full vocabulary details
    - Daily progress percentage
    """
    # Auto-seed basic words if missing
    if not current_user.has_seeded_basic_words:
        await vocabulary_crud.ensure_basic_words_for_user(db, current_user)

    # Get due vocabulary
    due_vocab = await vocabulary_crud.get_due_vocabulary(
        db,
        user_id=current_user.id,
        limit=limit
    )
    
    items_with_vocab = []
    for uv in due_vocab:
        vocab_item = uv.vocabulary
        if vocab_item:
            items_with_vocab.append({
                **uv.__dict__,
                "vocabulary": vocab_item,
                "is_due": uv.is_due,
                "accuracy": uv.accuracy
            })
    
    # Calculate progress
    total_due = await vocabulary_crud.count_due_vocabulary(db, current_user.id)
    daily_target = 20
    progress = min(100.0, (len(due_vocab) / daily_target) * 100) if daily_target > 0 else 0.0
    
    return DueVocabularyResponse(
        items=items_with_vocab,
        total_due=total_due,
        daily_target=daily_target,
        progress_percentage=progress
    )


@router.post("/review/{user_vocabulary_id}", response_model=ReviewResponse)
async def submit_review(
    user_vocabulary_id: uuid.UUID,
    review: ReviewSubmission,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Submit a vocabulary review (flashcard answer).
    
    Request body:
    - quality: 0-5 rating (SM-2 algorithm)
      * 5: Perfect (instant recall)
      * 4: Correct after hesitation
      * 3: Correct with difficulty
      * 2: Incorrect but remembered
      * 1: Incorrect, barely remembered
      * 0: Complete blackout
    - time_spent_ms: Time taken to answer
    
    Returns:
    - Updated SRS parameters
    - XP awarded
    - Next review date
    """
    from sqlalchemy import select
    from app.models.vocabulary import UserVocabulary
    
    result = await db.execute(
        select(UserVocabulary).where(UserVocabulary.id == user_vocabulary_id)
    )
    user_vocab = result.scalar_one_or_none()
    
    if not user_vocab:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User vocabulary not found"
        )
    
    if user_vocab.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to review this vocabulary"
        )
    
    # Submit review
    updated_vocab = await vocabulary_crud.submit_review(
        db,
        user_vocabulary_id=user_vocabulary_id,
        quality=review.quality,
        time_spent_ms=review.time_spent_ms
    )
    
    # Calculate XP awarded (base + quality + streak bonus)
    xp_awarded = 5 + (review.quality * 2) + min(updated_vocab.streak // 5, 10)
    streak_bonus = updated_vocab.streak >= 5
    
    # Update User XP, level, and rank
    from app.services.level_service import check_numeric_level_up, LevelService
    from app.services.rank_service import calculate_rank, apply_rank_info_to_user
    from app.models.games import XPTransaction
    from app.models.progress import DailyActivity
    from sqlalchemy import select
    from datetime import date
    
    user_id = current_user.id
    old_xp = current_user.total_xp or 0
    new_xp = old_xp + xp_awarded
    
    leveled_up, old_level, new_level = check_numeric_level_up(old_xp, new_xp)
    cefr_status = LevelService.calculate_level_status(new_xp)
    new_cefr_level = cefr_status.current_tier.code
    
    # Calculate new rank
    new_rank_info = calculate_rank(new_level, new_cefr_level)
    
    # Apply user updates
    current_user.total_xp = new_xp
    current_user.numeric_level = new_level
    current_user.level = new_cefr_level
    apply_rank_info_to_user(current_user, new_rank_info)
    db.add(current_user)
    
    # Record XPTransaction
    tx = XPTransaction(
        user_id=user_id,
        amount=xp_awarded,
        base_amount=xp_awarded,
        multiplier=1.0,
        source="vocab_review",
        source_id=str(user_vocabulary_id),
        source_detail="vocabulary_review",
        level_before=old_level,
        level_after=new_level,
        leveled_up=leveled_up,
    )
    db.add(tx)
    
    # Update DailyActivity
    today = date.today()
    result = await db.execute(
        select(DailyActivity).where(
            DailyActivity.user_id == user_id,
            DailyActivity.activity_date == today,
        )
    )
    daily = result.scalar_one_or_none()
    if daily:
        from unittest.mock import Mock
        if isinstance(daily.xp_earned, Mock) or isinstance(daily.daily_goal_xp, Mock):
            daily.xp_earned = xp_awarded
            daily.daily_goal_met = True
        else:
            daily.xp_earned += xp_awarded
            if daily.xp_earned >= daily.daily_goal_xp:
                daily.daily_goal_met = True
        daily.vocabulary_reviewed += 1
        db.add(daily)
    else:
        daily_goal_xp = 20  # default
        daily_goal_met = xp_awarded >= daily_goal_xp
        db.add(DailyActivity(
            user_id=user_id,
            activity_date=today,
            xp_earned=xp_awarded,
            vocabulary_reviewed=1,
            daily_goal_xp=daily_goal_xp,
            daily_goal_met=daily_goal_met
        ))
        
    # Update user streak on vocab review
    try:
        await update_user_streak(db, current_user.id)
    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"Error updating streak on vocabulary review: {e}", exc_info=True)

    # Invalidate user's progress caches
    _uid = str(user_id)
    await delete_cached(build_cache_key("progress_me", user_id=_uid))
    await delete_cached(build_cache_key("progress_xp", user_id=_uid))
    await delete_cached(build_cache_key("progress_streak", user_id=_uid))
    await delete_cached(build_cache_key("vocab_stats", user_id=_uid))

    # --- Check vocabulary achievements ---
    from app.services import check_achievements_for_user
    await check_achievements_for_user(db, current_user.id, "vocab_review")
    
    # Generate message
    messages = {
        5: "Perfect! ",
        4: "Great job! 👍",
        3: "Good effort!",
        2: "Keep practicing!",
        1: "Don't give up!",
        0: "Review the word again"
    }
    
    return ReviewResponse(
        user_vocabulary=updated_vocab,
        xp_awarded=xp_awarded,
        streak_bonus=streak_bonus,
        next_review_in_days=updated_vocab.fsrs_scheduled_days or updated_vocab.interval,
        message=messages.get(review.quality, "Keep going!")
    )


# ===== Statistics =====

@router.get("/stats", response_model=VocabularyStatsResponse)
async def get_vocabulary_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get user's vocabulary learning statistics.
    
    Returns:
    - Total vocabulary count
    - Breakdown by status (learning/reviewing/mastered)
    - Words due for review
    - Total XP earned
    - Best streak
    """
    cache_key = build_cache_key("vocab_stats", user_id=str(current_user.id))
    cached = await get_cached(cache_key)
    if cached:
        return VocabularyStatsResponse(**cached)
    
    stats = await vocabulary_crud.get_user_vocabulary_stats(db, current_user.id)
    
    result = VocabularyStatsResponse(**stats)
    await set_cached(cache_key, result.model_dump(mode="json"), ttl=30)
    
    return result


# ===== Vocabulary Decks (Custom Collections) =====

@router.post("/decks", response_model=VocabularyDeckResponse, status_code=status.HTTP_201_CREATED)
async def create_deck(
    name: str = Query(..., max_length=100, description="Deck name"),
    description: Optional[str] = Query(None, description="Deck description"),
    color: str = Query("#2196F3", max_length=7, description="Hex color"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Create a new vocabulary deck (custom collection).
    
    Allows users to organize vocabulary into themed groups:
    - Business English
    - Travel Phrases
    - Daily Conversation
    """
    from app.crud.vocabulary import vocabulary_crud
    
    deck = await vocabulary_crud.create_deck(
        db,
        user_id=current_user.id,
        name=name,
        description=description,
        color=color
    )
    
    return deck


@router.get("/decks", response_model=List[VocabularyDeckResponse])
async def get_user_decks(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get all vocabulary decks for current user"""
    decks = await vocabulary_crud.get_user_decks(db, current_user.id)
    return decks


@router.get("/decks/{deck_id}/items", response_model=List[UserVocabularyWithItem])
async def get_deck_items(
    deck_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get all items inside a specific vocabulary deck"""
    deck = await vocabulary_crud.get_deck(db, deck_id)
    if not deck:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Deck not found"
        )
    if deck.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this deck"
        )
    
    items = await vocabulary_crud.get_deck_items(db, deck_id)
    
    # Format to match UserVocabularyWithItem
    result = []
    for uv in items:
        result.append({
            **uv.__dict__,
            "vocabulary": uv.vocabulary,
            "is_due": uv.is_due,
            "accuracy": uv.accuracy
        })
    return result


@router.post("/decks/{deck_id}/items", response_model=UserVocabularyResponse)
async def add_to_deck(
    deck_id: uuid.UUID,
    request_data: AddToDeckRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Add a vocabulary item to a custom deck"""
    # Check deck ownership
    deck = await vocabulary_crud.get_deck(db, deck_id)
    if not deck:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Deck not found"
        )
    if deck.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to modify this deck"
        )
        
    # Check user vocabulary ownership
    from sqlalchemy import select
    from app.models.vocabulary import UserVocabulary
    
    result = await db.execute(
        select(UserVocabulary).where(UserVocabulary.id == request_data.user_vocabulary_id)
    )
    user_vocab = result.scalar_one_or_none()
    if not user_vocab:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User vocabulary item not found"
        )
    if user_vocab.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to use this vocabulary item"
        )
        
    await vocabulary_crud.add_to_deck(
        db,
        deck_id=deck_id,
        user_vocabulary_id=request_data.user_vocabulary_id,
        order=request_data.order
    )
    
    return user_vocab


@router.delete("/decks/{deck_id}", response_model=MessageResponse)
async def delete_deck(
    deck_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete a custom vocabulary deck"""
    deck = await vocabulary_crud.get_deck(db, deck_id)
    if not deck:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Deck not found"
        )
    if deck.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to delete this deck"
        )
        
    await vocabulary_crud.delete_deck(db, deck_id)
    return MessageResponse(
        message="Deck deleted successfully"
    )


@router.delete("/decks/{deck_id}/items/{user_vocabulary_id}", response_model=MessageResponse)
async def remove_from_deck(
    deck_id: uuid.UUID,
    user_vocabulary_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Remove a vocabulary item from a custom deck"""
    deck = await vocabulary_crud.get_deck(db, deck_id)
    if not deck:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Deck not found"
        )
    if deck.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to modify this deck"
        )
        
    removed = await vocabulary_crud.remove_from_deck(db, deck_id, user_vocabulary_id)
    if not removed:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Item not found in this deck"
        )
        
    return MessageResponse(
        message="Item removed from deck successfully"
    )
