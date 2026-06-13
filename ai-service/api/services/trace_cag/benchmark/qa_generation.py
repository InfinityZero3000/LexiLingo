"""
QA generation for benchmark tasks (multihop_qa, retrieval_qa).

Pure helpers (_extract_*, _generate_extractive_*) have no external dependencies
and are also imported by prod generate_node for the extractive policy path.
The async ``_generate_benchmark_qa_response`` lazily imports nodes_v2 helpers
at call time to avoid a circular import at module load.
"""

from __future__ import annotations

import logging
import os
import re
import time
from typing import Any, Dict

from api.services.trace_cag.env_helpers import _env_float
from api.services.trace_cag.benchmark.ranking import (
    _answer_support_score,
    _content_tokens,
    _split_benchmark_sentences,
    _update_ranker_from_generation,
)
from api.services.trace_cag.benchmark.quality import (
    _benchmark_provider_order,
    _is_low_quality_benchmark_answer,
)
from api.services.trace_cag.benchmark.adaptive import _ADAPTIVE_PROFILES
from api.services.trace_cag.state import TraceCAGState

logger = logging.getLogger(__name__)

_BENCHMARK_CONTEXT_MAX_CHARS = int(os.getenv("TRACECAG_BENCHMARK_CONTEXT_MAX_CHARS", "3000"))


# ── Pure text helpers (no LLM / no prod imports) ──────────────────────────────

def _extract_first_sentence(text: str) -> str:
    cleaned = " ".join(text.split())
    if not cleaned:
        return ""
    for separator in [".", "?", "!"]:
        if separator in cleaned:
            first = cleaned.split(separator, 1)[0].strip()
            if first:
                return first
    return cleaned


def _strip_jit_soft_graph_block(context: str) -> str:
    text = str(context or "")
    if not text:
        return ""
    text = re.sub(
        r"\[JIT_SOFT_GRAPH\]\s*(?:\n|\r\n?)?\s*\{[\s\S]*?\}\s*",
        "",
        text,
        flags=re.IGNORECASE,
    )
    return text.strip()


def _best_matching_sentence(question: str, context: str) -> str:
    question_tokens = set(_content_tokens(question))
    best_sentence = ""
    best_score = -1
    for sentence in _split_benchmark_sentences(context):
        sentence_tokens = set(_content_tokens(sentence))
        overlap = len(question_tokens & sentence_tokens)
        bonus = 1 if any(char.isdigit() for char in sentence) and any(token in question.lower() for token in ["when", "year", "how many", "how much"]) else 0
        score = overlap + bonus
        if score > best_score:
            best_score = score
            best_sentence = sentence
    return best_sentence or _extract_first_sentence(context)


def _extract_yes_no_answer(question: str, context: str) -> "str | None":
    if not question.lower().startswith(("is ", "are ", "was ", "were ", "do ", "does ", "did ", "can ", "could ", "has ", "have ")):
        return None

    best_sentence = _best_matching_sentence(question, context).lower()
    question_lc = question.lower()

    if "same nationality" in question_lc or "same country" in question_lc:
        nationality_markers = [
            "american", "british", "english", "french", "german", "polish", "turkish", "canadian", "australian",
            "indian", "russian", "japanese", "korean", "chinese", "italian", "spanish",
        ]
        markers_found = [marker for marker in nationality_markers if marker in context.lower()]
        if len(set(markers_found)) == 1 and markers_found:
            return "yes"
        if len(set(markers_found)) > 1:
            return "no"

    if re.search(r"\b(no|not|different)\b", best_sentence):
        return "no"
    if re.search(r"\b(yes|same|both)\b", best_sentence):
        return "yes"
    return None


def _extract_span_after_patterns(sentence: str, patterns: list[str]) -> "str | None":
    for pattern in patterns:
        match = re.search(pattern, sentence, re.IGNORECASE)
        if match:
            candidate = match.group(1).strip(" ,.;:()[]\"")
            if candidate:
                return candidate
    return None


