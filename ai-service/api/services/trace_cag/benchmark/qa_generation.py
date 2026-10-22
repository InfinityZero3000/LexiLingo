"""
QA generation for benchmark tasks (multihop_qa, retrieval_qa).

Pure helpers (_extract_*, _generate_extractive_*) have no external dependencies
and are also imported by prod generate_node for the extractive policy path.
The async ``_generate_benchmark_qa_response`` lazily imports nodes_v2 helpers
at call time to avoid a circular import at module load.
"""

from __future__ import annotations

import asyncio
import contextlib
import contextvars
import datetime as _dt
import logging
import os
import re
import time
from typing import Any, Dict

from api.core.groq_key_pool import resolve_groq_model
from api.services.trace_cag.env_helpers import _env_float, _env_flag, _env_int
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

# Chars allowed per declared passage. A single global cap silently undid the
# arm that exists to read a long shortlist: at 3000 chars, cag_longcontext's
# 50 passages were cut to about 7, leaving it near-identical to rag_topk's 5 --
# which is one reason every arm used to tie. The cap now scales with the window
# the arm declared. MuSiQue passages average 426 chars, so 600 holds almost all
# of them whole.
_BENCHMARK_CONTEXT_CHARS_PER_PASSAGE = int(os.getenv("TRACECAG_CONTEXT_CHARS_PER_PASSAGE", "600"))

# Hard ceiling, because Groq's measured limit is 8,000 tokens per minute per
# key: a prompt above roughly 28k chars cannot be served at all, so an arm
# asking for one would 429 forever rather than produce a number.
_BENCHMARK_CONTEXT_CEILING_CHARS = int(os.getenv("TRACECAG_CONTEXT_CEILING_CHARS", "26000"))


def _benchmark_context_cap(state: "TraceCAGState") -> int:
    """Char budget for this arm's context, from the window it declared."""
    declared = int((state.get("benchmark_metadata") or {}).get("_evidence_budget") or 0)
    if declared <= 0:
        return _BENCHMARK_CONTEXT_MAX_CHARS
    return min(declared * _BENCHMARK_CONTEXT_CHARS_PER_PASSAGE, _BENCHMARK_CONTEXT_CEILING_CHARS)
_IRCOT_YES_NO_PREFIXES = (
    "is ", "are ", "was ", "were ", "do ", "does ", "did ",
    "can ", "could ", "has ", "have ", "had ", "will ", "would ",
)


def _safe_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _usage_state_from_provider_usage(usage: dict[str, Any]) -> dict[str, Any]:
    prompt_tokens = _safe_int(
        usage.get("prompt_tokens")
        or usage.get("promptTokenCount")
        or usage.get("prompt_eval_count")
    )
    completion_tokens = _safe_int(
        usage.get("completion_tokens")
        or usage.get("candidatesTokenCount")
        or usage.get("eval_count")
    )
    total_tokens = _safe_int(usage.get("total_tokens") or usage.get("totalTokenCount"))
    details = (
        usage.get("prompt_tokens_details")
        or usage.get("prompt_token_details")
        or usage.get("input_token_details")
        or {}
    )
    cached_tokens = _safe_int(usage.get("cached_tokens") or details.get("cached_tokens"))
    if not total_tokens and (prompt_tokens or completion_tokens):
        total_tokens = prompt_tokens + completion_tokens
    if not (prompt_tokens or completion_tokens or total_tokens or cached_tokens):
        return {}
    effective_prompt_tokens = max(0.0, float(prompt_tokens) - 0.5 * float(cached_tokens))
    return {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": total_tokens,
        "cached_tokens": cached_tokens,
        "effective_prompt_tokens": effective_prompt_tokens,
        "prompt_cache_token_rate": (cached_tokens / prompt_tokens) if prompt_tokens else 0.0,
        "prompt_discount_savings_rate": (
            (prompt_tokens - effective_prompt_tokens) / prompt_tokens
        ) if prompt_tokens else 0.0,
        "usage_source": "provider",
    }


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


def _is_strong_benchmark_model(model_used: str) -> bool:
    """Whether the generating model is capable enough to trust over extractive spans.

    Classify by actual parameter size, not substring tags: the old tag list
    ("70b","7b",…) mis-read "groq/qwen/qwen3-32b" as WEAK (no tag matched) and
    "qwen3-1.7b" as STRONG ("7b" is a substring of "1.7b") — exactly backwards,
    so the main 32B benchmark model got the aggressive extractive override.
    """
    model_name = str(model_used or "").strip().lower()
    if model_name in ("extractive_fallback", "extractive_policy"):
        return False
    param_sizes = [float(m) for m in re.findall(r"(\d+(?:\.\d+)?)\s*b\b", model_name)]
    max_params_b = max(param_sizes) if param_sizes else 0.0
    return max_params_b >= 14.0 or any(tag in model_name for tag in ("gemini", "gpt", "claude"))


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

    # Capable LLMs produce high-quality answers that should be trusted more than
    # extractive span matching; only override for clear hallucinations.
    low_model = str(model_used or "").strip().lower()
    is_strong_llm = _is_strong_benchmark_model(low_model)

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


def _truncate_benchmark_context(
    context: str,
    question: str,
    max_chars: int = _BENCHMARK_CONTEXT_MAX_CHARS,
    items: "list[dict] | None" = None,
) -> str:
    """Truncate context to keep token usage within TPM budget.

    When `items` (the upstream rank-ordered retrieval trace) is supplied, drop
    whole lowest-ranked tail items to fit the budget — this preserves the
    bridge-aware multihop ordering computed upstream in ranking.py. The single
    joined `context` string has no recoverable per-document boundaries (items
    are joined with a single "\\n" and start with "[", so the lexical
    paragraph-split regex below never fires — it degenerates to a blind
    front-truncate that can sever a document mid-sentence). Falls back to that
    paragraph-overlap heuristic only when no structured items are available.
    """
    if not context or len(context) <= max_chars:
        return context

    if items:
        selected_parts: list[str] = []
        total = 0
        for item in items:
            title = str(item.get("title") or "").strip()
            text = str(item.get("text") or "").strip()
            if not text:
                continue
            part = f"[{title}] {text}" if title else text
            if total + len(part) + 1 > max_chars:
                break
            selected_parts.append(part)
            total += len(part) + 1
        if selected_parts:
            return "\n".join(selected_parts)
        return context[:max_chars]

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


