"""
Benchmark retrieval ranking — token-overlap heuristics, graph-propagation,
online ranker blend, and candidate building from HotpotQA / SQuAD-style datasets.
"""

from __future__ import annotations

import math
import re
from typing import Any, Dict, List, Mapping, Optional, Sequence

from api.services.trace_cag.env_helpers import _clip01, _env_flag, _env_float, _env_int
from api.services.trace_cag.retrieval_ranker import get_retrieval_ranker
from api.services.trace_cag.state import TraceCAGState

# Local copy of the decay constant (mirrors nodes_v2._RECENCY_LAMBDA).
_RECENCY_LAMBDA = 0.01

# tracecag_rapid bridge/graph weight. NOTE (2026-06-26, Run 22): raising this
# from 0.18→0.80 was offline-validated to lift recall@5 79%→84% and
# both-supporting@7 69%→78% with flat rank-1 precision — yet live it REGRESSED
# end-to-end EM 46.9%→43.8% (recovered 0 of the 25% "gold dropped by ranking"
# questions, flipped 2 clean wins via added distractors). Lesson: retrieval
# recall is NOT the binding constraint here — the 32B reader's multi-hop
# synthesis is — so more/higher-ranked evidence the reader can't use is
# net-negative. Default stays 0.18 (the EM-best config); knob kept for research.
_RAPID_GRAPH_WEIGHT = _env_float("TRACECAG_RAPID_GRAPH_WEIGHT", 0.18)


# ── Text helpers ──────────────────────────────────────────────────────────────

def _benchmark_tokens(text: str) -> set[str]:
    stopwords = {
        "the", "a", "an", "of", "in", "on", "at", "to", "for", "and", "or", "is", "are", "was", "were",
        "did", "do", "does", "who", "what", "where", "when", "which", "how", "many", "much", "by", "with",
        "that", "this", "these", "those", "from", "into", "about", "their", "his", "her", "its",
    }
    return {token for token in re.findall(r"[a-z0-9]+", text.lower()) if token not in stopwords}


def _content_tokens(text: str) -> list[str]:
    stopwords = {
        "the", "a", "an", "of", "in", "on", "at", "to", "for", "and", "or", "is", "are", "was", "were",
        "did", "do", "does", "who", "what", "where", "when", "which", "how", "many", "much", "by", "with",
        "that", "this", "these", "those", "from", "into", "about", "their", "his", "her", "its",
    }
    return [token for token in re.findall(r"[a-z0-9]+", text.lower()) if token not in stopwords]


def _split_benchmark_sentences(context: str) -> list[str]:
    normalized = context.replace("\n", " ")
    parts = re.split(r"(?<=[.!?])\s+", normalized)
    return [part.strip() for part in parts if part.strip()]


def _lexical_overlap_score(query: str, candidate: str) -> float:
    query_tokens = _benchmark_tokens(query)
    candidate_tokens = _benchmark_tokens(candidate)
    if not query_tokens or not candidate_tokens:
        return 0.0
    return len(query_tokens & candidate_tokens) / max(len(query_tokens), 1)


def _token_overlap_count(query: str, candidate: str) -> int:
    query_tokens = _benchmark_tokens(query)
    candidate_tokens = _benchmark_tokens(candidate)
    if not query_tokens or not candidate_tokens:
        return 0
    return len(query_tokens & candidate_tokens)


_QUESTION_HEAD_WORDS = frozenset(
    {
        "who", "what", "which", "when", "where", "why", "how",
        "was", "were", "is", "are", "did", "does", "do",
        "the", "a", "an",
    }
)


def _extract_query_anchors(question: str) -> list[str]:
    text = str(question or "")
    anchors: list[str] = []

    for quoted in re.findall(r'"([^\"]{2,80})"', text):
        q = quoted.strip().lower()
        if q:
            anchors.append(q)

    # Consecutive title-cased words often represent entities in HotpotQA-style
    # questions. The character classes must cover accented letters: with plain
    # [A-Z][a-z...] "Téa Leoni" matched nothing at all, so that hop had no anchor.
    for phrase in re.findall(
        r"\b[A-ZÀ-ÞĀ-Ž][a-z0-9à-öø-ÿā-ž''.-]*(?:\s+[A-ZÀ-ÞĀ-Ž][a-z0-9à-öø-ÿā-ž''.-]*)+\b",
        text,
    ):
        p = phrase.strip().lower()
        # A question opens with a capitalised interrogative/auxiliary, which the
        # title-case run then glues onto the first entity: "Were Scott Derrickson
        # and Ed Wood..." yielded the anchor "were scott derrickson", which no
        # passage can ever contain — so that hop silently had no anchor at all
        # and every anchor-driven score treated it as uncoverable.
        head, _, rest = p.partition(" ")
        if rest and head in _QUESTION_HEAD_WORDS:
            p = rest
        if p:
            anchors.append(p)

    deduped: list[str] = []
    seen: set[str] = set()
    for anchor in anchors:
        if anchor not in seen:
            seen.add(anchor)
            deduped.append(anchor)
    return deduped[:8]


