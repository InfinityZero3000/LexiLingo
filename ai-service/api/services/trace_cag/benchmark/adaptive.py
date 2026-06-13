"""
Adaptive controller for benchmark-mode evaluation.

Implements a constrained online bandit that selects a quality/speed profile
(fast | balanced | quality) per request and updates reward estimates from
benchmark feedback.
"""

from __future__ import annotations

import random
import threading
from dataclasses import dataclass
from typing import Any, Dict

from api.services.trace_cag.env_helpers import _clip01, _env_float
from api.services.trace_cag.provider_state import _provider_cooldown_seconds, _provider_is_disabled
from api.services.trace_cag.benchmark.ranking import _extract_query_anchors, _question_complexity_score
from api.services.trace_cag.state import TraceCAGState

# PCC thresholds — mirrors nodes_v2 constants; read from env so they stay in sync.
_TAU_REUSE = _env_float("TRACECAG_PCC_TAU_REUSE", 0.25)
_TAU_PATCH = _env_float("TRACECAG_PCC_TAU_PATCH", 0.55)

_CEFR_ORD: Dict[str, int] = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}


def _cefr_distance(a: str, b: str) -> int:
    return abs(_CEFR_ORD.get(a, 3) - _CEFR_ORD.get(b, 3))


@dataclass(frozen=True)
class _AdaptiveProfileConfig:
    name: str
    tau_reuse_delta: float
    tau_patch_delta: float
    evidence_budget_delta: int
    support_floor: float
    quality_factor: float
    retrieval_factor: float
    latency_cost: float
    reuse_risk_cost: float


_ADAPTIVE_PROFILES: Dict[str, _AdaptiveProfileConfig] = {
    "fast": _AdaptiveProfileConfig(
        name="fast",
        tau_reuse_delta=-0.06,
        tau_patch_delta=-0.04,
        evidence_budget_delta=-1,
        support_floor=0.36,
        quality_factor=0.86,
        retrieval_factor=0.90,
        latency_cost=0.40,
        reuse_risk_cost=0.32,
    ),
    "balanced": _AdaptiveProfileConfig(
        name="balanced",
        tau_reuse_delta=0.00,
        tau_patch_delta=0.00,
        evidence_budget_delta=0,
        support_floor=0.40,
        quality_factor=1.00,
        retrieval_factor=1.00,
        latency_cost=0.62,
        reuse_risk_cost=0.20,
    ),
    "quality": _AdaptiveProfileConfig(
        name="quality",
        tau_reuse_delta=0.04,
        tau_patch_delta=0.08,
        evidence_budget_delta=0,
        support_floor=0.42,
        quality_factor=1.06,
        retrieval_factor=1.06,
        latency_cost=0.88,
        reuse_risk_cost=0.14,
    ),
}

_ADAPTIVE_STATE_LOCK = threading.Lock()
_ADAPTIVE_PROFILE_BIAS: Dict[str, float] = {name: 0.0 for name in _ADAPTIVE_PROFILES}
_ADAPTIVE_PROFILE_COUNTS: Dict[str, int] = {name: 0 for name in _ADAPTIVE_PROFILES}
_ADAPTIVE_AVG_REWARD: float = 0.0
_ADAPTIVE_DUAL_LATENCY: float = 0.0
_ADAPTIVE_DUAL_INCORRECT: float = 0.0
_ADAPTIVE_UPDATE_STEPS: int = 0


def _provider_pressure_score() -> float:
    providers = ("groq", "gemini", "ollama")
    disabled = sum(1 for provider in providers if _provider_is_disabled(provider))
    max_cooldown = max((_provider_cooldown_seconds(provider) for provider in providers), default=0.0)
    cooldown_component = min(1.0, max_cooldown / max(1.0, _env_float("TRACECAG_ADAPTIVE_COOLDOWN_SCALE", 120.0)))
    disabled_component = min(1.0, disabled / max(len(providers), 1))
    return _clip01((0.65 * cooldown_component) + (0.35 * disabled_component))


def _adaptive_mode_enabled(state: TraceCAGState, benchmark_mode: str = "") -> bool:
    retrieval_policy = str(state.get("retrieval_policy") or "").strip().lower()
    if retrieval_policy == "adaptive":
        return True
    if str(benchmark_mode or "").strip().lower() == "trace-cag_adaptive":
        return True
    return False