def _generate_extractive_fallback_response(errors: list, strategy: str, user_input: str, context: str) -> str:
    """Deterministic fallback without template dependency when LLM providers are unavailable."""
    clean_context = _strip_jit_soft_graph_block(context)
    grounded = _best_matching_sentence(user_input, clean_context) if clean_context else ""
    grounded = grounded or _extract_first_sentence(clean_context)

    if strategy == "socratic" and grounded:
        return f"Use this clue from context: {grounded} What conclusion can you draw from it?"

    if errors:
        error = errors[0]
        span = str(error.get("span", "")).strip()
        correction = str(error.get("correction", "")).strip()
        explanation = str(error.get("explanation", "")).strip()
        corrected = user_input.replace(span, correction) if span and correction else user_input

        if grounded:
            return (
                f"You are close. Replace '{span}' with '{correction}'. {explanation} "
                f"Grounding: {grounded}"
            ).strip()

        return (
            f"You are close. Replace '{span}' with '{correction}'. {explanation} "
            f"Try: \"{corrected}\""
        ).strip()

    if grounded:
        return grounded

    if strategy == "praise":
        return "Great work. Your sentence is clear and grammatical."

    return "I could not reach a language model right now, but your message was received. Please try again."


def _generate_extractive_qa_response(question: str, context: str) -> str:
    clean_context = _strip_jit_soft_graph_block(context)

    yes_no = _extract_yes_no_answer(question, clean_context)
    if yes_no is not None:
        return yes_no

    best_sentence = _best_matching_sentence(question, clean_context)
    if not best_sentence:
        return "unknown"

    question_lc = question.lower().strip()
    if question_lc.startswith("who"):
        answer = _extract_span_after_patterns(best_sentence, [
            r"^\[[^\]]+\]\s*([^.,;]+?)\s+(?:is|was|are|were)\b",
            r"([^.,;]+?)\s+(?:is|was|are|were)\b",
        ])
        return answer or best_sentence

    if question_lc.startswith("where") or "what city" in question_lc or "what neighborhood" in question_lc:
        answer = _extract_span_after_patterns(best_sentence, [
            r"\b(?:in|at|from|based in|located in)\s+([^.,;]+)",
        ])
        return answer or best_sentence

    if question_lc.startswith("when") or "what year" in question_lc:
        answer = _extract_span_after_patterns(best_sentence, [
            r"\b(?:in|on|during|since)\s+([^.,;]+)",
            r"\b(\d{4})\b",
        ])
        return answer or best_sentence

    if "how many" in question_lc or "how much" in question_lc:
        answer = _extract_span_after_patterns(best_sentence, [
            r"\b(\$?[\d,]+(?:\.\d+)?(?:\s+[A-Za-z]+)?)\b",
        ])
        return answer or best_sentence

    answer = _extract_span_after_patterns(best_sentence, [
        r"\b(?:served as|was|is|are|were|formed by|called|named|known as)\s+([^.,;]+)",
    ])
    return answer or best_sentence