# ── Per-request usage ledger ──────────────────────────────────────────────────
#
# `usage_state` on a benchmark observation holds the usage of the LAST provider
# response only. A request that asks IRCoT for a bridge entity, or whose
# thinking call came back empty and was re-asked, made more calls than that, so
# `total_tokens` understated its cost (626 -> 994 recorded tokens/question
# between the top-5 arm and the IRCoT arm, with the bridge call in neither).
# The ledger records every provider call of one request. It is a ContextVar, so
# it is inert outside `_generate_benchmark_qa_response` and every concurrent
# sample (its own task) gets its own list; nothing here changes an answer.
_USAGE_LEDGER: "contextvars.ContextVar[list[dict[str, Any]] | None]" = contextvars.ContextVar(
    "tracecag_usage_ledger", default=None
)


def _ledger_add(role: str, data: Any, *, wall_started: float, response: Any = None) -> None:
    """Append one provider call to this request's ledger. Never raises."""
    ledger = _USAGE_LEDGER.get()
    if ledger is None:
        return
    try:
        usage = (data or {}).get("usage") or {}
        details = usage.get("prompt_tokens_details") or {}
        prompt = _safe_int(usage.get("prompt_tokens"))
        completion = _safe_int(usage.get("completion_tokens"))
        elapsed = getattr(response, "elapsed", None)
        ledger.append({
            "role": role,
            "prompt_tokens": prompt,
            "completion_tokens": completion,
            "total_tokens": _safe_int(usage.get("total_tokens")) or prompt + completion,
            "cached_tokens": _safe_int(usage.get("cached_tokens") or details.get("cached_tokens")),
            # Time inside the provider's HTTP call: excludes our own throttle waits and key rotation.
            "http_ms": int(elapsed.total_seconds() * 1000) if isinstance(elapsed, _dt.timedelta) else 0,
            # Wall time of the attempt, waits included.
            "wall_ms": int((time.monotonic() - wall_started) * 1000),
        })
    except Exception as exc:  # accounting must never change an answer
        logger.debug("[usage_ledger] skipped a call: %s", exc)


def summarize_usage_ledger(entries: "list[dict[str, Any]] | None") -> "dict[str, Any] | None":
    """Totals and a per-role breakdown for one request, or None when no call was recorded."""
    if not entries:
        return None
    by_role: dict[str, dict[str, int]] = {}
    for e in entries:
        r = by_role.setdefault(e["role"], dict.fromkeys(("calls", "prompt_tokens", "completion_tokens", "total_tokens", "http_ms"), 0))
        r["calls"] += 1
        for k in ("prompt_tokens", "completion_tokens", "total_tokens", "http_ms"):
            r[k] += e[k]
    total = {k: sum(e[k] for e in entries) for k in ("prompt_tokens", "completion_tokens", "total_tokens", "cached_tokens", "http_ms", "wall_ms")}
    return {"calls": len(entries), **total, "by_role": by_role, "source": "provider"}


@contextlib.contextmanager
def usage_ledger():
    """Collect the provider calls made inside the block (for callers outside the QA pipeline)."""
    entries: list[dict[str, Any]] = []
    token = _USAGE_LEDGER.set(entries)
    try:
        yield entries
    finally:
        _USAGE_LEDGER.reset(token)


# ── Groq chat helper (reused for IRCoT's reason + answer calls) ───────────────

def _estimate_message_tokens(messages: list, *, max_tokens: int) -> int:
    """Prompt tokens a chat payload will actually cost, plus its output budget."""
    chars = sum(len(str(m.get("content") or "")) for m in messages or [])
    return (chars // 4) + int(max_tokens)


async def _groq_chat_with_retry(
    messages: list, max_tokens: int, *, estimated_tokens: int = 0, reasoning_effort: str = "none",
    ledger_role: str = "aux",
) -> "tuple[str, str]":
    """One Groq chat completion preserving the Bug 5/6 hardening: round-robin
    across all configured keys, skip 401 keys, bounded 503 exponential backoff.
    Returns (raw_text_with_think_stripped, model_used) or ("", "") on failure.
    """
    from api.core.groq_key_pool import (
        get_available_groq_key, record_groq_key_usage, get_configured_key_count,
    )
    from api.services.trace_cag.llm_client import _qwen_reasoning_overrides, _throttled_post_json

    groq_model = resolve_groq_model()
    _max_503_retries = 5
    _max_key_tries = (get_configured_key_count() or 1) + _max_503_retries
    _tried: set = set()
    _503 = 0
    for _ in range(_max_key_tries):
        key = await get_available_groq_key(
            estimated_tokens=estimated_tokens or _estimate_message_tokens(messages, max_tokens=max_tokens)
        )
        if not key or (key in _tried and _503 >= _max_503_retries):
            break
        _tried.add(key)
        _attempt_started = time.monotonic()
        try:
            resp = await _throttled_post_json(
                provider="groq",
                url="https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                payload={
                    "model": groq_model,
                    "messages": messages,
                    "max_tokens": max_tokens,
                    "temperature": 0.0,
                    # Explicit, so `_throttled_post_json` does not force "none".
                    **({"reasoning_effort": reasoning_effort} if "qwen" in groq_model.lower() else {}),
                },
                timeout=30.0,
                # One attempt per key. The default of 3 sleeps ~20s on THIS key
                # before retrying it, while the other six sit idle -- a
                # per-minute bucket is emptied per key, so the cure is the next
                # key, not waiting on this one. Rotation is the loop below.
                max_retries=1,
            )
            if resp is not None and resp.status_code == 200:
                data = resp.json()
                _ledger_add(ledger_role, data, wall_started=_attempt_started, response=resp)
                await record_groq_key_usage(key, data.get("usage", {}).get("total_tokens", max_tokens))
                raw = data["choices"][0]["message"]["content"].strip()
                raw = re.sub(r"<think>.*?</think>\s*", "", raw, flags=re.DOTALL).strip()
                if not raw and reasoning_effort != "none":
                    # Thinking spent the whole budget. Same floor as the reader:
                    # answer this call without it rather than return nothing.
                    logger.warning(
                        "[_groq_chat_with_retry] empty content with reasoning=%s, retrying without",
                        reasoning_effort,
                    )
                    return await _groq_chat_with_retry(
                        messages, 32, estimated_tokens=estimated_tokens, reasoning_effort="none",
                        ledger_role=f"{ledger_role}_nothink",
                    )
                return raw, f"groq/{groq_model}"
            if resp is not None and resp.status_code == 401:
                continue
            if resp is not None and resp.status_code == 429:
                # Rotate. 429 used to fall through to the `break` below, so the
                # single most common failure abandoned the key loop after one
                # key -- 26 of 200 samples on the `tracecag` arm returned no
                # response with six keys untouched. `_throttled_post_json`
                # already pushed this key's next-request time out, so cycling
                # back to it waits without this loop having to sleep.
                continue
            if resp is not None and resp.status_code == 503 and _503 < _max_503_retries:
                _503 += 1
                await asyncio.sleep(2 ** _503)
                continue
            logger.warning("[_groq_chat_with_retry] Groq returned %s: %s",
                           getattr(resp, "status_code", "n/a"), getattr(resp, "text", "")[:160])
            break
        except Exception as e:
            logger.warning("[_groq_chat_with_retry] Groq failed: %s", e)
            break
    return "", ""