def _anchors_present(anchors: list[str], title: str, body: str) -> set[str]:
    haystack = f"{title} {body}".lower()
    return {anchor for anchor in anchors if anchor and anchor in haystack}


def _anchor_coverage_score(anchors: list[str], title: str, body: str) -> float:
    if not anchors:
        return 0.0
    haystack = f"{title} {body}".lower()
    covered = sum(1 for anchor in anchors if anchor and anchor in haystack)
    return covered / max(len(anchors), 1)


def _anchor_title_exact_score(anchors: list[str], title: str) -> float:
    if not anchors:
        return 0.0
    title_l = str(title or "").lower()
    if not title_l:
        return 0.0

    best = 0.0
    for anchor in anchors:
        a = str(anchor or "").strip().lower()
        if not a:
            continue
        if a == title_l or a in title_l:
            tok_len = max(len(_benchmark_tokens(a)), 1)
            candidate = min(1.0, 0.45 + (0.12 * min(tok_len, 4)))
            if candidate > best:
                best = candidate
    return best


def _normalize_benchmark_surface(text: str) -> str:
    surface = str(text or "").lower()
    # Ignore parenthetical qualifiers so title matching can still fire.
    surface = re.sub(r"\([^)]*\)", " ", surface)
    surface = re.sub(r"[^a-z0-9]+", " ", surface)
    return " ".join(surface.split())


def _title_tokens(title: str) -> set[str]:
    return {token for token in _benchmark_tokens(title) if len(token) >= 3}


def _title_token_recall_score(question: str, title: str) -> float:
    question_tokens = _benchmark_tokens(question)
    title_tokens = _title_tokens(title)
    if not question_tokens or not title_tokens:
        return 0.0
    return len(question_tokens & title_tokens) / max(len(title_tokens), 1)


def _question_title_phrase_score(question: str, title: str) -> float:
    q_norm = _normalize_benchmark_surface(question)
    t_norm = _normalize_benchmark_surface(title)
    if not q_norm or not t_norm:
        return 0.0

    # Strong signal when the title (or de-article form) appears directly.
    if t_norm in q_norm:
        return 1.0
    t_no_article = re.sub(r"^(the|a|an)\s+", "", t_norm)
    if t_no_article and t_no_article in q_norm:
        return 0.92

    q_tokens = _benchmark_tokens(q_norm)
    t_tokens = [token for token in _title_tokens(t_norm) if len(token) >= 3]
    if not q_tokens or not t_tokens:
        return 0.0

    overlap = len(set(t_tokens) & q_tokens) / max(len(set(t_tokens)), 1)

    # Bonus for contiguous two-token title chunks inside the question.
    bigram_hit = 0.0
    if len(t_tokens) >= 2:
        q_space = f" {q_norm} "
        for idx in range(len(t_tokens) - 1):
            phrase = f" {t_tokens[idx]} {t_tokens[idx + 1]} "
            if phrase in q_space:
                bigram_hit = 0.18
                break

    return min(1.0, (0.82 * overlap) + bigram_hit)


def _title_similarity_for_diversity(a_title: str, b_title: str) -> float:
    a_tokens = _title_tokens(a_title)
    b_tokens = _title_tokens(b_title)
    if not a_tokens or not b_tokens:
        return 0.0
    inter = len(a_tokens & b_tokens)
    union = len(a_tokens | b_tokens)
    return inter / max(union, 1)


