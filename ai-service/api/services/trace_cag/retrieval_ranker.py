"""
Online retrieval ranker for TraceCAG.

This module implements a model-agnostic, pairwise online ranker that blends
multiple retrieval signals (lexical, graph, semantic, recency) and updates
itself from explicit or weak supervision labels.
"""

from __future__ import annotations

import math
import threading
from dataclasses import dataclass
from typing import Any, Dict, List, Optional


from api.services.trace_cag.env_helpers import _clip01, _env_float, _env_int


def _sigmoid(value: float) -> float:
    if value >= 0:
        exp_neg = math.exp(-value)
        return 1.0 / (1.0 + exp_neg)
    exp_pos = math.exp(value)
    return exp_pos / (1.0 + exp_pos)


@dataclass(frozen=True)
class RankerConfig:
    learning_rate: float
    l2_penalty: float
    exploration: float
    max_training_items: int
    min_pairs: int


class OnlinePairwiseRetrievalRanker:
    """Pairwise logistic ranker with lightweight online updates."""

    def __init__(self, config: RankerConfig) -> None:
        self._config = config
        self._feature_keys = [
            "base_score",
            "body_overlap",
            "title_overlap",
            "anchor_coverage",
            "title_phrase",
            "title_token_recall",
            "kg_proximity",
            "vec_signal",
            "graph_signal",
            "memory_signal",
            "recency_signal",
            "external_penalty",
        ]
        self._weights: Dict[str, float] = {
            "base_score": 0.42,
            "body_overlap": 0.14,
            "title_overlap": 0.11,
            "anchor_coverage": 0.11,
            "title_phrase": 0.08,
            "title_token_recall": 0.07,
            "kg_proximity": 0.05,
            "vec_signal": 0.05,
            "graph_signal": 0.05,
            "memory_signal": 0.04,
            "recency_signal": 0.03,
            "external_penalty": -0.05,
        }
        self._item_seen: Dict[str, int] = {}
        self._updates: int = 0
        self._lock = threading.Lock()

    def score(self, *, item_id: str, features: Dict[str, float], allow_exploration: bool = False) -> float:
        with self._lock:
            linear = 0.0
            for key in self._feature_keys:
                linear += self._weights.get(key, 0.0) * float(features.get(key, 0.0))

            base_prob = _sigmoid(linear)

            if allow_exploration:
                total = max(1, self._updates)
                seen = max(0, self._item_seen.get(str(item_id), 0))
                bonus = self._config.exploration * math.sqrt(math.log(total + 2.0) / (seen + 1.0))
                return _clip01(base_prob + bonus)

            return _clip01(base_prob)

    def observe(self, candidates: List[Dict[str, Any]]) -> None:
        if not candidates:
            return

        labeled: List[Dict[str, Any]] = []
        for candidate in candidates[: max(1, self._config.max_training_items)]:
            label = candidate.get("label")
            features = candidate.get("features") or {}
            if label is None or not isinstance(features, dict):
                continue
            labeled.append(
                {
                    "item_id": str(candidate.get("item_id") or ""),
                    "label": float(label),
                    "features": {k: float(features.get(k, 0.0)) for k in self._feature_keys},
                }
            )

        positives = [entry for entry in labeled if entry["label"] >= 0.55]
        negatives = [entry for entry in labeled if entry["label"] <= 0.45]
        if not positives or not negatives:
            return

        with self._lock:
            gradients = {key: 0.0 for key in self._feature_keys}
            pair_count = 0

            for pos in positives:
                pos_features = pos["features"]
                for neg in negatives:
                    neg_features = neg["features"]
                    margin = 0.0
                    diff: Dict[str, float] = {}
                    for key in self._feature_keys:
                        delta = pos_features.get(key, 0.0) - neg_features.get(key, 0.0)
                        diff[key] = delta
                        margin += self._weights.get(key, 0.0) * delta

                    prob = _sigmoid(margin)
                    coeff = 1.0 - prob
                    for key in self._feature_keys:
                        gradients[key] += coeff * diff[key]
                    pair_count += 1

            if pair_count < max(1, self._config.min_pairs):
                return

            scale = 1.0 / float(pair_count)
            for key in self._feature_keys:
                grad = gradients[key] * scale
                reg = self._config.l2_penalty * self._weights.get(key, 0.0)
                update = self._config.learning_rate * (grad - reg)
                self._weights[key] = max(-3.0, min(3.0, self._weights.get(key, 0.0) + update))

            for entry in labeled:
                item_id = entry.get("item_id") or ""
                if item_id:
                    self._item_seen[item_id] = int(self._item_seen.get(item_id, 0)) + 1

            self._updates += 1

    def snapshot(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "weights": dict(self._weights),
                "updates": int(self._updates),
                "tracked_items": len(self._item_seen),
                "config": {
                    "learning_rate": self._config.learning_rate,
                    "l2_penalty": self._config.l2_penalty,
                    "exploration": self._config.exploration,
                    "max_training_items": self._config.max_training_items,
                    "min_pairs": self._config.min_pairs,
                },
            }


def _build_config() -> RankerConfig:
    return RankerConfig(
        learning_rate=max(0.001, _env_float("TRACECAG_RANKER_LEARNING_RATE", 0.045)),
        l2_penalty=max(0.0, _env_float("TRACECAG_RANKER_L2", 0.008)),
        exploration=max(0.0, _env_float("TRACECAG_RANKER_EXPLORATION", 0.06)),
        max_training_items=max(4, _env_int("TRACECAG_RANKER_MAX_TRAINING_ITEMS", 12)),
        min_pairs=max(1, _env_int("TRACECAG_RANKER_MIN_PAIRS", 2)),
    )


_RANKER_INSTANCE: Optional[OnlinePairwiseRetrievalRanker] = None
_RANKER_LOCK = threading.Lock()


def get_retrieval_ranker() -> OnlinePairwiseRetrievalRanker:
    global _RANKER_INSTANCE
    with _RANKER_LOCK:
        if _RANKER_INSTANCE is None:
            _RANKER_INSTANCE = OnlinePairwiseRetrievalRanker(_build_config())
        return _RANKER_INSTANCE