def _ircot_full_candidate_docs(state: TraceCAGState) -> list[dict]:
    """All candidate passages (the full distractor pool), for IRCoT re-retrieval."""
    md = state.get("benchmark_metadata") or {}
    docs = md.get("context_docs") or []
    out = []
    for i, d in enumerate(docs):
        if isinstance(d, dict) and str(d.get("text") or "").strip():
            out.append({"title": str(d.get("title") or f"doc_{i}"), "text": str(d.get("text") or "")})
    return out


# Corpus search for IRCoT's second retrieval, registered by the benchmark
# runtime when it builds the shared retriever. `(query, k) -> [{title, text}]`.
# None everywhere else, which keeps the in-pool fallback below.
_BENCHMARK_CORPUS_SEARCH = None


def _ircot_corpus_bridge_passages(entity: str, already: set, k: int = 2, *, context: str = "") -> list[dict]:
    """IRCoT as published: a NEW retrieval over the corpus, driven by the
    reasoning step's bridge entity.

    The in-pool version below was written for `candidate_pool` mode, where each
    question's 20 passages always held both gold passages, so re-ranking that
    pool could find hop 2. In corpus mode the pool is the first retrieval's own
    top-50, which misses the hop-2 passage for ~47% of questions -- so the
    "second retrieval" could only re-find what the first one already had.
    Simulated on 148 questions with a missing link: the pool filled it 33.8% of
    the time, a corpus search on the entity alone 57.4%. Adding the question to
    the query pulls results back toward hop 1 (top-1: 45.9% -> 9.5%), so the
    query is the entity only.
    """
    search = _BENCHMARK_CORPUS_SEARCH
    if search is None or not str(entity or "").strip():
        return []
    # Over-fetch: some hits are passages the reader already has.
    hits = search(entity, k + len(already) + 2)
    if context:
        # By text: an article contributes several distinct paragraphs, and one
        # already in context says nothing about whether this one is.
        seen = " ".join(context.split())
        return [h for h in hits if " ".join(str(h.get("text") or "").split())[:80] not in seen][:k]
    return [h for h in hits if str(h.get("title") or "").strip().lower() not in already][:k]


def _ircot_pick_bridge_passages(entity: str, docs: list[dict], already: set, k: int = 2) -> list[dict]:
    """Re-retrieve: rank the full pool by overlap with the reasoning's bridge
    entity and return up to k passages not already in the reader's context."""
    ent = _content_tokens(entity)
    if not ent or not docs:
        return []
    ent_set = set(ent)
    scored = []
    for d in docs:
        title_l = str(d.get("title") or "").strip().lower()
        if title_l in already:
            continue
        title_tokens = set(_content_tokens(str(d.get("title", ""))))
        hay = set(_content_tokens(f"{d.get('title','')} {d.get('text','')}"))
        # Strong boost when the entity name appears in the title (bridge target page).
        title_hit = 1.0 if ent_set.issubset(title_tokens) else 0.0
        overlap = len(ent_set & hay) / max(len(ent_set), 1)
        score = overlap + 0.5 * title_hit
        if score > 0:
            scored.append((score, d))
    scored.sort(key=lambda s: s[0], reverse=True)
    return [d for _, d in scored[:k]]


def _ircot_context_titles(context: str) -> set[str]:
    titles: set[str] = set()
    for line in str(context or "").splitlines():
        match = re.match(r"\[([^\]]+)\]", line.strip())
        if match:
            titles.add(match.group(1).strip().lower())
    return titles


def _ircot_support_titles(state: TraceCAGState) -> list[str]:
    md = state.get("benchmark_metadata") or {}
    raw = md.get("supporting_titles") or md.get("relevant_passage_ids") or []
    return [str(item).strip() for item in raw if str(item).strip()]


def _ircot_uncovered_question_entities(question: str, base_context: str) -> list[str]:
    """Named entities the question asks about that the context never mentions.

    Oracle-free stand-in for "am I missing a hop". The gold `supporting_titles`
    the gate was originally written against are NOT passed to the pipeline at
    runtime (`tracecag_bench/runtime/ai_service.py` builds benchmark_metadata
    without them), so every support-coverage branch below was dead and the gate
    collapsed to a question-shape guess. An entity named in the question with no
    passage mentioning it is the same signal without reading the answer key.
    """
    haystack = str(base_context or "").lower()
    if not haystack:
        return []
    # Capitalised runs, skipping the sentence-initial word (usually "Who"/"What").
    spans = re.findall(r"\b[A-Z][\w.'’-]*(?:\s+[A-Z][\w.'’-]*)*", str(question or "")[1:])
    uncovered = []
    for span in spans:
        span = span.strip()
        if len(span) < 3 or span.lower() in _IRCOT_ENTITY_STOPWORDS:
            continue
        if span.lower() not in haystack:
            uncovered.append(span)
    return uncovered


_IRCOT_ENTITY_STOPWORDS = frozenset({
    "the", "a", "an", "who", "what", "which", "when", "where", "why", "how",
    "was", "were", "is", "are", "did", "does", "do", "in", "of", "and", "or",
})