def _postprocess_benchmark_qa_answer(
    question: str,
    raw_answer: str,
    context: str,
    *,
    support_floor: float = 0.4,
    grounding_margin: float = 0.18,
    model_used: str = "",
) -> str:
    """Normalize LLM output into a concise benchmark answer span."""
    text = str(raw_answer or "").strip()
    if not text:
        return "unknown"

    # Remove code fences/prefixes and keep first non-empty line.
    text = re.sub(r"```(?:text)?", "", text, flags=re.IGNORECASE)
    text = text.replace("```", "").strip()
    text = re.sub(r"^\s*(final\s+answer|answer)\s*:\s*", "", text, flags=re.IGNORECASE)
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    candidate = (lines[0] if lines else text).strip(" \t\n\r\"'`“”")

    low = candidate.lower().strip().rstrip(".!")
    if low in {"yes", "no", "unknown"}:
        return low

    # Strong LLM models (70b+) produce high-quality answers that should be trusted
    # more than extractive span matching. Only override for clear hallucinations.
    model_name = str(model_used or "").strip().lower()
    is_strong_llm = any(tag in model_name for tag in ("70b", "7b", "gemini", "gpt", "claude")) and model_name not in ("extractive_fallback", "extractive_policy")

    extractive_answer = _generate_extractive_qa_response(question, context)
    llm_support = _answer_support_score(candidate, context)
    extractive_support = _answer_support_score(extractive_answer, context)

    # For strong LLMs, require a larger grounding gap before preferring extractive.
    # For weaker/extractive fallbacks, use tighter grounding enforcement.
    if is_strong_llm:
        weak_llm_cutoff = max(0.20, support_floor - 0.18)
        effective_grounding_margin = max(grounding_margin, 0.30)
    else:
        weak_llm_cutoff = max(0.38, support_floor - 0.02)
        effective_grounding_margin = grounding_margin

    strong_extractive_cutoff = max(0.72, llm_support + effective_grounding_margin)
    if extractive_answer and llm_support < weak_llm_cutoff and extractive_support >= strong_extractive_cutoff:
        return extractive_answer

    if not is_strong_llm:
        candidate_tokens = _content_tokens(candidate)
        context_tokens = set(_content_tokens(context))
        if candidate_tokens:
            support = sum(1 for tok in candidate_tokens if tok in context_tokens) / max(len(candidate_tokens), 1)
            if support < support_floor and extractive_support >= (llm_support + 0.05):
                return extractive_answer

    # For long explanatory outputs, fallback to deterministic span extraction.
    if len(candidate.split()) > 20 or any(token in low for token in ["because", "according to", "based on", "the answer"]):
        if extractive_support >= llm_support:
            return extractive_answer

    return candidate


def _truncate_benchmark_context(context: str, question: str, max_chars: int = _BENCHMARK_CONTEXT_MAX_CHARS) -> str:
    """Truncate context to keep token usage within TPM budget.

    Keeps the most relevant passages by scoring each paragraph's lexical overlap
    with the question, then greedily fills up to max_chars.
    """
    if not context or len(context) <= max_chars:
        return context

    paragraphs = [p.strip() for p in re.split(r"\n{2,}|\n(?=[A-Z])|(?<=\.)\s{2,}", context) if p.strip()]
    if not paragraphs:
        return context[:max_chars]

    q_tokens = set(_content_tokens(question))

    def _relevance(para: str) -> float:
        p_tokens = set(_content_tokens(para))
        if not p_tokens or not q_tokens:
            return 0.0
        return len(p_tokens & q_tokens) / max(len(q_tokens), 1)

    scored = sorted(enumerate(paragraphs), key=lambda iv: _relevance(iv[1]), reverse=True)
    selected: list[tuple[int, str]] = []
    total = 0
    for idx, para in scored:
        if total + len(para) + 2 > max_chars:
            break
        selected.append((idx, para))
        total += len(para) + 2

    if not selected:
        return context[:max_chars]

    selected.sort(key=lambda iv: iv[0])
    return "\n\n".join(p for _, p in selected)


# ── Async QA generation (benchmark entry point) ───────────────────────────────

