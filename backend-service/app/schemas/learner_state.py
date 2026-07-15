"""Internal service contracts for sparse learner state."""

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

MAX_PAYLOAD_BYTES = 4096
MAX_FUTURE_SKEW = timedelta(minutes=5)
ALLOWED_OBSERVATION_PAYLOAD_KEYS = {
    "algorithm_version",
    "error_count",
    "migration_version",
    "source",
}


class LearnerStateBatchGetRequest(BaseModel):
    user_id: UUID
    concept_ids: list[str] = Field(max_length=100)

    @field_validator("concept_ids")
    @classmethod
    def validate_concept_ids(cls, values: list[str]) -> list[str]:
        if any(not value or len(value) > 255 for value in values):
            raise ValueError("concept IDs must contain 1..255 characters")
        return list(dict.fromkeys(values))


class LearnerConceptStateResponse(BaseModel):
    concept_id: str
    mastery_probability: float
    stability_days: float
    difficulty: float
    attempt_count: int
    correct_count: int
    error_count: int
    last_interacted_at: datetime | None
    next_review_at: datetime | None
    state_version: int
    algorithm_version: str


class LearnerStateBatchGetResponse(BaseModel):
    state_epoch: int
    states: list[LearnerConceptStateResponse]


class LearnerObservationRequest(BaseModel):
    event_id: str = Field(min_length=64, max_length=64, pattern=r"^[0-9a-f]{64}$")
    user_id: UUID
    session_id: str | None = Field(default=None, max_length=255)
    concept_id: str = Field(min_length=1, max_length=255)
    outcome: str = Field(pattern=r"^(correct|incorrect)$")
    confidence: float = Field(ge=0.0, le=1.0)
    observed_at: datetime
    payload: dict | None = None

    @model_validator(mode="after")
    def validate_time_and_payload(self):
        if self.observed_at.tzinfo is None:
            raise ValueError("observed_at must be timezone-aware")
        if self.observed_at > datetime.now(UTC) + MAX_FUTURE_SKEW:
            raise ValueError("observed_at is too far in the future")
        if self.payload is not None:
            encoded = json.dumps(self.payload, separators=(",", ":"), ensure_ascii=False)
            if len(encoded.encode("utf-8")) > MAX_PAYLOAD_BYTES:
                raise ValueError(f"payload exceeds {MAX_PAYLOAD_BYTES} bytes")
            unknown = set(self.payload) - ALLOWED_OBSERVATION_PAYLOAD_KEYS
            if unknown:
                raise ValueError("payload contains unsupported fields")
            if any(isinstance(value, (dict, list)) for value in self.payload.values()):
                raise ValueError("nested observation payload values are not allowed")
        return self


class LearnerObservationBatchRequest(BaseModel):
    observations: list[LearnerObservationRequest] = Field(max_length=100)


class LearnerObservationBatchResponse(BaseModel):
    accepted_event_ids: list[str]
    duplicate_event_ids: list[str]