def _ircot_question_type(question: str) -> str:
    text = str(question or "").strip().lower()
    if not text:
        return "unknown"
    if text.startswith(_IRCOT_YES_NO_PREFIXES) or text.startswith(("yes or no", "yes/no")):
        return "yes_no"
    if any(marker in text for marker in (
        "same ", "both ", "compare", "which of", "earlier", "later",
        "older", "younger", "larger", "smaller", "higher", "lower",
    )):
        return "comparison"
    if any(marker in text for marker in (
        " of the ", " by the ", " in the ", " who ", " whose ", " that ",
        "which ", "where ", "when ", "what ", "director of", "author of",
        "located in", "founded by",
    )):
        return "bridge"
    return "single_hop_like"


def _ircot_should_run(question: str, base_context: str, state: TraceCAGState) -> "tuple[bool, dict[str, Any]]":
    """Deterministic gate for the expensive IRCoT reason call.

    The benchmark runtime currently marks public QA samples as ``multihop_qa``.
    This gate keeps Run 27's mechanism available, but skips cases where a second
    LLM call is unlikely to add bridge evidence (yes/no, single-support, or no
    candidate pool). Set ``TRACECAG_BENCHMARK_IRCOT_SELECTIVE=false`` to reproduce
    the old all-multihop behavior.
    """
    docs = _ircot_full_candidate_docs(state)
    support_titles = _ircot_support_titles(state)
    context_titles = _ircot_context_titles(base_context)
    support_hits = sum(1 for title in support_titles if title.lower() in context_titles)
    support_total = len(support_titles)
    support_coverage = (support_hits / support_total) if support_total else 0.0
    question_type = _ircot_question_type(question)
    uncovered = _ircot_uncovered_question_entities(question, base_context)
    selective = _env_flag("TRACECAG_BENCHMARK_IRCOT_SELECTIVE", True)
    meta: dict[str, Any] = {
        "uncovered_entities": uncovered[:5],
        "evaluated": True,
        "selected": False,
        "reason": "not_selected",
        "question_type": question_type,
        "selective": selective,
        "candidate_docs": len(docs),
        "support_titles_total": support_total,
        "support_titles_seen": support_hits,
        "support_coverage": round(support_coverage, 4),
    }

    if not _env_flag("TRACECAG_BENCHMARK_IRCOT", True):
        meta["reason"] = "env_disabled"
        return False, meta
    # The arm's declared `enable_ircot`. Absent for every non-benchmark caller,
    # so production chat keeps whatever this gate decides; present and false
    # means the arm under test does not include IRCoT and must not pay for it.
    declared = (state.get("benchmark_metadata") or {}).get("_enable_ircot")
    if declared is not None and not declared:
        meta["reason"] = "arm_declared_off"
        return False, meta
    if state.get("benchmark_task") != "multihop_qa":
        meta["reason"] = "not_multihop_task"
        return False, meta
    if not docs:
        meta["reason"] = "no_candidate_pool"
        return False, meta
    unselected = [
        doc for doc in docs
        if str(doc.get("title") or "").strip().lower() not in context_titles
    ]
    meta["unselected_docs"] = len(unselected)
    if not unselected:
        # The reason call can only pay for itself by pulling in a passage that
        # is not already in context. Since the evidence budget was raised to
        # 9–10 of the 10-document pool, that is usually empty: measured 41 of 53
        # reason calls returned `no_bridge_passages` — an LLM call, its latency
        # and its quota spent on a retrieval that had nothing left to retrieve.
        meta["reason"] = "no_unselected_candidates"
        return False, meta
    if not selective:
        meta.update({"selected": True, "reason": "all_multihop"})
        return True, meta
    if question_type == "yes_no" and _env_flag("TRACECAG_IRCOT_SKIP_YES_NO", True):
        meta["reason"] = "skip_yes_no"
        return False, meta
    if 0 < support_total <= 1:
        meta["reason"] = "skip_single_support"
        return False, meta
    if support_total >= 2 and support_coverage < 1.0:
        meta.update({"selected": True, "reason": "missing_support_bridge"})
        return True, meta
    if uncovered:
        # A hop the question names but the context never mentions — the case
        # a second, reasoning-driven retrieval exists for.
        meta.update({"selected": True, "reason": "uncovered_question_entity"})
        return True, meta
    if question_type in {"bridge", "comparison"} and (support_total >= 2 or len(docs) >= 4):
        meta.update({"selected": True, "reason": "question_shape_multihop"})
        return True, meta
    if support_total >= 2:
        meta.update({"selected": True, "reason": "support_titles_multihop"})
        return True, meta

    meta["reason"] = "low_multihop_signal"
    return False, meta


def _ircot_bridge_contract(question: str, entity: str, extra: list[dict], base_context: str) -> dict[str, Any]:
    entity_tokens = set(_content_tokens(entity))
    question_tokens = set(_content_tokens(question))
    base_tokens = set(_content_tokens(base_context))
    added_titles = [str(doc.get("title") or "").strip() for doc in extra if str(doc.get("title") or "").strip()]

    if not entity_tokens or not extra:
        return {
            "passes": False,
            "reason": "empty_entity_or_extra",
            "added_titles": added_titles,
            "extra_overlap": 0.0,
            "base_overlap": 0.0,
            "question_overlap": 0.0,
        }

    best_extra_overlap = 0.0
    title_hit = False
    for doc in extra:
        title = str(doc.get("title") or "")
        text = str(doc.get("text") or "")
        title_tokens = set(_content_tokens(title))
        hay_tokens = set(_content_tokens(f"{title} {text}"))
        if title_tokens and entity_tokens.issubset(title_tokens):
            title_hit = True
        best_extra_overlap = max(best_extra_overlap, len(entity_tokens & hay_tokens) / max(len(entity_tokens), 1))

    base_overlap = len(entity_tokens & base_tokens) / max(len(entity_tokens), 1)
    question_overlap = len(entity_tokens & question_tokens) / max(len(entity_tokens), 1)
    has_source_anchor = base_overlap > 0 or question_overlap > 0
    has_bridge_doc = title_hit or best_extra_overlap >= 0.5
    passes = bool(has_source_anchor and has_bridge_doc)

    return {
        "passes": passes,
        "reason": "ok" if passes else "weak_bridge_anchor",
        "added_titles": added_titles,
        "title_hit": title_hit,
        "extra_overlap": round(best_extra_overlap, 4),
        "base_overlap": round(base_overlap, 4),
        "question_overlap": round(question_overlap, 4),
    }