def _select_diverse_multihop_evidence(
    *,
    items: list[Dict[str, Any]],
    question: str,
    budget: int,
) -> list[Dict[str, Any]]:
    if budget <= 0 or not items:
        return []
    if len(items) <= budget:
        return items

    anchors = _extract_query_anchors(question)
    remaining = list(items)
    selected: list[Dict[str, Any]] = []
    covered_anchors: set[str] = set()

    # Phase 1 — guarantee one slot per question anchor while slots remain.
    # A weighted coverage bonus is not enough: with 0.30 marginal weight a
    # redundant passage about the covered hop still outranks the missing hop's
    # passage whenever its score is ~0.35 higher, which is common. A question
    # naming two entities is unanswerable without both, so coverage is a
    # constraint here, not a preference — this is what moves all_support_at_k.
    for anchor in anchors:
        if len(selected) >= budget:
            break
        if anchor in covered_anchors:
            continue
        best = max(
            (
                item
                for item in remaining
                if anchor
                in _anchors_present(
                    anchors, str(item.get("title") or ""), str(item.get("text") or "")
                )
            ),
            key=lambda item: float(item.get("fusion_score") or 0.0),
            default=None,
        )
        if best is None:
            continue
        remaining.remove(best)
        selected.append(best)
        covered_anchors |= _anchors_present(
            anchors, str(best.get("title") or ""), str(best.get("text") or "")
        )

    # Phase 2 — fill the rest on the usual relevance/diversity objective.
    while remaining and len(selected) < budget:
        best_idx = 0
        best_score = float("-inf")
        for idx, item in enumerate(remaining):
            base = float(item.get("fusion_score") or 0.0)
            title = str(item.get("title") or "")
            text = str(item.get("text") or "")
            item_anchors = _anchors_present(anchors, title, text)
            marginal = (
                len(item_anchors - covered_anchors) / max(len(anchors), 1) if anchors else 0.0
            )

            max_sim = 0.0
            for prev in selected:
                sim = _title_similarity_for_diversity(title, str(prev.get("title") or ""))
                if sim > max_sim:
                    max_sim = sim

            # MMR-like objective: keep strong evidence while avoiding near-duplicate
            # titles, and prefer a passage covering an anchor nothing else covers.
            mmr = (0.78 * base) + (0.30 * marginal) - (0.22 * max_sim)
            if mmr > best_score:
                best_score = mmr
                best_idx = idx

        chosen = remaining.pop(best_idx)
        selected.append(chosen)
        covered_anchors |= _anchors_present(
            anchors, str(chosen.get("title") or ""), str(chosen.get("text") or "")
        )

    # Coverage decided membership; relevance decides the order the reader sees.
    selected.sort(key=lambda item: float(item.get("fusion_score") or 0.0), reverse=True)
    return selected


def _benchmark_evidence_snippet(
    *,
    question: str,
    title: str,
    text: str,
    max_sentences: int = 2,
    max_chars: int = 520,
) -> str:
    """Keep benchmark evidence reader-friendly without changing ranking.

    ponytail: clipping from rank 3 deletes the answer outright in 3 of 54 span
    questions (n=64), but retaining bridge sentences (link_titles, measured
    2026-08-28) cost more F1 than it recovered in BOTH modes and was reverted.
    Fixing this needs a larger context budget, not a smarter snippet.
    """
    body = str(text or "").strip()
    if not body:
        return ""

    sentences = _split_benchmark_sentences(body)
    if len(sentences) <= max_sentences and len(body) <= max_chars:
        return body

    anchors = _extract_query_anchors(question)
    q_tokens = set(_content_tokens(question))
    question_lower = str(question or "").lower()
    want_numbers = any(
        token in question_lower for token in ("when", "year", "how many", "how much")
    )

    def _score(sentence: str, idx: int) -> float:
        s_tokens = set(_content_tokens(sentence))
        overlap = len(q_tokens & s_tokens) / max(len(q_tokens), 1) if q_tokens else 0.0
        anchor = _anchor_coverage_score(anchors, title, sentence)
        number_bonus = 0.18 if want_numbers and re.search(r"\b\d{2,4}\b", sentence) else 0.0
        first_sentence_bonus = 0.12 if idx == 0 else 0.0
        return overlap + (0.35 * anchor) + number_bonus + first_sentence_bonus

    ranked = sorted(
        enumerate(sentences),
        key=lambda item: (_score(item[1], item[0]), -item[0]),
        reverse=True,
    )
    keep = {0}
    for idx, _ in ranked:
        keep.add(idx)
        if len(keep) >= max_sentences:
            break

    selected = " ".join(sentences[idx] for idx in sorted(keep)).strip()
    return selected[:max_chars].rstrip()


# ── Graph helpers ─────────────────────────────────────────────────────────────

