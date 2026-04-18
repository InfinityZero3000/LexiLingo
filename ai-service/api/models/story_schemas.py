from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field


class DifficultyLevel(str, Enum):
    A1 = "A1"
    A2 = "A2"
    B1 = "B1"
    B2 = "B2"
    C1 = "C1"
    C2 = "C2"


class LocalizedTitle(BaseModel):
    en: str
    vi: str


class ContextDescription(BaseModel):
    setting: str
    scenario: str
    objectives: List[str] = Field(default_factory=list)


class RolePersona(BaseModel):
    name: str
    role: str
    personality: str
    speaking_style: str
    background: str


class ConversationFlow(BaseModel):
    opening_prompt: str
    checkpoints: List[str] = Field(default_factory=list)


class Story(BaseModel):
    model_config = ConfigDict(extra="allow")

    story_id: str
    title: LocalizedTitle
    difficulty_level: DifficultyLevel
    category: str
    context_description: Optional[ContextDescription] = None
    role_persona: Optional[RolePersona] = None
    conversation_flow: ConversationFlow
    vocabulary_list: List[Dict[str, Any]] = Field(default_factory=list)
    grammar_points: List[Dict[str, Any]] = Field(default_factory=list)
    estimated_minutes: int = 15
    cover_image_url: Optional[str] = None
    suggested_prompts: List[str] = Field(default_factory=list)
    tags: List[str] = Field(default_factory=list)
    is_published: bool = True
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class StoryListItem(BaseModel):
    story_id: str
    title: LocalizedTitle
    difficulty_level: DifficultyLevel
    category: str
    estimated_minutes: int = 15
    cover_image_url: Optional[str] = None
    suggested_prompts: List[str] = Field(default_factory=list)
    tags: List[str] = Field(default_factory=list)


class ListStoriesRequest(BaseModel):
    category: Optional[str] = None
    difficulty_level: Optional[DifficultyLevel] = None
    limit: int = 20
    skip: int = 0


class ListStoriesResponse(BaseModel):
    stories: List[StoryListItem]
    total: int


class StartTopicSessionRequest(BaseModel):
    user_id: str
    story_id: str
    session_title: Optional[str] = None
    preferred_llm: Optional[str] = None


class StartTopicSessionResponse(BaseModel):
    session_id: str
    story: StoryListItem
    role_persona: Optional[RolePersona] = None
    opening_message: str
    vocabulary_preview: List[Dict[str, Any]] = Field(default_factory=list)
    created_at: datetime


class TopicChatRequest(BaseModel):
    user_id: str
    message: str


class TopicChatResponse(BaseModel):
    message_id: str
    ai_response: str
    clean_response: Optional[str] = None
    educational_hints: Optional[Dict[str, Any]] = None
    processing_time_ms: int
    llm_metadata: Optional[Dict[str, Any]] = None


class WarmTopicCacheRequest(BaseModel):
    story_id: str
    user_id: str


class WarmTopicCacheResponse(BaseModel):
    success: bool
    topic_id: str
    message: str
    bundle_size_kb: float
