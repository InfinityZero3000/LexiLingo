"""Rule/score layer for the recommender — pure functions, no I/O.

Every signal here is a number in [0,1]; the linear blend is the only place
weights live, so the online ranker can later replace them wholesale.
"""

from __future__ import annotations

import math
from typing import Any, Iterable, Sequence

CEFR_ORDER = {"A1": 0, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5}

# Mastery assumed for a concept the learner has never been observed on. Low
# enough that unseen material outranks half-learned material, high enough that
# it does not outrank a concept we know is weak.
UNSEEN_MASTERY = 0.30

# Krashen i+1: one step above current level is the target, two steps is noise.
# A multiplicative gate — a strong topic match must not drag a C1 text in front
# of an A2 learner, which is what adding this as a term would allow.
_CEFR_FIT = {-2: 0.25, -1: 0.60, 0: 0.90, 1: 1.00, 2: 0.35}

DEFAULT_WEIGHTS = {
    "sequential": 0.00,  # SASRec/EASE slot — stays 0 until Phase 3
    "similarity": 0.25,
    "mastery_gap": 0.30,
    "due": 0.25,
    "topic": 0.20,
}


def cefr_fit(user_level: str | None, item_level: str | None) -> float:
    """Multiplicative difficulty gate."""
    if not item_level:
        return 0.85  # unlabelled content: mild penalty, never a free pass
    user_idx = CEFR_ORDER.get((user_level or "A1").upper())
    item_idx = CEFR_ORDER.get(item_level.upper())
    if user_idx is None or item_idx is None:
        return 0.85
    return _CEFR_FIT.get(item_idx - user_idx, 0.10)


def topic_affinity_score(
    item_topic: str | None,
    item_tags: Sequence[str] | None,
    affinity: dict[str, float],
) -> float:
    """Best match between the item's topic/tags and the learner's affinity map."""
    if not affinity:
        return 0.0
    keys = [item_topic] + list(item_tags or [])
    return max(
        (affinity.get(key.strip().lower(), 0.0) for key in keys if key),
        default=0.0,
    )


def mastery_gap(concept_ids: Sequence[str], mastery: dict[str, float]) -> float:
    """How much of this item the learner has not mastered yet."""
    if not concept_ids:
        return 0.5  # no concept labels — neutral, not a bonus
    total = sum(1.0 - mastery.get(cid, UNSEEN_MASTERY) for cid in concept_ids)
    return _clip01(total / len(concept_ids))


def due_score(concept_ids: Sequence[str], due_concepts: Iterable[str]) -> float:
    """Fraction of the item's concepts whose FSRS review is overdue."""
    if not concept_ids:
        return 0.0
    due = set(due_concepts)
    if not due:
        return 0.0
    return sum(1.0 for cid in concept_ids if cid in due) / len(concept_ids)


def recency_penalty(seen_hours_ago: float | None, half_life_hours: float = 48.0) -> float:
    """1.0 for never-seen, approaching 0 for just-seen. Multiplicative."""
    if seen_hours_ago is None:
        return 1.0
    if seen_hours_ago < 0:
        seen_hours_ago = 0.0
    return _clip01(1.0 - math.exp(-seen_hours_ago * math.log(2) / half_life_hours))


def score_candidate(
    candidate: dict[str, Any],
    profile: dict[str, Any],
    *,
    weights: dict[str, float] | None = None,
    similarity: float = 0.0,
    sequential: float = 0.0,
) -> dict[str, Any]:
    """Blend every signal into one score, with the two gates applied last."""
    w = {**DEFAULT_WEIGHTS, **(weights or {})}
    concept_ids = candidate.get("concept_ids") or []

    features = {
        "sequential": _clip01(sequential),
        "similarity": _clip01(similarity),
        "mastery_gap": mastery_gap(concept_ids, profile.get("mastery") or {}),
        "due": due_score(concept_ids, profile.get("due_concepts") or []),
        "topic": topic_affinity_score(
            candidate.get("topic"),
            candidate.get("tags"),
            profile.get("topic_affinity") or {},
        ),
    }

    base = sum(w[key] * value for key, value in features.items())
    gate_cefr = cefr_fit(profile.get("level"), candidate.get("level"))
    gate_recency = recency_penalty(candidate.get("seen_hours_ago"))

    return {
        **candidate,
        "score": round(base * gate_cefr * gate_recency, 6),
        "features": {
            **{k: round(v, 4) for k, v in features.items()},
            "cefr_fit": gate_cefr,
            "recency": round(gate_recency, 4),
        },
    }


def mmr_rerank(
    scored: list[dict[str, Any]],
    k: int,
    *,
    lambda_: float = 0.75,
    similarity_of=None,
) -> list[dict[str, Any]]:
    """Maximal Marginal Relevance: relevance minus redundancy.

    Without it the top-K collapses onto one topic — the learner's favourite
    topic wins every slot, which is exactly the filter bubble the affinity
    signal creates on its own.
    """
    if k <= 0 or not scored:
        return []
    pool = sorted(scored, key=lambda item: item["score"], reverse=True)
    similarity_of = similarity_of or _topic_overlap
    selected: list[dict[str, Any]] = [pool.pop(0)]

    while pool and len(selected) < k:
        best_idx, best_value = 0, -math.inf
        for idx, candidate in enumerate(pool):
            redundancy = max(similarity_of(candidate, chosen) for chosen in selected)
            value = lambda_ * candidate["score"] - (1.0 - lambda_) * redundancy
            if value > best_value:
                best_idx, best_value = idx, value
        selected.append(pool.pop(best_idx))
    return selected