def _build_candidate_graph(candidates: list[Dict[str, Any]]) -> dict[str, dict[str, float]]:
    """
    Bridge-entity adjacency for multi-hop reasoning: edge A->B means A's body
    text names the bridge entity that B's title covers (the standard HotpotQA
    bridge pattern, where doc A mentions the entity whose own page B holds the
    next-hop answer). Edge weight 1.0 = B's full title appears verbatim in A's
    text (high-precision bridge mention); 0.4 = weaker token-overlap fallback
    for titles that get paraphrased instead of quoted exactly.
    """
    title_norm_map = {
        str(candidate["item_id"]): _normalize_benchmark_surface(
            str(candidate.get("title") or candidate.get("item_id") or "")
        )
        for candidate in candidates
    }
    title_token_map = {
        str(candidate["item_id"]): _title_tokens(str(candidate.get("title") or candidate.get("item_id") or ""))
        for candidate in candidates
    }
    adjacency: dict[str, dict[str, float]] = {str(candidate["item_id"]): {} for candidate in candidates}

    for candidate in candidates:
        source_id = str(candidate["item_id"])
        source_text_norm = _normalize_benchmark_surface(str(candidate.get("text") or ""))
        source_text_tokens = set(_benchmark_tokens(str(candidate.get("text") or "")))
        for other in candidates:
            target_id = str(other["item_id"])
            if source_id == target_id:
                continue

            target_title_norm = title_norm_map.get(target_id, "")
            if target_title_norm and len(target_title_norm) >= 4 and f" {target_title_norm} " in f" {source_text_norm} ":
                adjacency[source_id][target_id] = 1.0
                continue

            title_tokens = title_token_map.get(target_id, set())
            if not title_tokens:
                continue
            overlap = len(source_text_tokens & title_tokens)
            threshold = 1 if len(title_tokens) <= 2 else 2
            if overlap >= threshold:
                adjacency[source_id][target_id] = 0.4
    return adjacency


def _normalize_score_map(scores: dict[str, float]) -> dict[str, float]:
    positive = {key: max(0.0, value) for key, value in scores.items()}
    total = sum(positive.values())
    if total <= 0:
        size = max(len(positive), 1)
        return {key: 1.0 / size for key in positive}
    return {key: value / total for key, value in positive.items()}


# ── Complexity & budget ───────────────────────────────────────────────────────

def _question_complexity_score(question: str) -> int:
    text = (question or "").lower()
    score = 1
    if any(k in text for k in ["and", "both", "compare", "before", "after", "while"]):
        score += 1
    if any(k in text for k in ["who", "where", "when", "which", "how many", "how much"]):
        score += 1
    if len(text.split()) >= 14:
        score += 1
    return min(score, 4)


def _compute_evidence_budget(
    *,
    question: str,
    retrieval_policy: str,
    benchmark_mode: str,
    benchmark_candidates: bool,
    adaptive_profile: str = "",
    benchmark_task: str = "",
) -> int:
    # Lazy import to avoid circular dependency at module load time.
    from api.services.trace_cag.benchmark.adaptive import _ADAPTIVE_PROFILES

    base = max(2, _env_int("TRACECAG_EVIDENCE_BUDGET_BASE", 5))
    max_budget = max(base, _env_int("TRACECAG_EVIDENCE_BUDGET_MAX", 9))
    complexity = _question_complexity_score(question)
    budget = base + max(0, complexity - 2)

    if retrieval_policy == "rapid":
        # Keep full evidence budget for multihop-style questions in rapid mode.
        if benchmark_task != "multihop_qa":
            budget -= 1
    elif retrieval_policy == "adaptive":
        config = _ADAPTIVE_PROFILES.get(adaptive_profile or "balanced")
        if config is not None:
            budget += int(config.evidence_budget_delta)

    if benchmark_candidates and benchmark_mode == "tracecag_adaptive":
        config = _ADAPTIVE_PROFILES.get(adaptive_profile or "balanced")
        if config is not None:
            budget = max(4, min(max_budget, budget + int(config.evidence_budget_delta)))

    return max(2, min(max_budget, budget))


# ── Ranking ───────────────────────────────────────────────────────────────────