def _adaptive_context_features(
    *,
    state: TraceCAGState,
    user_input: str,
    benchmark_task: str,
    benchmark_metadata: Dict[str, Any],
) -> Dict[str, float]:
    word_count = len(str(user_input or "").split())
    complexity = _question_complexity_score(user_input) / 4.0
    anchor_density = min(1.0, len(_extract_query_anchors(user_input)) / 4.0)
    question_len = min(1.0, word_count / 20.0)
    provider_pressure = _provider_pressure_score()
    task_is_multihop = 1.0 if benchmark_task == "multihop_qa" else 0.0

    request_level = str(benchmark_metadata.get("request_level") or state.get("learner_profile", {}).get("level") or "B1")
    cached_level = str(benchmark_metadata.get("cached_level") or request_level)
    level_gap = min(1.0, _cefr_distance(request_level, cached_level) / 3.0)

    return {
        "complexity": _clip01(complexity),
        "anchor_density": _clip01(anchor_density),
        "question_len": _clip01(question_len),
        "provider_pressure": _clip01(provider_pressure),
        "task_is_multihop": _clip01(task_is_multihop),
        "level_gap": _clip01(level_gap),
    }


def _adaptive_weighting() -> tuple[float, float, float]:
    f1_w = _env_float("TRACECAG_ADAPTIVE_W_F1", 0.52)
    retrieval_w = _env_float("TRACECAG_ADAPTIVE_W_RETRIEVAL", 0.31)
    pcc_w = _env_float("TRACECAG_ADAPTIVE_W_PCC", 0.17)
    total = max(f1_w + retrieval_w + pcc_w, 1e-6)
    return f1_w / total, retrieval_w / total, pcc_w / total


def _adaptive_objective(
    profile: _AdaptiveProfileConfig,
    *,
    features: Dict[str, float],
    bias: float,
    dual_latency: float,
    dual_incorrect: float,
) -> float:
    quality_base = (
        (0.42 * features.get("complexity", 0.0))
        + (0.28 * features.get("anchor_density", 0.0))
        + (0.20 * features.get("task_is_multihop", 0.0))
        + (0.10 * features.get("question_len", 0.0))
    )
    retrieval_base = (
        (0.48 * features.get("anchor_density", 0.0))
        + (0.34 * features.get("complexity", 0.0))
        + (0.18 * features.get("task_is_multihop", 0.0))
    )
    safety_base = 1.0 - (
        (0.60 * features.get("provider_pressure", 0.0))
        + (0.40 * features.get("level_gap", 0.0))
    )

    quality_signal = _clip01(quality_base) * profile.quality_factor
    retrieval_signal = _clip01(retrieval_base) * profile.retrieval_factor
    safety_signal = _clip01(safety_base)

    w_f1, w_retrieval, w_pcc = _adaptive_weighting()
    utility = (w_f1 * quality_signal) + (w_retrieval * retrieval_signal) + (w_pcc * safety_signal)
    utility -= dual_latency * profile.latency_cost
    utility -= dual_incorrect * profile.reuse_risk_cost
    utility += bias
    return utility


def _choose_adaptive_profile(
    *,
    state: TraceCAGState,
    user_input: str,
    benchmark_task: str,
    benchmark_mode: str,
    benchmark_metadata: Dict[str, Any],
) -> Dict[str, Any]:
    if not _adaptive_mode_enabled(state, benchmark_mode):
        return {}

    features = _adaptive_context_features(
        state=state,
        user_input=user_input,
        benchmark_task=benchmark_task,
        benchmark_metadata=benchmark_metadata,
    )

    with _ADAPTIVE_STATE_LOCK:
        bias_map = dict(_ADAPTIVE_PROFILE_BIAS)
        dual_latency = float(_ADAPTIVE_DUAL_LATENCY)
        dual_incorrect = float(_ADAPTIVE_DUAL_INCORRECT)
        snapshot = {
            "dual_latency": dual_latency,
            "dual_incorrect": dual_incorrect,
            "avg_reward": float(_ADAPTIVE_AVG_REWARD),
            "updates": int(_ADAPTIVE_UPDATE_STEPS),
        }

    objective_map: Dict[str, float] = {}
    for profile_name, profile in _ADAPTIVE_PROFILES.items():
        objective_map[profile_name] = _adaptive_objective(
            profile,
            features=features,
            bias=bias_map.get(profile_name, 0.0),
            dual_latency=dual_latency,
            dual_incorrect=dual_incorrect,
        )

    epsilon = _clip01(_env_float("TRACECAG_ADAPTIVE_EPSILON", 0.03))
    explore = random.random() < epsilon
    if explore:
        chosen_profile = random.choice(list(_ADAPTIVE_PROFILES.keys()))
    else:
        chosen_profile = max(objective_map.items(), key=lambda item: item[1])[0]

    config = _ADAPTIVE_PROFILES[chosen_profile]
    tau_reuse = max(0.05, min(0.85, _TAU_REUSE + config.tau_reuse_delta))
    tau_patch = max(tau_reuse + 0.08, min(0.95, _TAU_PATCH + config.tau_patch_delta))

    return {
        "profile": chosen_profile,
        "explore": explore,
        "features": features,
        "objective_map": objective_map,
        "tau_reuse": tau_reuse,
        "tau_patch": tau_patch,
        "evidence_budget_delta": config.evidence_budget_delta,
        "support_floor": config.support_floor,
        "controller": snapshot,
    }