async def _ircot_augment(
    question: str, base_context: str, state: TraceCAGState, *, cap_bonus: int = 0, looked_up: "tuple[str, ...]" = (),
) -> "tuple[str, str, dict[str, Any]]":
    """IRCoT step: reason to find the bridge entity, then re-retrieve passages
    about it from the full pool and fold them into the reader's context.

    Returns (augmented_context, bridge_entity_hint, telemetry). This is the faithful
    iterative reason→re-retrieve→answer mechanism (arXiv:2212.10509), unlike the
    one-shot E2G/recall experiments — the reasoning step DRIVES a focused second
    retrieval of the hop-2 passage that lexical ranking leaves out of budget.
    """
    started = time.time()
    meta: dict[str, Any] = {
        "selected": True,
        "reason": "augment_started",
        "bridge_entity": "",
        "reason_model": "",
        "reason_latency_ms": 0,
        "added_titles": [],
        "contract": {"passes": False, "reason": "not_evaluated"},
        "context_chars_before": len(base_context or ""),
        "context_chars_after": len(base_context or ""),
    }
    # No "/no_think" prefix: verified against Groq (2026-08-16) that qwen3.6
    # ignores it and keeps emitting <think>. reasoning_effort="none" is the
    # control that works, and _throttled_post_json injects it for every Groq
    # caller — see _qwen_reasoning_overrides in llm_client.py.
    reason_sys = (
        "You are solving a multi-hop question. From the question and passages, name the SINGLE "
        "intermediate 'bridge' entity you must look up next to connect the question to its answer "
        "(e.g. the person/film/place the question refers to indirectly). Output ONLY that entity "
        "name on one line — no explanation. If the answer is already directly in the passages, "
        "output that answer entity instead."
    )
    reason_user = f"Passages:\n{base_context[:1800]}\n\nQuestion: {question}\n\nBridge entity to look up next:"
    if looked_up:   # later rounds only: without this the model names the entity it already resolved
        reason_user = (f"Passages:\n{base_context[:1800]}\n\nQuestion: {question}\n\n"
                       f"Already looked up: {'; '.join(looked_up)}.\nNext bridge entity to look up:")
    # The bridge entity IS the second retrieval's query, and it was extracted
    # with thinking off. Measured with corpus bridging: when the extracted
    # entity matched the missing hop's title (41% of 143) the answer scored F1
    # 0.793, when it did not (59%) 0.427. 32 tokens cannot hold a reasoning
    # trace, hence the larger budget when the arm declares reasoning here.
    _ircot_reasoning = str((state.get("benchmark_metadata") or {}).get("_ircot_reasoning") or "none")
    reasoning, reason_model = await _groq_chat_with_retry(
        [{"role": "system", "content": reason_sys}, {"role": "user", "content": reason_user}],
        max_tokens=32 if _ircot_reasoning == "none" else 320,
        estimated_tokens=64,
        reasoning_effort=_ircot_reasoning,
        ledger_role="ircot_reason",
    )
    meta["reason_latency_ms"] = int((time.time() - started) * 1000)
    meta["reason_model"] = reason_model
    entity = (reasoning.splitlines()[0].strip(" .\"'`") if reasoning else "")
    meta["bridge_entity"] = entity
    if not entity or len(entity) > 60 or entity.lower() in {"unknown", "none"}:
        meta["reason"] = "empty_bridge_entity"
        return base_context, "", meta

    already = _ircot_context_titles(base_context)
    # Passages added per hop. 2 is the measured default; the rank-2 passage was a supporting passage 17% of the time
    # against 37% for rank 1, so an arm may declare 1 to hand the reader less noise.
    bridge_k = max(1, int((state.get("benchmark_metadata") or {}).get("_ircot_bridge_k") or 2))
    if (state.get("benchmark_metadata") or {}).get("_ircot_corpus") and _BENCHMARK_CORPUS_SEARCH is not None:
        extra = _ircot_corpus_bridge_passages(entity, already, k=bridge_k, context=base_context)
        meta["bridge_source"] = "corpus"
    else:
        docs = _ircot_full_candidate_docs(state)
        extra = _ircot_pick_bridge_passages(entity, docs, already, k=bridge_k)
        meta["bridge_source"] = "pool"
    if not extra:
        meta["reason"] = "no_bridge_passages"
        return base_context, "", meta

    contract = _ircot_bridge_contract(question, entity, extra, base_context)
    meta["contract"] = contract
    meta["added_titles"] = list(contract.get("added_titles") or [])
    if _env_flag("TRACECAG_IRCOT_VERIFY_BRIDGE", True) and not bool(contract.get("passes")):
        meta["reason"] = "contract_rejected"
        return base_context, "", meta

    # Bridge passages first (most relevant to the unmet hop), then the FULL
    # original context. Use a larger IRCoT-specific cap so adding the hop-2
    # passage does NOT evict the original answer passage (Run 26 lost
    # "English Electric Canberra"→"unknown" exactly because re-truncating to the
    # base 2500-char budget dropped the original answer-bearing passage).
    bridge_block = "\n".join(f"[{d['title']}] {d['text']}" for d in extra)
    augmented = f"{bridge_block}\n{base_context}"
    ircot_cap = max(_BENCHMARK_CONTEXT_MAX_CHARS, _env_int("TRACECAG_IRCOT_CONTEXT_MAX_CHARS", 3800)) + cap_bonus
    augmented = augmented[:ircot_cap]
    meta["reason"] = "augmented"
    meta["ircot_context_cap"] = ircot_cap
    meta["context_chars_after"] = len(augmented)
    return augmented, entity, meta


