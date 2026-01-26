"""AI-related schemas.

These are intentionally lightweight so the core backend can be built without
depending on the AI service implementation details.
"""

from typing import Literal, Optional
from pydantic import BaseModel, Field


AIModelName = Literal["gemini", "huggingface", "qwen", "llama3", "auto"]


class AIChatRequest(BaseModel):
    user_id: str = Field(..., description="Stable user identifier")
    session_id: str = Field(..., description="Conversation/session identifier")
    message: str = Field(..., min_length=1, description="User message")
    model: AIModelName = Field("auto", description="Preferred model routing key")
    locale: Optional[str] = Field(None, description="Locale hint (e.g. vi-VN, en-US)")


class AIChatResponse(BaseModel):
    text: str
    model: Optional[str] = None
    request_id: Optional[str] = None