def report_adaptive_benchmark_feedback(
    *,
    profile_name: str,
    token_f1: float,
    exact_match: float,
    recall_at_1: float,
    recall_at_3: float,
    recall_at_5: float,
    latency_ms: int,
    incorrect_reuse: bool,
) -> None:
    """Online constrained update for the adaptive controller (benchmark mode)."""
    if profile_name not in _ADAPTIVE_PROFILES:
        return

    target_latency = max(50.0, _env_float("TRACECAG_ADAPTIVE_TARGET_LATENCY_MS", 380.0))
    target_incorrect = _clip01(_env_float("TRACECAG_ADAPTIVE_TARGET_INCORRECT_REUSE", 0.12))
    lr = max(0.001, _env_float("TRACECAG_ADAPTIVE_LR", 0.07))
    dual_lr = max(0.001, _env_float("TRACECAG_ADAPTIVE_DUAL_LR", 0.04))

    retrieval_score = (0.50 * recall_at_1) + (0.30 * recall_at_3) + (0.20 * recall_at_5)
    safety_score = 0.0 if incorrect_reuse else 1.0

    # Priority order from product requirement: F1/EM > Retrieval > Drift safety > Latency.
    raw_reward = (
        (0.46 * _clip01(token_f1))
        + (0.16 * _clip01(exact_match))
        + (0.24 * _clip01(retrieval_score))
        + (0.14 * _clip01(safety_score))
    )

    latency_term = (float(latency_ms) - target_latency) / max(target_latency, 1.0)
    incorrect_term = (1.0 if incorrect_reuse else 0.0) - target_incorrect

    global _ADAPTIVE_AVG_REWARD, _ADAPTIVE_DUAL_LATENCY, _ADAPTIVE_DUAL_INCORRECT, _ADAPTIVE_UPDATE_STEPS
    with _ADAPTIVE_STATE_LOCK:
        adjusted_reward = raw_reward - (_ADAPTIVE_DUAL_LATENCY * max(0.0, latency_term)) - (_ADAPTIVE_DUAL_INCORRECT * max(0.0, incorrect_term))

        _ADAPTIVE_AVG_REWARD = (0.96 * _ADAPTIVE_AVG_REWARD) + (0.04 * adjusted_reward)
        _ADAPTIVE_PROFILE_COUNTS[profile_name] = int(_ADAPTIVE_PROFILE_COUNTS.get(profile_name, 0)) + 1

        centered = adjusted_reward - _ADAPTIVE_AVG_REWARD
        _ADAPTIVE_PROFILE_BIAS[profile_name] = max(-0.8, min(0.8, _ADAPTIVE_PROFILE_BIAS.get(profile_name, 0.0) + (lr * centered)))

        _ADAPTIVE_DUAL_LATENCY = max(0.0, _ADAPTIVE_DUAL_LATENCY + (dual_lr * latency_term))
        _ADAPTIVE_DUAL_INCORRECT = max(0.0, _ADAPTIVE_DUAL_INCORRECT + (dual_lr * incorrect_term))
        _ADAPTIVE_UPDATE_STEPS += 1


def get_adaptive_controller_snapshot() -> Dict[str, Any]:
    with _ADAPTIVE_STATE_LOCK:
        return {
            "bias": dict(_ADAPTIVE_PROFILE_BIAS),
            "counts": dict(_ADAPTIVE_PROFILE_COUNTS),
            "dual_latency": float(_ADAPTIVE_DUAL_LATENCY),
            "dual_incorrect": float(_ADAPTIVE_DUAL_INCORRECT),
            "avg_reward": float(_ADAPTIVE_AVG_REWARD),
            "updates": int(_ADAPTIVE_UPDATE_STEPS),
        }