async def _generate_benchmark_qa_response(state: TraceCAGState, start_time: float) -> Dict[str, Any]:
    """Generate concise QA outputs for paper-style public benchmarks."""
    from api.services.trace_cag.llm_client import _throttled_post_json
    from api.services.trace_cag.cache_utils import _write_cache_entry

    question = state.get("user_input", "")
    context = state.get("retrieved_context", "") or (state.get("benchmark_context") or "")
    clean_context = _strip_jit_soft_graph_block(context)
    generation_policy = state.get("generation_policy", "auto")

    if generation_policy == "template":
        logger.warning("[_generate_benchmark_qa_response] generation_policy='template' is deprecated; using extractive policy")
        generation_policy = "extractive"

    if generation_policy == "extractive":
        response = _generate_extractive_qa_response(question, clean_context)
        model_used = "extractive_policy"
    else:
        response = ""
        model_used = "llm_unavailable"
        truncated_context = _truncate_benchmark_context(clean_context, question)
        _bench_groq_model = os.getenv("GROQ_MODEL", "qwen/qwen3-32b")
        _no_think_prefix = "/no_think\n" if "qwen" in _bench_groq_model.lower() else ""
        system_prompt = (
            _no_think_prefix +
            "You are a precise QA system for multi-hop reasoning benchmarks. "
            "The context spans multiple passages — read ALL of them, identify key entities and facts, "
            "then chain the evidence to reach the answer. "
            "Output ONLY the minimal final answer: a short entity/phrase (1–6 words), 'yes', or 'no'. "
            "Never explain, never add punctuation or preamble. "
            "If genuinely unanswerable from the context, output exactly: unknown"
        )
        user_prompt = f"Context:\n{truncated_context}\n\nQuestion: {question}\n\nAnswer (entity or yes/no, max 6 words):"

        try:
            import httpx

            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ]

            for provider in _benchmark_provider_order():
                if response:
                    break

                if provider == "groq":
                    from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage, get_groq_key_pool
                    groq_model = os.getenv("GROQ_MODEL", "qwen/qwen3-32b")
                    # Retry across all available keys — skip keys returning 401 (expired/invalid)
                    _pool = get_groq_key_pool()
                    _max_key_tries = _pool.count if _pool else 4
                    _tried_groq_keys: set = set()
                    for _key_attempt in range(_max_key_tries):
                        groq_key = await get_available_groq_key(estimated_tokens=96)
                        if not groq_key or groq_key in _tried_groq_keys:
                            break
                        _tried_groq_keys.add(groq_key)
                        try:
                            resp = await _throttled_post_json(
                                provider="groq",
                                url="https://api.groq.com/openai/v1/chat/completions",
                                headers={"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"},
                                payload={"model": groq_model, "messages": messages, "max_tokens": 96, "temperature": 0.0},
                                httpx_module=httpx,
                                timeout=30.0,
                            )
                            if resp is not None and resp.status_code == 200:
                                data = resp.json()
                                tokens = data.get("usage", {}).get("total_tokens", 96)
                                await record_groq_key_usage(groq_key, tokens)
                                _raw = data["choices"][0]["message"]["content"].strip()
                                # Strip <think>…</think> blocks (Qwen3 thinking mode)
                                response = re.sub(r"<think>.*?</think>\s*", "", _raw, flags=re.DOTALL).strip()
                                model_used = f"groq/{groq_model}"
                                break
                            elif resp is not None and resp.status_code == 401:
                                logger.warning(
                                    "[_generate_benchmark_qa_response] Groq key invalid (401), trying next key"
                                )
                                continue
                            else:
                                logger.warning(
                                    "[_generate_benchmark_qa_response] Groq returned %s: %s",
                                    getattr(resp, "status_code", "n/a"),
                                    getattr(resp, "text", "")[:200],
                                )
                                break
                        except Exception as e:
                            logger.warning("[_generate_benchmark_qa_response] Groq failed: %s", e)
                            break

                elif provider == "gemini":
                    gemini_key = os.getenv("GEMINI_API_KEY", "")
                    if not gemini_key:
                        continue
                    try:
                        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={gemini_key}"
                        request_body = {
                            "contents": [{"parts": [{"text": user_prompt}]}],
                            "system_instruction": {"parts": [{"text": system_prompt}]},
                            "generationConfig": {"temperature": 0.0, "maxOutputTokens": 96},
                        }
                        resp = await _throttled_post_json(
                            provider="gemini",
                            url=url,
                            payload=request_body,
                            httpx_module=httpx,
                            timeout=30.0,
                        )
                        if resp is not None and resp.status_code == 200:
                            candidates = resp.json().get("candidates", [])
                            if candidates:
                                response = candidates[0]["content"]["parts"][0]["text"].strip()
                                model_used = "gemini-2.0-flash"
                        else:
                            logger.warning(
                                "[_generate_benchmark_qa_response] Gemini returned %s: %s",
                                getattr(resp, "status_code", "n/a"),
                                getattr(resp, "text", "")[:200],
                            )
                    except Exception as e:
                        logger.warning("[_generate_benchmark_qa_response] Gemini failed: %s", e)

                elif provider == "ollama":
                    ollama_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
                    ollama_model = os.getenv("OLLAMA_MODEL", "lexilingo-qwen3-1.7b")
                    try:
                        resp = await _throttled_post_json(
                            provider="ollama",
                            url=f"{ollama_url}/api/chat",
                            payload={
                                "model": ollama_model,
                                "messages": messages,
                                "stream": False,
                                "options": {"num_predict": 96, "temperature": 0.0},
                            },
                            httpx_module=httpx,
                            timeout=60.0,
                            max_retries=1,
                        )
                        if resp is not None and resp.status_code == 200:
                            response = resp.json().get("message", {}).get("content", "").strip()
                            model_used = f"ollama/{ollama_model}"
                        else:
                            logger.warning(
                                "[_generate_benchmark_qa_response] Ollama returned %s: %s",
                                getattr(resp, "status_code", "n/a"),
                                getattr(resp, "text", "")[:200],
                            )
                    except Exception as e:
                        logger.warning("[_generate_benchmark_qa_response] Ollama failed: %s", e)
        except Exception as e:
            logger.error("[_generate_benchmark_qa_response] QA generation error: %s", e)

        if not response:
            response = _generate_extractive_qa_response(question, clean_context)
            model_used = "extractive_fallback"

    adaptive_profile = str(state.get("adaptive_profile") or "").strip().lower()
    adaptive_config = _ADAPTIVE_PROFILES.get(adaptive_profile or "balanced") if adaptive_profile else None
    support_floor = float(state.get("adaptive_controller", {}).get("support_floor") or (adaptive_config.support_floor if adaptive_config else 0.4))
    grounding_margin = float(_env_float("TRACECAG_BENCHMARK_GROUNDING_MARGIN", 0.18))

    response = _postprocess_benchmark_qa_answer(
        question,
        response,
        clean_context,
        support_floor=max(0.2, min(0.8, support_floor)),
        grounding_margin=max(0.02, min(0.35, grounding_margin)),
        model_used=model_used,
    )

    overall_score = 1.0 if response and response.lower() != "unknown" else 0.0
    if state.get("cache_policy", "on") == "on":
        try:
            if _is_low_quality_benchmark_answer(response, clean_context, model_used):
                logger.info("[_generate_benchmark_qa_response] Skip cache write for low-quality benchmark answer")
            else:
                await _write_cache_entry(
                    state,
                    response,
                    "benchmark_qa",
                    [],
                    overall_score,
                    clean_context,
                    model_used=model_used,
                )
        except Exception as e:
            logger.debug("[_generate_benchmark_qa_response] Cache write failed: %s", e)

    _update_ranker_from_generation(
        question=question,
        response=response,
        retrieval_trace=list(state.get("retrieval_trace") or []),
    )

    latency_ms = int((time.time() - start_time) * 1000)
    logger.info("[_generate_benchmark_qa_response] Generated QA response via %s in %dms", model_used, latency_ms)
    return {
        "tutor_response": response.strip(),
        "strategy": "benchmark_qa",
        "next_action": "continue",
        "overall_score": overall_score,
        "ttft_ms": latency_ms,
        "models_used": [model_used],
    }
