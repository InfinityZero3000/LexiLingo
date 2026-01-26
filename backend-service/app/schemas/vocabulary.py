"""
Vocabulary Pydantic Schemas
Phase 3: Request/Response models for vocabulary API
"""

import uuid
from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator


# ===== VocabularyItem Schemas =====

class VocabularyItemBase(BaseModel):
    """Base vocabulary item schema"""
    word: str = Field(..., max_length=255, description="The vocabulary word")
    definition: str = Field(..., description="Definition in English")
    translation: Optional[Dict[str, Any]] = Field(None, description="Translations and examples")
    pronunciation: Optional[str] = Field(None, max_length=100, description="IPA pronunciation")
    audio_url: Optional[str] = Field(None, max_length=500, description="Audio URL")
    part_of_speech: str = Field(..., description="noun, verb, adjective, etc.")
    difficulty_level: str = Field(..., description="A1, A2, B1, B2, C1, C2")
    tags: Optional[List[str]] = Field(None, description="Tags for categorization")


class VocabularyItemCreate(VocabularyItemBase):
    """Schema for creating vocabulary item"""
    course_id: Optional[uuid.UUID] = None
    lesson_id: Optional[uuid.UUID] = None


class VocabularyItemResponse(VocabularyItemBase):
    """Schema for vocabulary item response"""
    id: uuid.UUID
    course_id: Optional[uuid.UUID]
    lesson_id: Optional[uuid.UUID]
    usage_frequency: int
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


# ===== UserVocabulary Schemas =====

class UserVocabularyBase(BaseModel):
    """Base user vocabulary schema"""
    vocabulary_id: uuid.UUID


class UserVocabularyCreate(UserVocabularyBase):
    """Schema for adding vocabulary to collection"""
    pass


class UserVocabularyResponse(BaseModel):
    """
    Schema for user vocabulary response (with SRS data).
    Includes the actual vocabulary item data.
    """
    id: uuid.UUID
    user_id: uuid.UUID
    vocabulary_id: uuid.UUID
    status: str
    
    # SRS data
    ease_factor: float
    interval: int
    repetitions: int
    next_review_date: datetime
    last_reviewed_at: Optional[datetime]
    
    # Statistics
    total_reviews: int
    correct_reviews: int
    streak: int
    longest_streak: int
    total_xp_earned: int
    
    # Metadata
    notes: Optional[str]
    added_at: datetime
    
    # Computed properties
    is_due: bool = Field(default=False, description="Whether review is due")
    accuracy: float = Field(default=0.0, description="Accuracy percentage")
    
    class Config:
        from_attributes = True


class UserVocabularyWithItem(UserVocabularyResponse):
    """User vocabulary with full vocabulary item details"""
    vocabulary: VocabularyItemResponse


class UserVocabularyListResponse(BaseModel):
    """Paginated vocabulary list response"""
    items: List[UserVocabularyWithItem]
    total: int
    limit: int
    offset: int
    has_more: bool


# ===== Review Schemas =====

class ReviewSubmission(BaseModel):
    """Schema for submitting a vocabulary review"""
    quality: int = Field(..., ge=0, le=5, description="Quality rating (0-5)")
    time_spent_ms: int = Field(default=0, ge=0, description="Time spent in milliseconds")
    
    @field_validator('quality')
    def validate_quality(cls, v):
        """Ensure quality is in valid range"""
        if not 0 <= v <= 5:
            raise ValueError("Quality must be between 0 and 5")
        return v


class ReviewResponse(BaseModel):
    """Schema for review submission response"""
    user_vocabulary: UserVocabularyResponse
    xp_awarded: int
    streak_bonus: bool
    next_review_in_days: int
    message: str


class VocabularyReviewHistoryItem(BaseModel):
    """Individual review record"""
    id: uuid.UUID
    quality: int
    time_spent_ms: int
    ease_factor_after: Optional[float]
    interval_after: Optional[int]
    reviewed_at: datetime
    
    class Config:
        from_attributes = True


# ===== Due Vocabulary Schemas =====

class DueVocabularyResponse(BaseModel):
    """Response for due vocabulary endpoint"""
    items: List[UserVocabularyWithItem]
    total_due: int
    daily_target: int = 20
    progress_percentage: float


# ===== Statistics Schemas =====

class VocabularyStatsResponse(BaseModel):
    """User vocabulary statistics"""
    total: int
    learning: int
    reviewing: int
    mastered: int
    due_for_review: int
    total_xp: int
    best_streak: int


# ===== Deck Schemas =====

class VocabularyDeckBase(BaseModel):
    """Base deck schema"""
    name: str = Field(..., max_length=100, description="Deck name")
    description: Optional[str] = Field(None, description="Deck description")
    color: str = Field(default="#2196F3", max_length=7, description="Hex color code")
    is_public: bool = Field(default=False, description="Whether deck is public")


class VocabularyDeckCreate(VocabularyDeckBase):
    """Schema for creating a deck"""
    pass


class VocabularyDeckResponse(VocabularyDeckBase):
    """Schema for deck response"""
    id: uuid.UUID
    user_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    item_count: int = Field(default=0, description="Number of items in deck")
    
    class Config:
        from_attributes = True


class AddToDeckRequest(BaseModel):
    """Schema for adding vocabulary to deck"""
    user_vocabulary_id: uuid.UUID
    order: int = Field(default=0, description="Order in deck")


# ===== Search & Filter Schemas =====

class VocabularySearchParams(BaseModel):
    """Query parameters for vocabulary search"""
    search: Optional[str] = Field(None, description="Search term")
    course_id: Optional[uuid.UUID] = Field(None, description="Filter by course")
    lesson_id: Optional[uuid.UUID] = Field(None, description="Filter by lesson")
    difficulty_level: Optional[str] = Field(None, description="A1, A2, B1, B2, C1, C2")
    status: Optional[str] = Field(None, description="learning, reviewing, mastered")
    limit: int = Field(default=50, ge=1, le=100, description="Results per page")
    offset: int = Field(default=0, ge=0, description="Pagination offset")


class VocabularyBulkAddRequest(BaseModel):
    """Schema for bulk adding vocabulary from lesson"""
    vocabulary_ids: List[uuid.UUID] = Field(..., description="List of vocabulary IDs to add")