def _rank_benchmark_candidates(
    question: str,
    candidates: list[Dict[str, Any]],
    ranker: str,
    benchmark_mode: str = "",
    adaptive_profile: str = "",
) -> list[Dict[str, Any]]:
    # Lazy import to avoid circular dependency at module load time.
    from api.services.trace_cag.benchmark.adaptive import _ADAPTIVE_PROFILES

    if not candidates:
        return []

    anchors = _extract_query_anchors(question)

    base_scores: dict[str, float] = {}
    for candidate in candidates:
        item_id = str(candidate["item_id"])
        title = str(candidate.get("title") or item_id)
        text = str(candidate.get("text") or "")
        title_score = _lexical_overlap_score(question, title)
        body_score = _lexical_overlap_score(question, text)
        title_overlap = _token_overlap_count(question, title)
        title_prior = min(1.0, title_score + (0.12 * min(title_overlap, 3)))
        anchor_coverage = _anchor_coverage_score(anchors, title, text)
        anchor_title_exact = _anchor_title_exact_score(anchors, title)
        title_token_recall = _title_token_recall_score(question, title)
        title_phrase = _question_title_phrase_score(question, title)
        base_scores[item_id] = max(
            body_score,
            (0.55 * body_score) + (0.45 * title_score),
            (0.70 * title_prior) + (0.30 * body_score),
            (0.65 * body_score) + (0.20 * title_prior) + (0.15 * anchor_coverage),
            (0.55 * body_score) + (0.20 * title_prior) + (0.10 * anchor_coverage) + (0.15 * anchor_title_exact),
            (0.46 * body_score) + (0.16 * title_prior) + (0.14 * anchor_coverage) + (0.14 * title_token_recall) + (0.10 * title_phrase),
            (0.34 * body_score) + (0.14 * title_prior) + (0.20 * title_token_recall) + (0.18 * anchor_title_exact) + (0.14 * title_phrase),
            (0.30 * body_score) + (0.18 * title_prior) + (0.22 * title_phrase) + (0.16 * title_token_recall) + (0.14 * anchor_coverage),
        )

    if ranker == "flat":
        scored = []
        for candidate in candidates:
            item_id = str(candidate["item_id"])
            enriched = dict(candidate)
            enriched["vec_sim"] = base_scores[item_id]
            enriched["graph_score"] = 0.0
            enriched["memory_score"] = 0.0
            scored.append(enriched)
        return scored

    adjacency = _build_candidate_graph(candidates)
    degree_scores = {
        item_id: (sum(neighbors.values()) / max(len(candidates) - 1, 1))
        for item_id, neighbors in adjacency.items()
    }
    seed_ids = [
        item_id
        for item_id, _ in sorted(base_scores.items(), key=lambda item: item[1], reverse=True)[:2]
    ]

    graph_scores: dict[str, float] = {item_id: 0.0 for item_id in base_scores}
    for item_id in graph_scores:
        seed_bridge = 0.0
        for seed_id in seed_ids:
            if seed_id == item_id:
                seed_bridge = max(seed_bridge, base_scores.get(seed_id, 0.0))
                continue
            edge_weight = adjacency.get(seed_id, {}).get(item_id) or adjacency.get(item_id, {}).get(seed_id)
            if edge_weight:
                seed_bridge = max(seed_bridge, base_scores.get(seed_id, 0.0) * edge_weight)
        graph_scores[item_id] = (0.7 * seed_bridge) + (0.3 * degree_scores.get(item_id, 0.0))

    memory_state = _normalize_score_map(base_scores)
    for _ in range(2):
        propagated = {item_id: 0.15 * memory_state.get(item_id, 0.0) for item_id in memory_state}
        for source_id, neighbors in adjacency.items():
            if not neighbors:
                continue
            weight_total = sum(neighbors.values()) or 1.0
            shared = 0.85 * memory_state.get(source_id, 0.0)
            for target_id, edge_weight in neighbors.items():
                propagated[target_id] = propagated.get(target_id, 0.0) + shared * (edge_weight / weight_total)
        memory_state = _normalize_score_map(propagated)

    scored_candidates: list[Dict[str, Any]] = []
    for candidate in candidates:
        item_id = str(candidate["item_id"])
        base_score = base_scores[item_id]
        graph_score = graph_scores.get(item_id, 0.0)
        memory_score = memory_state.get(item_id, 0.0)
        title = str(candidate.get("title") or item_id)
        title_overlap = _token_overlap_count(question, title)
        query_coverage = min(1.0, title_overlap / 3.0)
        anchor_coverage = _anchor_coverage_score(anchors, title, str(candidate.get("text") or ""))
        anchor_title_exact = _anchor_title_exact_score(anchors, title)
        title_token_recall = _title_token_recall_score(question, title)
        title_phrase = _question_title_phrase_score(question, title)

        if ranker == "graph":
            # Keep proxy modes intentionally distinct in benchmark runs.
            if benchmark_mode == "graphrag_proxy":
                final_score = (
                    (0.28 * base_score)
                    + (0.56 * graph_score)
                    + (0.08 * query_coverage)
                    + (0.08 * anchor_coverage)
                )
            elif benchmark_mode == "tracecag_rapid":
                # Keep the full lexical base score (matches flat ranker's strength on
                # single-hop docs) and add the bridge/graph signal on top instead of
                # diluting base_score — diluting it previously made multi-hop bridge
                # targets win at the cost of demoting strong direct matches.
                final_score = (
                    base_score
                    + (_RAPID_GRAPH_WEIGHT * graph_score)
                    + (0.06 * memory_score)
                    + (0.06 * query_coverage)
                    + (0.05 * anchor_coverage)
                    + (0.03 * anchor_title_exact)
                    + (0.03 * title_token_recall)
                )
                if title_phrase >= 0.9:
                    final_score += 0.04
                elif title_phrase >= 0.6:
                    final_score += 0.03
                else:
                    final_score += 0.01 * title_phrase
            elif benchmark_mode == "tracecag_adaptive":
                profile = _ADAPTIVE_PROFILES.get(adaptive_profile or "balanced")
                if profile is None:
                    profile = _ADAPTIVE_PROFILES["balanced"]

                if profile.name == "quality":
                    final_score = (
                        (0.30 * base_score)
                        + (0.18 * graph_score)
                        + (0.14 * query_coverage)
                        + (0.10 * anchor_coverage)
                        + (0.08 * memory_score)
                        + (0.12 * anchor_title_exact)
                        + (0.08 * title_token_recall)
                    )
                    if title_phrase >= 0.9:
                        final_score += 0.22
                    elif title_phrase >= 0.6:
                        final_score += 0.12
                    else:
                        final_score += 0.05 * title_phrase
                elif profile.name == "fast":
                    final_score = (
                        (0.40 * base_score)
                        + (0.20 * graph_score)
                        + (0.14 * query_coverage)
                        + (0.10 * anchor_coverage)
                        + (0.08 * anchor_title_exact)
                        + (0.08 * title_phrase)
                    )
                else:  # balanced
                    final_score = (
                        (0.30 * base_score)
                        + (0.18 * graph_score)
                        + (0.14 * query_coverage)
                        + (0.10 * anchor_coverage)
                        + (0.08 * memory_score)
                        + (0.12 * anchor_title_exact)
                        + (0.08 * title_token_recall)
                    )
                    if title_phrase >= 0.9:
                        final_score += 0.18
                    elif title_phrase >= 0.6:
                        final_score += 0.10
                    else:
                        final_score += 0.04 * title_phrase
            else:
                final_score = (
                    (0.50 * base_score)
                    + (0.32 * graph_score)
                    + (0.10 * query_coverage)
                    + (0.08 * anchor_coverage)
                )
        elif ranker == "memory":
            final_score = (
                (0.36 * base_score)
                + (0.46 * memory_score)
                + (0.10 * query_coverage)
                + (0.08 * anchor_coverage)
            )
        else:
            final_score = base_score + (0.08 * query_coverage) + (0.08 * anchor_coverage)

        if title_overlap >= 2:
            final_score += 0.08
        if title_overlap >= 3:
            final_score += 0.05

        enriched = dict(candidate)
        enriched["vec_sim"] = base_score
        enriched["graph_score"] = graph_score
        enriched["memory_score"] = memory_score
        enriched["query_coverage"] = query_coverage
        enriched["anchor_coverage"] = anchor_coverage
        enriched["anchor_title_exact"] = anchor_title_exact
        enriched["title_token_recall"] = title_token_recall
        enriched["title_phrase"] = title_phrase
        enriched["title_overlap"] = float(title_overlap)
        enriched["fusion_score"] = final_score
        scored_candidates.append(enriched)

    return scored_candidates