async def _ircot_rounds(question: str, base_context: str, state: TraceCAGState) -> "tuple[str, str, dict[str, Any]]":
    """Up to the arm's declared `_ircot_rounds` reason -> re-retrieve hops (default 1: exactly `_ircot_augment`).

    A later round reasons over the context the previous one produced and is told what was already looked up. The first
    round that adds nothing ends the loop, and each extra round raises the context cap, because the cap truncates the
    END of the context -- the original window -- and a second bridge block would otherwise push the first hop out.
    """
    rounds = max(1, int((state.get("benchmark_metadata") or {}).get("_ircot_rounds") or 1))
    context, hint, meta = await _ircot_augment(question, base_context, state)
    meta["rounds_run"] = 1
    entities = [meta.get("bridge_entity") or ""]
    titles = list(meta.get("added_titles") or [])
    for n in range(2, rounds + 1):
        if meta.get("reason") != "augmented":
            break
        nxt, nxt_hint, nxt_meta = await _ircot_augment(
            question, context, state,
            cap_bonus=(n - 1) * _env_int("TRACECAG_IRCOT_ROUND_EXTRA_CHARS", 1500),
            looked_up=tuple(e for e in entities if e),
        )
        if nxt_meta.get("reason") != "augmented":
            meta["rounds_stopped_by"] = nxt_meta.get("reason")
            break
        context, hint = nxt, nxt_hint
        meta["rounds_run"] = n
        entities.append(nxt_meta.get("bridge_entity") or "")
        titles += list(nxt_meta.get("added_titles") or [])
        meta["context_chars_after"] = nxt_meta.get("context_chars_after")
    meta["bridge_entities"] = entities
    meta["added_titles"] = titles
    return context, hint, meta


# ── Async QA generation (benchmark entry point) ───────────────────────────────


async def _generate_benchmark_qa_response(state: TraceCAGState, start_time: float) -> Dict[str, Any]:
    """Benchmark QA generation; adds `retrieval_meta["llm_usage"]`, the usage of every provider call it made."""
    token = _USAGE_LEDGER.set([])
    try:
        result = await _generate_benchmark_qa_response_impl(state, start_time)
        usage = summarize_usage_ledger(_USAGE_LEDGER.get())
        if usage:
            result["retrieval_meta"] = {**(result.get("retrieval_meta") or {}), "llm_usage": usage}
        return result
    finally:
        _USAGE_LEDGER.reset(token)


