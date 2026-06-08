"""SCAR-L1 state-certified reuse decisions for TraceCAG.

This module is intentionally pure: no Redis, no LLM calls, no graph service.
It answers one question for cache-gate orchestration: can this L1 candidate be
reused, patched, or must the request fall back to full reconstruction?
"""

from __future__ import annotations

from dataclasses import dataclass, field
import time


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


def _empty_or_equal(left: str, right: str) -> bool:
    return not left or not right or left == right


def _compatible_relations(left: set[str], right: set[str]) -> bool:
    if not left or not right:
        return True
    return left == right


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

    current_time = time.monotonic() if now is None else now
    reasons: list[str] = []

    if request.level != candidate.level:
        reasons.append("level_mismatch")
    if request.profile_epoch != candidate.profile_epoch:
        reasons.append("profile_epoch_mismatch")
    if not _empty_or_equal(request.intent, candidate.intent):
        reasons.append("intent_mismatch")
    if not _empty_or_equal(request.answer_target, candidate.answer_target):
        reasons.append("answer_target_mismatch")
    if not _empty_or_equal(request.evidence_hash, candidate.evidence_hash):
        reasons.append("evidence_mismatch")
    if not _compatible_relations(request.relation_hints, candidate.relation_hints):
        reasons.append("relation_mismatch")

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
    intent_drift = 0.0 if _empty_or_equal(request.intent, candidate.intent) else 1.0

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
