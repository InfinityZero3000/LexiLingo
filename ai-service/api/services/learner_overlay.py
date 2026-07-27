"""Request-local merge and ranking of shared concepts with sparse learner state."""

from __future__ import annotations

from copy import deepcopy
from datetime import UTC, datetime
from math import exp, isfinite
from typing import Any


def _clip(value: Any, default: float = 0.0) -> float:
    try:
        number = float(value)
        if not isfinite(number):
            return default
        return max(0.0, min(1.0, number))
    except (TypeError, ValueError):
        return default


def _as_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def rank_with_learner_overlay(
    candidates: list[dict[str, Any]],
    learner_states: dict[str, dict[str, Any]],
    *,
    now: datetime,
    top_k: int = 60,
    prior_mastery: float = 0.5,
) -> list[dict[str, Any]]:
    """Return a bounded ranked copy; shared candidate input is never mutated."""
    ranked: list[tuple[float, int, str, dict[str, Any]]] = []
    normalized_now = now if now.tzinfo is not None else now.replace(tzinfo=UTC)
    for original_index, candidate in enumerate(candidates[: max(0, top_k * 4)]):
        concept_id = str(candidate.get("concept_id") or candidate.get("id") or "")
        if not concept_id:
            continue
        state = learner_states.get(concept_id)
        mastery = _clip(
            state.get("mastery_probability") if state else prior_mastery,
            prior_mastery,
        )
        raw_stability = (state or {}).get("stability_days", 1.0)
        try:
            stability = float(raw_stability)
            if not isfinite(stability):
                stability = 1.0
        except (TypeError, ValueError):
            stability = 1.0
        stability = max(0.25, stability)
        last_seen = _as_datetime((state or {}).get("last_interacted_at"))
        elapsed_days = 0.0
        if last_seen is not None:
            normalized_last_seen = (
                last_seen if last_seen.tzinfo is not None else last_seen.replace(tzinfo=UTC)
            )
            elapsed_days = max(
                0.0, (normalized_now - normalized_last_seen).total_seconds() / 86_400.0
            )
        forgetting_risk = _clip(1.0 - exp(-elapsed_days / stability))
        relevance = _clip(candidate.get("relevance", candidate.get("score", 0.0)))
        recent_error = _clip(candidate.get("recent_error_signal", 0.0))
        prerequisite_readiness = _clip(candidate.get("prerequisite_readiness", 1.0), 1.0)
        score = (
            0.50 * relevance
            + 0.25 * (1.0 - mastery)
            + 0.15 * forgetting_risk
            + 0.10 * recent_error
            - 0.20 * (1.0 - prerequisite_readiness)
        )
        enriched = deepcopy(candidate)
        enriched.update(
            learner_mastery=mastery,
            forgetting_risk=forgetting_risk,
            learner_score=score,
            learner_state_source="persisted" if state else "prior",
        )
        ranked.append((score, original_index, concept_id, enriched))

    ranked.sort(key=lambda item: (-item[0], item[1], item[2]))
    return [item[3] for item in ranked[: max(0, top_k)]]