def enforce_type_quota(
    ranked: list[dict[str, Any]],
    pool: list[dict[str, Any]],
    required_types: Sequence[str],
) -> list[dict[str, Any]]:
    """Guarantee one slot per content type when the pool can supply it.

    A pure score ranking hands every slot to whichever type happens to score
    highest — usually vocabulary, because it carries the most concept labels.
    """
    if not required_types:
        return ranked
    present = {item.get("item_type") for item in ranked}
    ranked_ids = {item.get("item_id") for item in ranked}
    result = list(ranked)

    for item_type in required_types:
        if item_type in present:
            continue
        replacement = next(
            (
                item
                for item in sorted(pool, key=lambda i: i["score"], reverse=True)
                if item.get("item_type") == item_type
                and item.get("item_id") not in ranked_ids
            ),
            None,
        )
        if replacement is None:
            continue
        # Drop the weakest item of an over-represented type, never the top pick.
        victim = _weakest_over_represented(result, required_types)
        if victim is None:
            continue
        result.remove(victim)
        result.append(replacement)
        ranked_ids.add(replacement.get("item_id"))
    return sorted(result, key=lambda item: item["score"], reverse=True)


def _weakest_over_represented(
    ranked: list[dict[str, Any]], required_types: Sequence[str]
) -> dict[str, Any] | None:
    counts: dict[str, int] = {}
    for item in ranked:
        counts[item.get("item_type")] = counts.get(item.get("item_type"), 0) + 1
    over = [item for item in ranked if counts.get(item.get("item_type"), 0) > 1]
    if not over:
        return None
    return min(over, key=lambda item: item["score"])


def _topic_overlap(left: dict[str, Any], right: dict[str, Any]) -> float:
    if left.get("item_type") == right.get("item_type"):
        if left.get("topic") and left.get("topic") == right.get("topic"):
            return 1.0
        return 0.5
    if left.get("topic") and left.get("topic") == right.get("topic"):
        return 0.7
    return 0.0


def _clip01(value: float) -> float:
    return 0.0 if value < 0.0 else (1.0 if value > 1.0 else value)


def demo() -> None:
    profile = {
        "level": "A2",
        "mastery": {"vocab:travel": 0.9, "grammar:past_simple": 0.2},
        "due_concepts": ["grammar:past_simple"],
        "topic_affinity": {"travel": 1.0, "business": 0.2},
    }

    # The CEFR gate is multiplicative: a perfect topic match at C1 must lose
    # to a mediocre topic match at the learner's own level.
    hot_but_hard = score_candidate(
        {"item_id": "1", "item_type": "course", "topic": "travel", "level": "C1",
         "concept_ids": []},
        profile,
    )
    lukewarm_but_fitting = score_candidate(
        {"item_id": "2", "item_type": "course", "topic": "business", "level": "B1",
         "concept_ids": ["grammar:past_simple"]},
        profile,
    )
    assert lukewarm_but_fitting["score"] > hot_but_hard["score"], (
        lukewarm_but_fitting["score"], hot_but_hard["score"]
    )

    # A mastered concept must not outrank an overdue weak one.
    mastered = score_candidate(
        {"item_id": "3", "item_type": "vocab", "topic": "travel", "level": "A2",
         "concept_ids": ["vocab:travel"]},
        profile,
    )
    weak_due = score_candidate(
        {"item_id": "4", "item_type": "vocab", "topic": "travel", "level": "A2",
         "concept_ids": ["grammar:past_simple"]},
        profile,
    )
    assert weak_due["score"] > mastered["score"]

    # Just-seen content is suppressed.
    fresh = score_candidate(
        {"item_id": "5", "item_type": "video", "topic": "travel", "level": "A2",
         "concept_ids": []},
        profile,
    )
    just_seen = score_candidate(
        {"item_id": "6", "item_type": "video", "topic": "travel", "level": "A2",
         "concept_ids": [], "seen_hours_ago": 0.5},
        profile,
    )
    assert fresh["score"] > just_seen["score"]

    # MMR must break a single-topic sweep.
    same_topic = [
        score_candidate(
            {"item_id": str(i), "item_type": "course", "topic": "travel",
             "level": "A2", "concept_ids": []},
            profile,
        )
        for i in range(5)
    ]
    other_topic = score_candidate(
        {"item_id": "x", "item_type": "vocab", "topic": "business", "level": "A2",
         "concept_ids": ["grammar:past_simple"]},
        profile,
    )
    picked = mmr_rerank(same_topic + [other_topic], k=3)
    assert any(item["item_id"] == "x" for item in picked), picked

    # Quota pulls in a missing type.
    ranked = enforce_type_quota(picked, same_topic + [other_topic], ["course", "vocab"])
    assert {"course", "vocab"} <= {item["item_type"] for item in ranked}

    print("rec_graph.scoring: all checks passed")


if __name__ == "__main__":
    demo()
