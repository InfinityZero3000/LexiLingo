"""Stable request and response contracts for TRACE-CAG."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, field
from typing import Any, Mapping


@dataclass(slots=True)
class TraceCAGRequest:
    """Portable input contract for any TRACE-CAG implementation."""

    user_input: str
    session_id: str = "tracecag-session"
    user_id: str | None = None
    input_type: str = "text"
    learner_profile: dict[str, Any] | None = None
    conversation_history: list[dict[str, Any]] | None = None
    stt_final: dict[str, Any] | None = None
    cache_policy: str = "on"
    retrieval_policy: str = "full"
    diagnosis_policy: str = "auto"
    generation_policy: str = "auto"
    benchmark_task: str | None = None
    benchmark_context: str | None = None
    benchmark_metadata: dict[str, Any] | None = None
    kg_seed_concepts: list[str] | None = None
    return_raw_state: bool = False
    metadata: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_text(
        cls,
        text: str,
        *,
        session_id: str = "tracecag-session",
        **kwargs: Any,
    ) -> "TraceCAGRequest":
        """Convenience constructor for simple text calls."""

        return cls(user_input=text, session_id=session_id, **kwargs)

    def to_pipeline_kwargs(self) -> dict[str, Any]:
        """Map the portable request to the current LexiLingo pipeline signature."""

        kwargs: dict[str, Any] = {
            "user_input": self.user_input,
            "session_id": self.session_id,
            "user_id": self.user_id,
            "input_type": self.input_type,
            "learner_profile": deepcopy(self.learner_profile),
            "conversation_history": deepcopy(self.conversation_history),
            "stt_final": deepcopy(self.stt_final),
            "cache_policy": self.cache_policy,
            "retrieval_policy": self.retrieval_policy,
            "diagnosis_policy": self.diagnosis_policy,
            "generation_policy": self.generation_policy,
            "benchmark_task": self.benchmark_task,
            "benchmark_context": self.benchmark_context,
            "benchmark_metadata": deepcopy(self.benchmark_metadata),
            "kg_seed_concepts": deepcopy(self.kg_seed_concepts),
            "return_raw_state": self.return_raw_state,
        }
        return {key: value for key, value in kwargs.items() if value is not None}


@dataclass(slots=True)
class TraceCAGResponse:
    """Portable output contract normalized from any TRACE-CAG implementation."""

    tutor_response: str = ""
    corrections: list[dict[str, Any]] = field(default_factory=list)
    linked_concepts: list[Any] = field(default_factory=list)
    action_plan: list[dict[str, Any]] = field(default_factory=list)
    vietnamese_hint: str | None = None
    pronunciation_tip: str | None = None
    scores: dict[str, Any] = field(default_factory=dict)
    action: dict[str, Any] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)
    audio: dict[str, Any] | None = None
    raw_state: dict[str, Any] | None = None
    error: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_mapping(
        cls,
        payload: Mapping[str, Any] | "TraceCAGResponse",
        *,
        raw_state: Mapping[str, Any] | None = None,
    ) -> "TraceCAGResponse":
        """Normalize a dict response or raw pipeline state into this contract."""

        if isinstance(payload, TraceCAGResponse):
            response = payload.copy()
            if raw_state is not None:
                response.raw_state = deepcopy(dict(raw_state))
            return response

        data = dict(payload)
        known = {
            "tutor_response",
            "corrections",
            "linked_concepts",
            "action_plan",
            "vietnamese_hint",
            "pronunciation_tip",
            "scores",
            "action",
            "metadata",
            "audio",
            "raw_state",
            "error",
        }
        metadata = deepcopy(data.get("metadata") or {})
        if not metadata:
            metadata = {
                "latency_ms": data.get("latency_ms", 0),
                "path": data.get("path", "slow"),
                "cache_hit": data.get("cache_hit", False),
                "cache_decision": data.get("cache_decision", "full"),
                "cache_layer": data.get("cache_layer", "none"),
            }

        return cls(
            tutor_response=str(data.get("tutor_response") or ""),
            corrections=deepcopy(data.get("corrections") or []),
            linked_concepts=deepcopy(data.get("linked_concepts") or data.get("kg_seed_concepts") or []),
            action_plan=deepcopy(data.get("action_plan") or []),
            vietnamese_hint=data.get("vietnamese_hint"),
            pronunciation_tip=data.get("pronunciation_tip"),
            scores=deepcopy(data.get("scores") or {}),
            action=deepcopy(data.get("action") or {}),
            metadata=metadata,
            audio=deepcopy(data.get("audio")),
            raw_state=deepcopy(dict(raw_state or data.get("raw_state") or {})) or None,
            error=data.get("error"),
            extra={key: deepcopy(value) for key, value in data.items() if key not in known},
        )

    def copy(self) -> "TraceCAGResponse":
        """Return a detached copy that callers can mutate safely."""

        return TraceCAGResponse.from_mapping(self.to_dict(include_raw_state=True))

    def to_dict(self, *, include_raw_state: bool = False) -> dict[str, Any]:
        """Serialize to a plain dict suitable for API responses."""

        payload: dict[str, Any] = {
            "tutor_response": self.tutor_response,
            "corrections": deepcopy(self.corrections),
            "linked_concepts": deepcopy(self.linked_concepts),
            "action_plan": deepcopy(self.action_plan),
            "vietnamese_hint": self.vietnamese_hint,
            "pronunciation_tip": self.pronunciation_tip,
            "scores": deepcopy(self.scores),
            "action": deepcopy(self.action),
            "metadata": deepcopy(self.metadata),
            "audio": deepcopy(self.audio),
            "error": self.error,
            **deepcopy(self.extra),
        }
        if include_raw_state and self.raw_state is not None:
            payload["raw_state"] = deepcopy(self.raw_state)
        return payload