def _ranker_enabled() -> bool:
    return _env_flag("TRACECAG_USE_LEARNED_RANKER", True)


def _candidate_feature_vector(question: str, item: Dict[str, Any]) -> Dict[str, float]:
    title = str(item.get("title") or item.get("item_id") or "")
    text = str(item.get("text") or "")
    anchors = _extract_query_anchors(question)

    kg_depth = float(item.get("kg_depth") or 1.0)
    turns_ago = max(0.0, float(item.get("turns_ago") or 0.0))

    base_score = _clip01(float(item.get("fusion_score", item.get("vec_sim", 0.0)) or 0.0))
    body_overlap = _clip01(_lexical_overlap_score(question, text))
    title_overlap = _clip01(_lexical_overlap_score(question, title))
    anchor_coverage = _clip01(_anchor_coverage_score(anchors, title, text))
    title_phrase = _clip01(_question_title_phrase_score(question, title))
    title_token_recall = _clip01(_title_token_recall_score(question, title))
    kg_proximity = _clip01(1.0 / (1.0 + max(0.0, kg_depth)))
    vec_signal = _clip01(float(item.get("vec_sim") or 0.0))
    graph_signal = _clip01(float(item.get("graph_score") or 0.0))
    memory_signal = _clip01(float(item.get("memory_score") or 0.0))
    recency_signal = _clip01(math.exp(-_RECENCY_LAMBDA * turns_ago))
    external_penalty = 1.0 if bool(item.get("is_external") or str(item.get("item_id") or "").startswith("ext_")) else 0.0

    return {
        "base_score": base_score,
        "body_overlap": body_overlap,
        "title_overlap": title_overlap,
        "anchor_coverage": anchor_coverage,
        "title_phrase": title_phrase,
        "title_token_recall": title_token_recall,
        "kg_proximity": kg_proximity,
        "vec_signal": vec_signal,
        "graph_signal": graph_signal,
        "memory_signal": memory_signal,
        "recency_signal": recency_signal,
        "external_penalty": external_penalty,
    }


