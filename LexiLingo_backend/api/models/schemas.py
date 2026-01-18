"""
Pydantic models for request/response

Following Flutter's Entity pattern from Domain layer
"""

from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from enum import Enum


# ============================================================
# Enums (similar to Flutter enums)
# ============================================================

class MessageRole(str, Enum):
    """Message role enum."""
    USER = "user"
    AI = "ai"
    SYSTEM = "system"


class MessageStatus(str, Enum):
    """Message status enum."""
    PENDING = "pending"
    SENT = "sent"
    ERROR = "error"


# ============================================================
# Health Check
# ============================================================

class HealthCheck(BaseModel):
    """Health check response."""
    status: str
    version: str
    environment: str
    services: Dict[str, bool]


class ErrorType(str, Enum):
    """Grammar error types."""
    VERB_TENSE = "verb_tense"
    SUBJECT_VERB_AGREEMENT = "subject_verb_agreement"
    ARTICLE = "article"
    PREPOSITION = "preposition"
    WORD_ORDER = "word_order"
    SPELLING = "spelling"
    OTHER = "other"


# ============================================================
# AI Interaction Models
# ============================================================

class GrammarError(BaseModel):
    """Grammar error model."""
    type: ErrorType
    error: str
    correction: str
    explanation: str
    severity: str = "moderate"  # minor, moderate, critical


class PronunciationError(BaseModel):
    """Pronunciation error model."""
    phoneme: str
    expected: str
    actual: str
    position: int
    word: str


class AIAnalysis(BaseModel):
    """AI analysis result model."""
    fluency_score: float = Field(..., ge=0.0, le=1.0)
    vocabulary_level: str  # A1, A2, B1, B2, C1, C2
    grammar_errors: List[GrammarError] = []
    pronunciation_errors: Optional[List[PronunciationError]] = None
    vocabulary_suggestions: List[Dict[str, str]] = []
    tutor_response: str
    tutor_response_vi: Optional[str] = None


class UserInput(BaseModel):
    """User input model."""
    text: str
    audio_features: Optional[Dict[str, Any]] = None
    context: List[str] = []


class LogInteractionRequest(BaseModel):
    """Request to log AI interaction."""
    session_id: str
    user_id: str
    user_input: UserInput
    models_used: List[str]
    processing_time_ms: Dict[str, int]
    analysis: AIAnalysis
    user_feedback: Optional[Dict[str, Any]] = None


class LogInteractionResponse(BaseModel):
    """Response after logging interaction."""
    interaction_id: str
    message: str = "Interaction logged successfully"


# ============================================================
# Chat Models
# ============================================================

class ChatMessage(BaseModel):
    """Chat message model (matching Flutter entity)."""
    id: Optional[str] = None
    session_id: str
    content: str
    role: MessageRole
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    status: MessageStatus = MessageStatus.SENT


class CreateSessionRequest(BaseModel):
    """Request to create chat session."""
    user_id: str
    title: Optional[str] = "New Conversation"


class CreateSessionResponse(BaseModel):
    """Response after creating session."""
    session_id: str
    title: str
    created_at: datetime


class SendMessageRequest(BaseModel):
    """Request to send message."""
    session_id: str
    user_id: str
    message: str


class SendMessageResponse(BaseModel):
    """Response with AI message."""
    message_id: str
    ai_response: str
    analysis: Optional[AIAnalysis] = None
    processing_time_ms: int


# ============================================================
# User Models
# ============================================================

class UserStats(BaseModel):
    """User statistics model."""
    total_interactions: int
    avg_fluency_score: float
    common_errors: List[Dict[str, Any]]
    improvement_rate: Dict[str, float]
    study_streak_days: int


class UserLearningPattern(BaseModel):
    """User learning pattern model."""
    user_id: str
    analyzed_at: datetime
    common_errors: List[Dict[str, Any]]
    improvement_rate: Dict[str, float]
    recommended_focus: List[str]
    stats: UserStats


