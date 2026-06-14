"""STT control messages, engine results, and outbound events."""

from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


class UseCase(str, Enum):
    CONVERSATION = "conversation"
    SPEAKING_PRACTICE = "speaking_practice"
    PRONUNCIATION_SCORING = "pronunciation_scoring"


class StartMessage(BaseModel):
    type: Literal["start"] = "start"
    session_id: str = Field(
        min_length=1,
        max_length=128,
        pattern=r"^[A-Za-z0-9_.-]+$",
    )
    user_id: Optional[str] = None
    sample_rate: Literal[16000] = 16000
    channels: Literal[1] = 1
    format: Literal["pcm16"] = "pcm16"
    language: str = "en"
    use_case: UseCase = UseCase.CONVERSATION
    client_started_at: Optional[int] = None


class ResumeMessage(BaseModel):
    type: Literal["resume"] = "resume"
    session_id: str
    last_seq: int = Field(ge=-1)


class AudioSegment(BaseModel):
    pcm16: bytes = Field(exclude=True)
    start_ms: int = Field(ge=0)
    end_ms: int = Field(gt=0)

    @property
    def duration_ms(self) -> int:
        return self.end_ms - self.start_ms


class PrimaryResult(BaseModel):
    text: str
    confidence: float = Field(ge=0, le=1)
    confidence_source: str = "heuristic"
    language: str = "en"
    source: str = "unknown"


class VerificationResult(PrimaryResult):
    segments: list[dict[str, Any]] = Field(default_factory=list)


class PartialTranscriptEvent(BaseModel):
    type: Literal["stt.partial"] = "stt.partial"
    session_id: str
    text: str
    start_ms: int
    end_ms: int
    confidence: float = Field(ge=0, le=1)
    source: str = "moonshine"
    is_final: Literal[False] = False


class CandidateTranscriptEvent(BaseModel):
    type: Literal["stt.candidate"] = "stt.candidate"
    session_id: str
    utterance_id: str
    text: str
    start_ms: int
    end_ms: int
    confidence: float = Field(ge=0, le=1)
    source: str = "moonshine"
    status: str = "pending_verify"


class FinalTranscriptEvent(BaseModel):
    type: Literal["stt.final"] = "stt.final"
    session_id: str
    user_id: Optional[str] = None
    utterance_id: str
    turn_id: str
    text: str
    original_text: Optional[str] = None
    start_ms: int
    end_ms: int
    confidence: float = Field(ge=0, le=1)
    confidence_source: str
    source: str
    verified: bool
    uncertain: bool
    needs_confirmation: bool
    language: str = "en"
    verify_reason: Optional[str] = None
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