def _weak_relevance_label(question: str, item: Dict[str, Any]) -> Optional[float]:
    if "is_relevant" in item:
        return 1.0 if bool(item.get("is_relevant")) else 0.0

    title = str(item.get("title") or item.get("item_id") or "")
    text = str(item.get("text") or "")
    anchors = _extract_query_anchors(question)
    body_overlap = _lexical_overlap_score(question, text)
    title_overlap = _lexical_overlap_score(question, title)
    anchor_coverage = _anchor_coverage_score(anchors, title, text)
    title_phrase = _question_title_phrase_score(question, title)
    vec_signal = float(item.get("vec_sim") or item.get("fusion_score") or 0.0)

    strong = max(body_overlap, title_overlap, anchor_coverage, title_phrase)
    if strong >= 0.68 and vec_signal >= 0.20:
        return 1.0
    if strong <= 0.10 and vec_signal <= 0.20:
        return 0.0
    return None


def _rank_with_online_ranker(
    *,
    question: str,
    evidence_items: List[Dict[str, Any]],
    allow_exploration: bool,
    benchmark_mode: str = "",
) -> List[Dict[str, Any]]:
    if not evidence_items:
        return []

    if not _ranker_enabled():
        return sorted(evidence_items, key=lambda item: float(item.get("fusion_score", item.get("vec_sim", 0.0))), reverse=True)

    ranker = get_retrieval_ranker()
    blended_weight = _clip01(_env_float("TRACECAG_RANKER_BLEND", 0.42))

    # Keep graph/title heuristic dominant until online ranker has enough updates.
    mode = str(benchmark_mode or "").strip().lower()
    if mode == "tracecag_rapid":
        snapshot = ranker.snapshot()
        updates = int(snapshot.get("updates", 0) or 0)
        warmup_updates = max(1, _env_int("TRACECAG_RANKER_WARMUP_UPDATES", 40))
        if updates < warmup_updates:
            blended_weight = min(blended_weight, 0.22)
        else:
            blended_weight = min(blended_weight, 0.35)

    base_weight = 1.0 - blended_weight

    ranked: List[Dict[str, Any]] = []
    training_payload: List[Dict[str, Any]] = []

    for item in evidence_items:
        enriched = dict(item)
        features = _candidate_feature_vector(question, enriched)
        item_id = str(enriched.get("item_id") or enriched.get("title") or "")

        learned_score = ranker.score(
            item_id=item_id,
            features=features,
            allow_exploration=allow_exploration,
        )
        base_score = float(enriched.get("fusion_score", enriched.get("vec_sim", 0.0)) or 0.0)
        final_score = (base_weight * base_score) + (blended_weight * learned_score)

        # Keep a small anchor floor to avoid hard demotion, without over-peaking top-1.
        anchor_floor = (0.04 * features.get("anchor_coverage", 0.0)) + (0.05 * features.get("title_phrase", 0.0))
        if features.get("title_phrase", 0.0) >= 0.9 and features.get("anchor_coverage", 0.0) >= 0.60:
            final_score = max(final_score, base_score + anchor_floor)

        label = _weak_relevance_label(question, enriched)
        enriched["rank_features"] = features
        enriched["learned_score"] = learned_score
        enriched["fusion_score"] = final_score
        if label is not None:
            enriched["_rank_label"] = label

        ranked.append(enriched)

        if label is not None and item_id:
            training_payload.append(
                {
                    "item_id": item_id,
                    "label": label,
                    "features": features,
                }
            )

    ranked.sort(key=lambda item: float(item.get("fusion_score") or 0.0), reverse=True)

    if training_payload:
        ranker.observe(training_payload)

    return ranked