async def _generate_benchmark_qa_response_impl(state: TraceCAGState, start_time: float) -> Dict[str, Any]:
    """Generate concise QA outputs for paper-style public benchmarks."""
    from api.services.trace_cag.llm_client import (
        _is_qwen_model, _qwen_reasoning_overrides, _throttled_post_json,
    )
    from api.services.trace_cag.cache_utils import _write_cache_entry

    question = state.get("user_input", "")
    context = state.get("retrieved_context", "") or (state.get("benchmark_context") or "")
    clean_context = _strip_jit_soft_graph_block(context)
    # The context the answer is actually grounded in. IRCoT appends a passage
    # that clean_context never sees, so grounding/cache checks run against it.
    answer_context = clean_context
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
        usage_state: dict[str, Any] = {}
        auxiliary_models: list[str] = []
        _ircot_meta: dict[str, Any] = {"evaluated": False, "selected": False, "reason": "not_evaluated"}
        context_cap = _benchmark_context_cap(state)
        truncated_context = _truncate_benchmark_context(
            clean_context, question, max_chars=context_cap,
            items=list(state.get("retrieval_trace") or []),
        )
        # IRCoT: one reason→re-retrieve hop before answering, for multi-hop tasks.
        # Default ON: Run 27 (n=64, tracecag_rapid) EM 45.3%→50.0%, F1 58.6%→62.5%
        # (net +3 questions, all genuine 2-hop reasoning fixes) — first validated
        # win after 4 prior attempts regressed. Costs a 2nd LLM call (~2× latency),
        # so only fires for benchmark multihop_qa, never production chat.
        _ircot_hint = ""
        _use_ircot, _ircot_meta = _ircot_should_run(question, truncated_context, state)
        if _use_ircot:
            truncated_context, _ircot_hint, _augment_meta = await _ircot_rounds(question, truncated_context, state)
            _ircot_meta.update(_augment_meta)
            if _augment_meta.get("added_titles"):
                # Ground against the UNION. The augmented context puts the bridge
                # block first and re-caps, so it drops the tail of the original —
                # it is not a superset of clean_context. Grounding against it
                # alone turned a correct long answer into "unknown" because the
                # passage supporting it had been cut to make room.
                answer_context = f"{truncated_context}\n{clean_context}"
            _reason_model = str(_ircot_meta.get("reason_model") or "")
            if _reason_model:
                auxiliary_models.append(f"ircot_reason:{_reason_model}")
        # Non-directive hint: surface the bridge entity as possibly relevant rather
        # than asserting it IS the link — Run 26 lost cases where the reason step
        # picked a wrong bridge and the assertive hint forced the model to follow it
        # (New York City→Columbia University, Terry Richardson→Annie Morton).
        _hint_block = f"\n\n(\"{_ircot_hint}\" may be relevant.)" if _ircot_hint else ""
        # E2G ("Evidence → minimal Answer"): one bounded reasoning step before the
        # answer, grounded in the passages, with an exemplar that pins HotpotQA
        # answer granularity. Targets the dominant failure buckets (2-hop synthesis
        # + near-miss span/format), per arXiv:2401.05787 / 2212.10509. Kept bounded
        # (still /no_think, no <think> explosion) to stay inside the TPM budget.
        # Default OFF: Run 23 (n=64, tracecag_rapid) showed bounded E2G with /no_think
        # kept REGRESSES EM 46.9%→39.1% (net −5 EM per-sample: 1 gain, 6 losses) —
        # the model writes a post-hoc Evidence line without real reasoning and diverges
        # to wrong entities on questions direct answering got right (Phil Spector→"the
        # Teddy Bears", YG Entertainment→WINNER). The research-backed gain needs REAL
        # Qwen3 thinking (remove /no_think, ~500+ reasoning tokens/call), which blows the
        # 500K/day TPD across n=64×3-modes. Knob kept for a future quota-permitting test.
        _use_e2g = _env_flag("TRACECAG_BENCHMARK_E2G", False)
        # The arm's declared `reasoning`. Every arm so far ran "none", inherited
        # from a JSON-parsing constraint that does not apply here: this reader
        # returns a short answer span and already strips <think> blocks below.
        # Multi-hop QA is the task thinking should pay for, and the window sweep
        # showed the binding constraint is the reader, not retrieval -- coverage
        # rose 0.235->0.440 while F1 fell 0.294->0.252.
        _reasoning = str((state.get("benchmark_metadata") or {}).get("_reasoning_effort") or "none")
        _allow_abstain = bool((state.get("benchmark_metadata") or {}).get("_allow_abstain", True))
        _reasoning_budget = int((state.get("benchmark_metadata") or {}).get("_reasoning_budget") or 320)
        _thinks = _reasoning != "none"
        # 96 tokens cannot hold a reasoning trace plus an answer, but max_tokens
        # is also a RESERVATION against Groq's output-tokens-per-minute budget:
        # at 1024 a key refused the request outright ("Request too large ... on
        # output tokens per minute") once its minute was partly spent, and 9 of
        # the first 14 samples errored. Measured output with reasoning="low" is
        # a median of 143 tokens, so 384 covers the usual call while reserving a
        # quarter as much. A call that needs more is truncated rather than lost.
        # Measured 2026-10-10: Groq enforces OTPM (output tokens per minute) of
        # 1000 PER KEY, and `max_tokens` is a reservation against it, not a
        # ceiling on what is used. 1024 was refused outright ("Request too large
        # ... on output tokens per minute"); 768 reserves 77% of a key's minute,
        # so a second request on that key is refused and the run died at 4-7 of
        # 30 samples. 320 reserves a third, which with 7 keys leaves room for
        # roughly 20 samples a minute. Thinking calls used a median of 137
        # output tokens, and the ones that want more hit the empty-content
        # fallback below rather than being lost.
        _bench_max_tokens = _env_int(
            "TRACECAG_BENCHMARK_MAX_TOKENS",
            _reasoning_budget if _thinks else (220 if _use_e2g else 96),
        )
        if _use_e2g:
            system_prompt = (
                "You are a precise multi-hop QA system. Read ALL passages, find the "
                "supporting fact(s), and chain them across passages to reach the answer.\n"
                "Then give the MINIMAL final answer copied in the gold style: a short "
                "entity/phrase (1–6 words), 'yes', or 'no'. Use the exact surface form as "
                "it appears in the passage; do NOT add titles, honorifics, given names, "
                "dates, or parentheticals beyond what the question asks. If the context "
                "does not contain the answer, output 'unknown'.\n"
                "Respond in EXACTLY this format, nothing else:\n"
                "Evidence: <one short supporting fact chaining the hops>\n"
                "Answer: <minimal final answer>\n\n"
                "Example:\n"
                "Context:\n"
                "[Doctor Strange (2016 film)] Doctor Strange is a 2016 Marvel film starring "
                "Benedict Cumberbatch, directed by Scott Derrickson.\n"
                "[Scott Derrickson] Scott Derrickson is an American director.\n"
                "Question: What nationality is the director of the 2016 film starring "
                "Benedict Cumberbatch as the title role?\n"
                "Evidence: Doctor Strange (2016) stars Cumberbatch and was directed by Scott "
                "Derrickson, who is American.\n"
                "Answer: American"
            )
            user_prompt = f"Context:\n{truncated_context}\n\nQuestion: {question}"
        else:
            system_prompt = (
                "You are a precise QA system for multi-hop reasoning benchmarks. "
                "The context spans multiple passages — read ALL of them, identify key entities and facts, "
                "then chain the evidence to reach the answer. "
                "Output ONLY the minimal final answer: a short entity/phrase (1–6 words), 'yes', or 'no'. "
                "Never explain, never add punctuation or preamble. "
                + (
                    "If genuinely unanswerable from the context, output exactly: unknown"
                    if _allow_abstain
                    # No MuSiQue question has "unknown" as its gold answer, so
                    # abstaining scores exactly 0 under token-F1 while a wrong
                    # guess that shares any token with the gold scores above it.
                    # Abstention is strictly dominated here; never offer it.
                    else "Never output 'unknown'. If the context is incomplete, give your "
                         "single best guess from the passages anyway."
                )
            )
            user_prompt = f"Context:\n{truncated_context}\n\nQuestion: {question}{_hint_block}\n\nAnswer (entity or yes/no, max 6 words):"

        try:
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ]

            for provider in _benchmark_provider_order():
                if response:
                    break

                if provider == "groq":
                    from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage, get_configured_key_count
                    groq_model = resolve_groq_model()
                    # Retry across all available keys — skip keys returning 401 (expired/invalid)
                    # 5 retries (2s..32s, ~62s worst case): Run 19 showed Groq's qwen3-32b
                    # over-capacity periods can outlast 3 retries (14s) for a sample.
                    _max_503_retries = 5
                    _max_key_tries = (get_configured_key_count() or 1) + _max_503_retries
                    _tried_groq_keys: set = set()
                    _503_retry_count = 0
                    for _key_attempt in range(_max_key_tries):
                        # The real prompt size, not a constant. This asked the
                        # pool for a key while declaring 96 tokens and then sent
                        # 3,864 (a 50-passage CAG window), so the pool's own
                        # per-minute accounting was wrong by 40x: it handed out
                        # keys it believed were idle and the requests 429'd on
                        # input tokens per minute. Measured: 8 of 51 samples
                        # lost before the run aborted.
                        groq_key = await get_available_groq_key(
                            # INPUT tokens only. The limit this reserves against
                            # is Groq's ITPM ("input tokens per minute: Limit
                            # 7000"); output has its own separate per-minute
                            # budget, which `max_tokens` in the payload reserves.
                            # Adding max_tokens here was harmless at 96 and broke
                            # the run at 384: the pool refused to hand out any
                            # key and the loop returned no response at all, with
                            # no 429 and nothing logged.
                            estimated_tokens=_estimate_message_tokens(messages, max_tokens=0)
                        )
                        if not groq_key or (groq_key in _tried_groq_keys and _503_retry_count >= _max_503_retries):
                            break
                        _tried_groq_keys.add(groq_key)
                        _attempt_started = time.monotonic()
                        try:
                            resp = await _throttled_post_json(
                                provider="groq",
                                url="https://api.groq.com/openai/v1/chat/completions",
                                headers={"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"},
                                payload={
                                    "model": groq_model,
                                    "messages": messages,
                                    "max_tokens": _bench_max_tokens,
                                    "temperature": 0.0,
                                    # Explicit, so `_throttled_post_json` leaves it
                                    # alone instead of forcing "none".
                                    **({"reasoning_effort": _reasoning} if _is_qwen_model(groq_model)
                                       else {}),
                                },
                                timeout=30.0,
                            )
                            if resp is not None and resp.status_code == 200:
                                data = resp.json()
                                _ledger_add(
                                    "reader" if not auxiliary_models.count("reasoning_fallback:empty_content") else "reader_nothink",
                                    data, wall_started=_attempt_started, response=resp,
                                )
                                usage_state = _usage_state_from_provider_usage(data.get("usage") or {})
                                tokens = usage_state.get("total_tokens") or data.get("usage", {}).get("total_tokens", _bench_max_tokens)
                                await record_groq_key_usage(groq_key, tokens)
                                _raw = data["choices"][0]["message"]["content"].strip()
                                # Strip <think>…</think> blocks (Qwen3 thinking mode)
                                _raw = re.sub(r"<think>.*?</think>\s*", "", _raw, flags=re.DOTALL).strip()
                                # E2G: keep only the final "Answer:" line (drop the Evidence
                                # reasoning so it never reaches the EM/F1 scorer). Fall back to
                                # the last non-empty line if the model skipped the format.
                                if _use_e2g:
                                    _ans_lines = re.findall(r"(?im)^\s*(?:final\s+)?answer\s*:\s*(.+?)\s*$", _raw)
                                    if _ans_lines:
                                        response = _ans_lines[-1].strip()
                                    else:
                                        _nonempty = [ln.strip() for ln in _raw.splitlines() if ln.strip()]
                                        response = (_nonempty[-1] if _nonempty else _raw).strip()
                                else:
                                    response = _raw
                                if not response:
                                    # Say so. An empty content with a reasoning
                                    # trace means the budget went entirely to
                                    # thinking; silently falling through to the
                                    # next key hid that as "no response".
                                    _think_chars = len(
                                        str((data["choices"][0]["message"] or {}).get("reasoning") or "")
                                    )
                                    logger.warning(
                                        "[_generate_benchmark_qa_response] empty content "
                                        "(completion=%s tokens, reasoning=%s chars, max_tokens=%s) "
                                        "-- retrying this sample without reasoning",
                                        (data.get("usage") or {}).get("completion_tokens"),
                                        _think_chars, _bench_max_tokens,
                                    )
                                    # Guaranteed floor. Raising max_tokens does not
                                    # fix this reliably -- trace length varies per
                                    # question and a bigger reservation is refused
                                    # outright on the output-per-minute budget. So
                                    # thinking is an attempt, and a sample whose
                                    # budget it exhausts falls back to the answer
                                    # the non-thinking arm would have given rather
                                    # than being lost.
                                    _reasoning, _thinks = "none", False
                                    _bench_max_tokens = 96
                                    # On the observation, not only in the log: with
                                    # samples running concurrently a log warning
                                    # cannot be matched to its sample (125 warnings
                                    # were attributed to 64 samples).
                                    auxiliary_models.append("reasoning_fallback:empty_content")
                                    continue
                                model_used = f"groq/{groq_model}"
                                break
                            elif resp is not None and resp.status_code == 401:
                                logger.warning(
                                    "[_generate_benchmark_qa_response] Groq key invalid (401), trying next key"
                                )
                                continue
                            elif resp is not None and resp.status_code == 503 and _503_retry_count < _max_503_retries:
                                # Transient "over capacity" — Groq's own error message asks for
                                # exponential backoff; the old code gave up to extractive_fallback
                                # on the very first occurrence instead of honoring that.
                                _503_retry_count += 1
                                _backoff = 2 ** _503_retry_count
                                logger.warning(
                                    "[_generate_benchmark_qa_response] Groq 503 over capacity, "
                                    "backing off %ss (retry %d/%d)",
                                    _backoff, _503_retry_count, _max_503_retries,
                                )
                                await asyncio.sleep(_backoff)
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
                        url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
                        request_body = {
                            "contents": [{"parts": [{"text": user_prompt}]}],
                            "system_instruction": {"parts": [{"text": system_prompt}]},
                            "generationConfig": {"temperature": 0.0, "maxOutputTokens": 96},
                        }
                        resp = await _throttled_post_json(
                            provider="gemini",
                            url=url,
                            payload=request_body,
                            headers={"x-goog-api-key": gemini_key},
                            timeout=30.0,
                        )
                        if resp is not None and resp.status_code == 200:
                            data = resp.json()
                            usage_state = _usage_state_from_provider_usage(data.get("usageMetadata") or {})
                            candidates = data.get("candidates", [])
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

        except Exception as e:
            logger.error("[_generate_benchmark_qa_response] QA generation error: %s", e)

        if not response:
            if _env_flag("TRACECAG_BENCHMARK_FAIL_ON_PROVIDER_ERROR", False):
                raise RuntimeError("Primary benchmark provider returned no response")
            response = _generate_extractive_qa_response(question, clean_context)
            model_used = "extractive_fallback"

    adaptive_profile = str(state.get("adaptive_profile") or "").strip().lower()
    adaptive_config = _ADAPTIVE_PROFILES.get(adaptive_profile or "balanced") if adaptive_profile else None
    support_floor = float(state.get("adaptive_controller", {}).get("support_floor") or (adaptive_config.support_floor if adaptive_config else 0.4))
    grounding_margin = float(_env_float("TRACECAG_BENCHMARK_GROUNDING_MARGIN", 0.18))

    response = _postprocess_benchmark_qa_answer(
        question,
        response,
        answer_context,
        support_floor=max(0.2, min(0.8, support_floor)),
        grounding_margin=max(0.02, min(0.35, grounding_margin)),
        model_used=model_used,
    )

    overall_score = 1.0 if response and response.lower() != "unknown" else 0.0
    if state.get("cache_policy", "on") == "on":
        try:
            if _is_low_quality_benchmark_answer(response, answer_context, model_used):
                logger.info("[_generate_benchmark_qa_response] Skip cache write for low-quality benchmark answer")
            else:
                await _write_cache_entry(
                    state,
                    response,
                    "benchmark_qa",
                    [],
                    overall_score,
                    answer_context,
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
    retrieval_meta = dict(state.get("retrieval_meta") or {})
    if "_ircot_meta" in locals() and _ircot_meta.get("evaluated"):
        retrieval_meta["ircot"] = _ircot_meta
    models_used = list(locals().get("auxiliary_models", []))
    models_used.append(model_used)
    return {
        "tutor_response": response.strip(),
        "strategy": "benchmark_qa",
        "next_action": "continue",
        "overall_score": overall_score,
        "ttft_ms": latency_ms,
        "models_used": models_used,
        "retrieval_meta": retrieval_meta,
        **locals().get("usage_state", {}),
    }
