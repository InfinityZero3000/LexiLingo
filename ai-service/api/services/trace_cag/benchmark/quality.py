"""
Quality filters for benchmark cache entries and LLM answers.

These predicates are checked at cache-write and cache-read time to prevent
low-signal answers from polluting the response cache during benchmark runs.
"""

from __future__ import annotations

import os

from api.services.trace_cag.env_helpers import _env_flag, _env_float
from api.services.trace_cag.provider_state import _provider_cooldown_seconds, _provider_is_disabled
from api.services.trace_cag.benchmark.ranking import _benchmark_tokens
from api.services.trace_cag.state import CacheEntry


def _benchmark_answer_support_ratio(answer: str, context: str) -> float:
    answer_tokens = _benchmark_tokens(answer)
    context_tokens = _benchmark_tokens(context)
    if not answer_tokens or not context_tokens:
        return 0.0
    return len(answer_tokens & context_tokens) / max(len(answer_tokens), 1)


def _benchmark_cache_quality_score(answer: str, context: str, model_used: str) -> float:
    text = str(answer or "").strip()
    if not text:
        return 0.0

    low = text.lower().strip().rstrip(".!")
    if low == "unknown":
        return 0.0

    support = _benchmark_answer_support_ratio(text, context) if context else 0.0
    word_count = len(text.split())
    concise_bonus = 0.14 if word_count <= 8 else (0.08 if word_count <= 16 else 0.0)
    model_name = str(model_used or "").strip().lower()
    provider_bonus = 0.10 if model_name.startswith(("groq/", "gemini", "ollama/")) else 0.0
    yes_no_bonus = 0.10 if low in {"yes", "no"} else 0.0
    fallback_penalty = -0.04 if model_name == "extractive_fallback" else 0.0

    return max(0.0, min(1.0, (0.72 * support) + concise_bonus + provider_bonus + yes_no_bonus + fallback_penalty))


def _is_low_quality_benchmark_answer(answer: str, context: str, model_used: str) -> bool:
    text = str(answer or "").strip()
    low = text.lower().strip().rstrip(".!")
    if not text or low == "unknown":
        return True
    model_name = str(model_used or "").strip().lower()
    if model_name == "extractive_fallback":
        # Allow caching extractive answers with reasonable support to improve warm-hit rate.
        # 0.45 captures entity-span answers that may not verbatim-match long contexts (multi-hop QA).
        min_support = _env_float("TRACECAG_BENCHMARK_EXTRACTIVE_CACHE_MIN_SUPPORT", 0.45)
        support = _benchmark_answer_support_ratio(text, context)
        if support < min_support:
            return True
    if len(text.split()) > 32:
        return True
    if any(marker in low for marker in ["i cannot", "i can't", "unable to", "not enough information", "insufficient"]):
        return True

    min_quality = _env_float("TRACECAG_BENCHMARK_CACHE_MIN_QUALITY", 0.12)
    if _benchmark_cache_quality_score(text, context, model_used) < min_quality:
        return True
    return False


def _cache_entry_quality_ok_for_benchmark(entry: CacheEntry, benchmark_task: str) -> bool:
    if benchmark_task not in {"multihop_qa", "retrieval_qa"}:
        return True

    response = str(entry.get("response") or "").strip()
    execution_plan = entry.get("execution_plan") or {}
    model_used = str(execution_plan.get("model") or "")
    evidence_bundle = entry.get("evidence_bundle") or []
    context_parts = [str(item.get("content") or "") for item in evidence_bundle if isinstance(item, dict)]
    context = "\n".join([part for part in context_parts if part.strip()])

    return not _is_low_quality_benchmark_answer(response, context, model_used)


def _benchmark_provider_order() -> list[str]:
    provider = os.getenv("TRACECAG_BENCHMARK_LLM_PROVIDER", "auto").strip().lower()
    if provider == "template":
        import logging
        logging.getLogger(__name__).warning(
            "[benchmark] provider='template' is deprecated; switching to auto/extractive fallback"
        )
        provider = "auto"
    if provider in {"groq", "gemini", "ollama"}:
        return [provider]

    order: list[str] = []
    if os.getenv("GROQ_API_KEY", "") or os.getenv("GROQ_API_KEYS", ""):
        order.append("groq")
    if _env_flag("TRACECAG_ENABLE_GEMINI_FALLBACK", False) and os.getenv("GEMINI_API_KEY", ""):
        order.append("gemini")
    if _env_flag("TRACECAG_ENABLE_OLLAMA_FALLBACK", False):
        order.append("ollama")

    order = [p for p in order if not _provider_is_disabled(p)]

    # In benchmark runs, avoid blocking on a provider that is cooling down.
    # Sort providers by current cooldown so fallback providers can proceed quickly.
    order.sort(key=_provider_cooldown_seconds)
    return order
