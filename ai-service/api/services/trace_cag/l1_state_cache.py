"""SCAR-L1 state-certified reuse decisions for TraceCAG.

This module is intentionally pure: no Redis, no LLM calls, no graph service.
It answers one question for cache-gate orchestration: can this L1 candidate be
reused, patched, or must the request fall back to full reconstruction?
"""

from __future__ import annotations

from dataclasses import dataclass, field
import time


CERTIFICATE_SCHEMA_VERSION = 2
BASE_REQUIRED_DIMENSIONS = frozenset({
    "intent", "level", "profile_epoch", "policy_version", "kg_version", "answer_target",
})


@dataclass(frozen=True)
class L1Request:
    """State signature for the current request."""

    query_norm: str
    intent: str
    level: str
    profile_epoch: int
    session_turn: int
    concepts: set[str] = field(default_factory=set)
    entities: set[str] = field(default_factory=set)
    answer_target: str = ""
    relation_hints: set[str] = field(default_factory=set)
    evidence_hash: str = ""
    policy_version: str = ""
    kg_version: str = ""
    source_version: str = ""
    freshness_class: str = ""
    native_language: str = ""
    schema_version: int = CERTIFICATE_SCHEMA_VERSION
    required_dimensions: set[str] = field(default_factory=lambda: set(BASE_REQUIRED_DIMENSIONS))


@dataclass(frozen=True)
class L1Candidate:
    """State signature for an L1 cache candidate."""

    cache_key: str
    query_norm: str
    intent: str
    level: str
    profile_epoch: int
    session_turn: int
    concepts: set[str] = field(default_factory=set)
    entities: set[str] = field(default_factory=set)
    answer_target: str = ""
    relation_hints: set[str] = field(default_factory=set)
    evidence_hash: str = ""
    policy_version: str = ""
    kg_version: str = ""
    source_version: str = ""
    freshness_class: str = ""
    native_language: str = ""
    schema_version: int = CERTIFICATE_SCHEMA_VERSION
    required_dimensions: set[str] = field(default_factory=lambda: set(BASE_REQUIRED_DIMENSIONS))
    created_at: float = 0.0
    ttl: int = 3600


@dataclass(frozen=True)
class L1Decision:
    """SCAR-L1 ternary decision."""

    decision: str
    risk: float
    rank_score: float
    reasons: tuple[str, ...]
    safe_to_reuse: bool


def _jaccard(left: set[str], right: set[str]) -> float:
    if not left and not right:
        return 1.0
    return len(left & right) / max(len(left | right), 1)


def _dimension_value(subject: L1Request | L1Candidate, dimension: str):
    return subject.relation_hints if dimension == "relation_path" else getattr(subject, dimension, None)


def _missing(value: object) -> bool:
    return value is None or value == "" or value == set() or value == []


def decide_l1_reuse(
    request: L1Request,
    candidate: L1Candidate,
    *,
    now: float | None = None,
    tau_reuse: float = 0.25,
    tau_patch: float = 0.55,
    concept_floor: float = 0.50,
) -> L1Decision:
    """Decide whether an L1 candidate can be reused, patched, or rejected.

    Hard constraints protect learner/profile and task-state compatibility.
    Risk scoring then separates exact safe reuse from near-hit patching.
    """

    # Wall-clock: candidate.created_at is read back from Redis and may have
    # been written by a different process/host (monotonic()'s reference point
    # is undefined across processes per the stdlib docs).
    current_time = time.time() if now is None else now
    reasons: list[str] = []

    if candidate.schema_version != CERTIFICATE_SCHEMA_VERSION:
        return L1Decision("full", 1.0, 0.0, ("unsupported_certificate_schema",), False)

    required = set(request.required_dimensions) | set(candidate.required_dimensions) | BASE_REQUIRED_DIMENSIONS
    for dimension in sorted(required):
        if _missing(_dimension_value(request, dimension)) or _missing(_dimension_value(candidate, dimension)):
            reasons.append(f"missing_required:{dimension}")
    if reasons:
        return L1Decision("full", 1.0, 0.0, tuple(reasons), False)

    if request.level != candidate.level:
        reasons.append("mismatch:level")
    if request.native_language and candidate.native_language and request.native_language != candidate.native_language:
        reasons.append("mismatch:native_language")
    if request.profile_epoch != candidate.profile_epoch:
        reasons.append("mismatch:profile_epoch")
    if request.intent != candidate.intent:
        reasons.append("mismatch:intent")
    if request.answer_target != candidate.answer_target:
        reasons.append("mismatch:answer_target")
    for dimension in ("evidence_hash", "policy_version", "kg_version", "source_version", "freshness_class"):
        left = _dimension_value(request, dimension)
        right = _dimension_value(candidate, dimension)
        if (dimension in required or (left and right)) and left != right:
            reasons.append(f"mismatch:{dimension}")
    if ("relation_path" in required or (request.relation_hints and candidate.relation_hints)) and request.relation_hints != candidate.relation_hints:
        reasons.append("mismatch:relation_path")

    concept_overlap = _jaccard(request.concepts, candidate.concepts)
    if concept_overlap < concept_floor:
        reasons.append("concept_overlap_below_floor")

    age_ratio = min(
        max((current_time - candidate.created_at) / max(candidate.ttl, 1), 0.0),
        1.0,
    )
    if age_ratio >= 1.0:
        reasons.append("stale_candidate")

    entity_overlap = _jaccard(request.entities, candidate.entities)
    relation_overlap = _jaccard(request.relation_hints, candidate.relation_hints)
    intent_drift = 0.0 if request.intent == candidate.intent else 1.0

    risk = (
        0.30 * intent_drift
        + 0.25 * (1.0 - concept_overlap)
        + 0.20 * (1.0 - entity_overlap)
        + 0.15 * (1.0 - relation_overlap)
        + 0.10 * age_ratio
    )
    risk = max(0.0, min(1.0, risk))
    rank_score = (1.0 - risk) + (0.30 * concept_overlap) + (0.20 * entity_overlap)

    if reasons:
        return L1Decision("full", risk, rank_score, tuple(reasons), False)
    if request.query_norm == candidate.query_norm and risk <= tau_reuse:
        return L1Decision("reuse", risk, rank_score, ("exact_or_normalized_match",), True)
    if risk <= tau_patch:
        return L1Decision("patch", risk, rank_score, ("state_compatible_near_hit",), True)
    return L1Decision("full", risk, rank_score, ("risk_above_patch_threshold",), False)
