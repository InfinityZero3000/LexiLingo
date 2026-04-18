from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field


class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="allow")

    role: str
    content: str
    timestamp: datetime


class CreateSessionRequest(BaseModel):
    user_id: str
    title: Optional[str] = None


class CreateSessionResponse(BaseModel):
    session_id: str
    created_at: datetime


class SendMessageRequest(BaseModel):
    session_id: str
    user_id: str
    message: str


class SendMessageResponse(BaseModel):
    message_id: str
    response: str
    metadata: Dict[str, Any] = Field(default_factory=dict)


class UserStats(BaseModel):
    total_interactions: int = 0
    avg_fluency_score: float = 0.0
    common_errors: List[str] = Field(default_factory=list)
    improvement_rate: Dict[str, Any] = Field(default_factory=dict)
    study_streak_days: int = 0


class UserLearningPattern(BaseModel):
    model_config = ConfigDict(extra="allow")

    user_id: str
    analyzed_at: Optional[datetime] = None
    stats: Optional[UserStats] = None


class LogInteractionRequest(BaseModel):
    model_config = ConfigDict(extra="allow")

    user_id: str
    session_id: Optional[str] = None
    input_text: Optional[str] = None
    ai_response: Optional[str] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)
    feedback: Optional[Dict[str, Any]] = None


class LogInteractionResponse(BaseModel):
    interaction_id: str
    message: str


class ErrorResponse(BaseModel):
    error: str
    detail: Optional[str] = None
