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
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.crud.vocabulary import vocabulary_crud
from app.schemas.vocabulary import (
    VocabularyItemResponse,
    UserVocabularyCreate,
    UserVocabularyResponse,
    UserVocabularyWithItem,
    UserVocabularyListResponse,
    ReviewSubmission,
    ReviewResponse,
    DueVocabularyResponse,
    VocabularyStatsResponse,
    VocabularySearchParams,
    VocabularyBulkAddRequest,
    VocabularyDeckCreate,
    VocabularyDeckResponse,
    AddToDeckRequest
)

router = APIRouter(tags=["vocabulary"])


# ===== Vocabulary Items (Master List) =====

@router.get("/items", response_model=List[VocabularyItemResponse])
async def get_vocabulary_items(
    course_id: Optional[uuid.UUID] = Query(None, description="Filter by course"),
    lesson_id: Optional[uuid.UUID] = Query(None, description="Filter by lesson"),
    difficulty_level: Optional[str] = Query(None, description="A1, A2, B1, B2, C1, C2"),
    search: Optional[str] = Query(None, description="Search by word"),
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
    - search: Partial word match
    """
    if search:
        # Search by word
        items = await vocabulary_crud.search_vocabulary(db, search, limit)
    else:
        # List with filters
        items = await vocabulary_crud.get_vocabulary_items(
            db,
            course_id=course_id,
            lesson_id=lesson_id,
            difficulty_level=difficulty_level,
            limit=limit,
            offset=offset
        )
    
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
    status: Optional[str] = Query(None, description="learning, reviewing, mastered"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get user's vocabulary collection with pagination.
    
    Query params:
    - status: Filter by learning status (learning/reviewing/mastered)
    - limit: Results per page (max 100)
    - offset: Pagination offset
    
    Returns:
    - User's vocabulary with SRS data + full vocabulary details
    """
    from app.models.vocabulary import VocabularyStatus
    
    status_filter = None
    if status:
        try:
            status_filter = VocabularyStatus(status)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid status. Must be one of: learning, reviewing, mastered, archived"
            )
    
    # Get user vocabulary
    user_vocab_list = await vocabulary_crud.get_user_vocabulary_list(
        db,
        user_id=current_user.id,
        status=status_filter,
        limit=limit,
        offset=offset
    )
    
    # Load vocabulary items
    items_with_vocab = []
    for uv in user_vocab_list:
        vocab_item = await vocabulary_crud.get_vocabulary_item(db, uv.vocabulary_id)
        if vocab_item:
            items_with_vocab.append({
                **uv.__dict__,
                "vocabulary": vocab_item,
                "is_due": uv.is_due,
                "accuracy": uv.accuracy
            })
    
    # Get total count (without filters for simplicity)
    # In production, add proper count query
    total = len(user_vocab_list)
    
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
    # Get due vocabulary
    due_vocab = await vocabulary_crud.get_due_vocabulary(
        db,
        user_id=current_user.id,
        limit=limit
    )
    
    # Load vocabulary items
    items_with_vocab = []
    for uv in due_vocab:
        vocab_item = await vocabulary_crud.get_vocabulary_item(db, uv.vocabulary_id)
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
    # Verify ownership
    user_vocab = await vocabulary_crud.get_user_vocabulary(
        db,
        user_id=current_user.id,
        vocabulary_id=uuid.UUID('00000000-0000-0000-0000-000000000000')  # Dummy, we'll fetch by ID
    )
    
    # Actually fetch by user_vocabulary_id and verify user
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
    
    # Generate message
    messages = {
        5: "Perfect! 🎉",
        4: "Great job! 👍",
        3: "Good effort! 💪",
        2: "Keep practicing!",
        1: "Don't give up!",
        0: "Review the word again"
    }
    
    return ReviewResponse(
        user_vocabulary=updated_vocab,
        xp_awarded=xp_awarded,
        streak_bonus=streak_bonus,
        next_review_in_days=updated_vocab.interval,
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
    stats = await vocabulary_crud.get_user_vocabulary_stats(db, current_user.id)
    
    return VocabularyStatsResponse(**stats)


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