# ============================================================
# Health Check Models
# ============================================================

class HealthCheck(BaseModel):
    """Health check response."""
    status: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    version: str
    environment: str
    services: Dict[str, bool]  # mongodb, redis, ai_model


# ============================================================
# Error Response Model
# ============================================================

class ErrorResponse(BaseModel):
    """Standard error response."""
    error: str
    message: str
    details: Optional[Dict[str, Any]] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ============================================================
# Feedback & Training Models
# ============================================================

class UserFeedback(BaseModel):
    """User feedback on AI response."""
    interaction_id: str
    user_id: str
    rating: int = Field(..., ge=1, le=5)  # 1-5 stars
    helpful: bool
    accurate: bool
    feedback_text: Optional[str] = None
    reported_issues: List[str] = []  # ["incorrect_grammar", "wrong_level", etc.]
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class SubmitFeedbackRequest(BaseModel):
    """Request to submit feedback."""
    interaction_id: str
    user_id: str
    rating: int = Field(..., ge=1, le=5)
    helpful: bool = True
    accurate: bool = True
    feedback_text: Optional[str] = None
    reported_issues: List[str] = []


class SubmitFeedbackResponse(BaseModel):
    """Response after submitting feedback."""
    success: bool
    message: str = "Feedback submitted successfully"


class TrainingExample(BaseModel):
    """Training example for LoRA fine-tuning."""
    example_id: str
    source_interaction_id: str
    user_input: str
    expected_output: Dict[str, Any]
    task_type: str  # "grammar", "fluency", "vocabulary", "tutor_response"
    difficulty_level: str  # A1, A2, B1, B2, C1, C2
    quality_score: float = Field(..., ge=0.0, le=1.0)
    validated: bool = False
    validated_by: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class AddToTrainingQueueRequest(BaseModel):
    """Request to add interaction to training queue."""
    interaction_id: str
    task_types: List[str]  # Which tasks this example is good for
    quality_score: float = Field(default=1.0, ge=0.0, le=1.0)
    notes: Optional[str] = None


class AddToTrainingQueueResponse(BaseModel):
    """Response after adding to training queue."""
    example_id: str
    message: str = "Added to training queue"


class UserProgressSnapshot(BaseModel):
    """User progress snapshot."""
    user_id: str
    snapshot_date: datetime
    level: str  # A1, A2, B1, B2, C1, C2
    fluency_score_avg: float
    grammar_accuracy: float
    vocabulary_count: int
    pronunciation_score_avg: Optional[float] = None
    total_interactions: int
    study_streak_days: int
    common_errors: List[Dict[str, Any]]
    improvement_trend: str  # "improving", "stable", "declining"


class ErrorPattern(BaseModel):
    """Detected error pattern."""
    pattern_id: str
    error_type: ErrorType
    frequency: int
    affected_users: List[str]
    example_errors: List[str]
    suggested_focus: str
    detected_at: datetime = Field(default_factory=datetime.utcnow)


class AnalyticsQuery(BaseModel):
    """Analytics query parameters."""
    user_id: Optional[str] = None
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    metric: str  # "fluency", "grammar", "vocabulary", "engagement"
    group_by: Optional[str] = None  # "day", "week", "month", "level"


class AnalyticsResponse(BaseModel):
    """Analytics response."""
    metric: str
    data: List[Dict[str, Any]]
    summary: Dict[str, Any]
    generated_at: datetime = Field(default_factory=datetime.utcnow)


class ExportDataRequest(BaseModel):
    """Request to export training data."""
    user_id: Optional[str] = None
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    task_types: Optional[List[str]] = None
    min_quality_score: float = 0.7
    format: str = "jsonl"  # jsonl, csv, parquet
    validated_only: bool = False


class ExportDataResponse(BaseModel):
    """Response with export data."""
    export_id: str
    file_url: str
    record_count: int
    format: str
    expires_at: datetime