def _build_benchmark_candidates(state: TraceCAGState) -> tuple[list[Dict[str, Any]], set[str]]:
    benchmark_metadata = state.get("benchmark_metadata") or {}
    benchmark_task = state.get("benchmark_task") or ""

    candidates: list[Dict[str, Any]] = []
    relevant_ids: set[str] = set()

    if benchmark_task == "multihop_qa":
        supporting_titles = benchmark_metadata.get("supporting_titles") or []
        relevant_ids = {str(title).strip().lower() for title in supporting_titles if str(title).strip()}
        for idx, doc in enumerate(benchmark_metadata.get("context_docs") or []):
            title = str(doc.get("title") or f"doc_{idx}").strip()
            text = str(doc.get("text") or "").strip()
            item_id = title.lower()
            if text:
                candidates.append({
                    "item_id": item_id,
                    "title": title,
                    "text": text,
                    "kg_depth": 1,
                    "turns_ago": 0,
                })
    elif benchmark_task == "retrieval_qa":
        relevant_ids = {str(item).strip() for item in (benchmark_metadata.get("relevant_passage_ids") or []) if str(item).strip()}
        for idx, passage in enumerate(benchmark_metadata.get("passages") or []):
            item_id = str(passage.get("item_id") or f"passage_{idx}")
            text = str(passage.get("text") or "").strip()
            if text:
                candidates.append({
                    "item_id": item_id,
                    "title": str(passage.get("title") or item_id),
                    "text": text,
                    "kg_depth": 1,
                    "turns_ago": 0,
                })

    return candidates, relevant_ids


# ── Online ranker update ──────────────────────────────────────────────────────

def _answer_support_score(answer: str, context: str) -> float:
    candidate = str(answer or "").strip().lower()
    if not candidate or candidate == "unknown":
        return 0.0
    if candidate in {"yes", "no"}:
        # Yes/no support is handled primarily by dedicated extractor.
        return 0.5

    answer_tokens = _content_tokens(candidate)
    context_tokens = set(_content_tokens(context))
    if not answer_tokens:
        return 0.0

    token_support = sum(1 for tok in answer_tokens if tok in context_tokens) / max(len(answer_tokens), 1)
    phrase_bonus = 0.25 if candidate and candidate in str(context or "").lower() else 0.0
    return max(0.0, min(1.0, token_support + phrase_bonus))


def _update_ranker_from_generation(
    question: str,
    response: str,
    retrieval_trace: Sequence[Mapping[str, Any]],
) -> None:
    if not _ranker_enabled() or not retrieval_trace:
        return

    ranker = get_retrieval_ranker()
    training_payload: List[Dict[str, Any]] = []
    anchors = _extract_query_anchors(question)

    for item in retrieval_trace[:8]:
        item_id = str(item.get("item_id") or item.get("title") or "")
        item_text = str(item.get("text") or "")
        if not item_id or not item_text:
            continue

        support = _answer_support_score(response, item_text)
        label: Optional[float] = None
        if support >= 0.52:
            label = 1.0
        elif support <= 0.10 and _anchor_coverage_score(
            anchors, str(item.get("title") or ""), item_text
        ) <= 0.0:
            # "Does not contain the answer" is not "irrelevant". On a bridge
            # question the answer lives in hop 2, so the hop-1 passage — the one
            # naming the bridge entity — scored ~0 support and was trained as a
            # negative: 31.4% of gold supporting passages in the n=64 run were
            # labelled 0.0, teaching the ranker to demote exactly what multi-hop
            # retrieval needs. A passage carrying a question anchor is evidence
            # wherever the answer sits; only anchor-free passages are true
            # distractors (442 of those remain, so negatives stay plentiful).
            label = 0.0

        if label is None:
            continue

        feature_item = {
            "item_id": item_id,
            "title": str(item.get("title") or item_id),
            "text": item_text,
            "kg_depth": 1,
            "turns_ago": 0,
            "vec_sim": float(item.get("score") or 0.0),
            "fusion_score": float(item.get("score") or 0.0),
            "is_external": str(item_id).startswith("ext_"),
        }
        features = _candidate_feature_vector(question, feature_item)
        training_payload.append(
            {
                "item_id": item_id,
                "label": label,
                "features": features,
            }
        )

    if training_payload:
        ranker.observe(training_payload)
