"""
EvaluationAgent — centralised scoring and vocabulary estimation for TraceCAG pipeline.

Pure-logic class (no I/O, no framework dependencies).
All methods are @classmethod so no instantiation is needed.
"""

from __future__ import annotations

import math
import re
from typing import Dict, List, Optional


class EvaluationAgent:
    """
    Centralises three previously-scattered concerns:
      1. CEFR vocabulary-level estimation from free text
      2. Overall score computation (grammar + fluency + vocab CEFR)
      3. Retrieval quality metric (precision@K from trace)
    """

    # ── CEFR marker-word sets ────────────────────────────────────────────────
    # Drawn from the 173 production vocabulary items in seed_courses.py
    # and established CEFR/AWL/IELTS word-frequency lists.

    _C2_MARKERS: frozenset = frozenset({
        "albeit", "notwithstanding", "elucidate", "conspicuous",
        "juxtapose", "mitigate", "pragmatic", "ubiquitous",
        "convoluted", "predilection", "ostensibly", "ameliorate",
        "concatenate", "obfuscate", "perspicacious", "recalcitrant",
        "sycophant", "tendentious", "verisimilitude", "wanton",
    })
    _C1_MARKERS: frozenset = frozenset({
        "analytical", "hypothesis", "paradigm", "facilitate",
        "coherent", "ambiguous", "concede", "inherent",
        "corroborate", "disseminate", "empirical", "exacerbate",
        "incentivise", "meticulous", "nuanced", "plausible",
        "rigorous", "substantiate", "ubiquitous", "warrant",
    })
    _B2_MARKERS: frozenset = frozenset({
        "consequently", "nevertheless", "evaluate", "integrate",
        "summarize", "significant", "sufficient", "perspective",
        "acknowledge", "anticipate", "criteria", "elaborate",
        "emphasis", "furthermore", "highlight", "hypothesis",
        "moreover", "nonetheless", "reinforce", "whereas",
    })
    _B1_MARKERS: frozenset = frozenset({
        "although", "however", "suggest", "compare",
        "explain", "similar", "different", "important", "because",
        "achieve", "advantage", "benefit", "concentrate",
        "describe", "develop", "examine", "identify",
        "include", "involve", "provide", "require",
    })

    # ── CEFR level → numeric (for score computation) ────────────────────────
    _VOCAB_NUMERIC: Dict[str, float] = {
        "A1": 0.10,
        "A2": 0.25,
        "B1": 0.45,
        "B2": 0.65,
        "C1": 0.85,
        "C2": 1.00,
    }

    # ── Score weights (must sum to 1.0) ─────────────────────────────────────
    _W_GRAMMAR: float = 0.40
    _W_FLUENCY: float = 0.30
    _W_VOCAB: float = 0.30

    # ──────────────────────────────────────────────────────────────────────────

    @classmethod
    def estimate_vocab_level(cls, text: str) -> str:
        """
        Estimate CEFR vocabulary level from free text using tier-word membership.

        Priority: C2 > C1 > B2 > B1 (highest match wins).
        Falls back to average word-length heuristic for very short / unknown text.

        Args:
            text: User input or LLM response text.

        Returns:
            CEFR level string: "A1" | "A2" | "B1" | "B2" | "C1" | "C2"
        """
        if not text or not text.strip():
            return "A1"

        words = frozenset(re.findall(r"[a-z]{3,}", text.lower()))

        if words & cls._C2_MARKERS:
            return "C2"
        if words & cls._C1_MARKERS:
            return "C1"
        if words & cls._B2_MARKERS:
            return "B2"
        if words & cls._B1_MARKERS:
            return "B1"

        # Heuristic fallback: average word length correlates with complexity
        if words:
            avg_len = sum(len(w) for w in words) / len(words)
            if avg_len < 4.0:
                return "A1"
            if avg_len < 5.0:
                return "A2"

        return "B1"  # safe default

    @classmethod
    def compute_overall_score(
        cls,
        grammar: float,
        fluency: float,
        vocab_level: str,
    ) -> float:
        """
        Compute weighted overall score:
          overall = 0.40 * grammar + 0.30 * fluency + 0.30 * vocab_numeric

        Replaces the naive grammar*0.6 + fluency*0.4 formula used in generate_node.

        Args:
            grammar:     Grammar accuracy score, range [0, 1].
            fluency:     Fluency score, range [0, 1].
            vocab_level: CEFR level string (e.g. "B1").

        Returns:
            Weighted overall score, range [0, 1].
        """
        vocab_numeric = cls._VOCAB_NUMERIC.get(vocab_level, 0.45)
        return (
            cls._W_GRAMMAR * grammar
            + cls._W_FLUENCY * fluency
            + cls._W_VOCAB * vocab_numeric
        )

    @classmethod
    def compute_retrieval_quality(
        cls,
        retrieval_trace: List[Dict],
    ) -> Optional[float]:
        """
        Compute retrieval quality as precision@K (fraction of relevant items).

        Uses the `is_relevant` flag in each trace item (set during benchmark runs).
        Returns None when trace is empty or no items have the `is_relevant` key
        (i.e. not a benchmark run).

        Args:
            retrieval_trace: List of dicts from state["retrieval_trace"].

        Returns:
            Precision@K in [0, 1], or None if not applicable.
        """
        if not retrieval_trace:
            return None

        # Only score when at least one item has the is_relevant key
        scored_items = [t for t in retrieval_trace if "is_relevant" in t]
        if not scored_items:
            return None

        relevant = sum(1 for t in scored_items if t.get("is_relevant"))
        return relevant / len(scored_items)

    # ── Text Quality Metrics ────────────────────────────────────────────────

    @classmethod
    def apply_corrections(cls, text: str, errors: List[Dict]) -> str:
        """
        Reconstruct corrected text by applying error span substitutions.

        Each error dict must have ``span`` (original text) and ``correction``
        (target text).  Overlapping spans are applied left-to-right; first-match
        wins so the operation is safe even for duplicate spans.

        Args:
            text:   Original user input.
            errors: List of diagnosis error dicts from state["diagnosis_errors"].

        Returns:
            Text with all corrections applied.
        """
        corrected = text
        for err in errors:
            span = err.get("span", "").strip()
            correction = err.get("correction", "").strip()
            if span and correction and span != correction:
                corrected = corrected.replace(span, correction, 1)
        return corrected

    @classmethod
    def compute_wer(cls, hypothesis: str, reference: str) -> float:
        """
        Word Error Rate (WER) using word-level Levenshtein distance.

        WER = (S + D + I) / N
          S = substitutions, D = deletions, I = insertions, N = reference words.

        For language-learning use: hypothesis = user input,
        reference = corrected version (from ``apply_corrections``).

        Returns 0.0 when reference is empty (nothing to correct).
        """
        h = hypothesis.lower().split()
        r = reference.lower().split()
        if not r:
            return 0.0
        n, m = len(r), len(h)
        # 1-D DP rolling array (O(N) space)
        prev = list(range(m + 1))
        for i in range(1, n + 1):
            curr = [i] + [0] * m
            for j in range(1, m + 1):
                if r[i - 1] == h[j - 1]:
                    curr[j] = prev[j - 1]
                else:
                    curr[j] = 1 + min(prev[j], curr[j - 1], prev[j - 1])
            prev = curr
        return prev[m] / n

    @classmethod
    def compute_type_token_ratio(cls, text: str) -> float:
        """
        Type-Token Ratio (TTR) — lexical diversity of free text.

        TTR = unique_words / total_words.  Range [0, 1]; higher = more diverse.
        Short texts (< 5 words) are clamped to 1.0 to avoid misleadingly high
        scores from trivial inputs.

        Args:
            text: User input or generated response.

        Returns:
            TTR in [0, 1].
        """
        tokens = re.findall(r"[a-zA-Z]+", text.lower())
        if len(tokens) < 5:
            return 1.0
        return len(set(tokens)) / len(tokens)

    @classmethod
    def compute_error_density(cls, correction_count: int, word_count: int) -> float:
        """
        Error density — grammatical errors per 100 words.

        Provides a normalised quality signal comparable across inputs of
        different lengths.  Returns 0.0 for empty inputs.

        Args:
            correction_count: Number of diagnosed error spans.
            word_count:       Total words in user input.

        Returns:
            Errors per 100 words, or 0.0 if word_count is 0.
        """
        if word_count == 0:
            return 0.0
        return round(correction_count / word_count * 100, 2)

    # ── Retrieval Ranking Metrics ───────────────────────────────────────────

    @classmethod
    def compute_recall_k(
        cls,
        retrieval_trace: List[Dict],
        total_relevant: int,
    ) -> Optional[float]:
        """
        Recall@K — fraction of all relevant documents that were retrieved.

        Recall@K = |relevant ∩ retrieved| / |relevant_total|

        Returns None when there is no ground-truth signal (``is_relevant`` key
        absent from all trace items, or ``total_relevant`` is 0).

        Args:
            retrieval_trace: List of dicts from state["retrieval_trace"].
            total_relevant:  Total number of gold-standard relevant items in
                             the corpus (from benchmark_metadata).
        """
        if not retrieval_trace or total_relevant <= 0:
            return None
        scored_items = [t for t in retrieval_trace if "is_relevant" in t]
        if not scored_items:
            return None
        relevant_retrieved = sum(1 for t in scored_items if t.get("is_relevant"))
        return relevant_retrieved / total_relevant

    @classmethod
    def compute_ndcg_k(cls, retrieval_trace: List[Dict]) -> Optional[float]:
        """
        NDCG@K (Normalised Discounted Cumulative Gain) for ranking quality.

        Measures whether relevant documents appear near the top of the result
        list.  Uses binary relevance: rel_i = 1 if relevant else 0.

        NDCG@K = DCG@K / IDCG@K
          DCG@K  = Σ rel_i / log₂(i + 2)   for i in 0..K-1 (0-indexed rank)
          IDCG@K = Σ 1    / log₂(i + 2)   for i in 0..min(K, R)-1

        Returns None when there is no ground-truth signal.

        Args:
            retrieval_trace: List of dicts sorted by rank (asc).  Each item
                             must have ``rank`` (int, 1-indexed) and optionally
                             ``is_relevant`` (bool).
        """
        scored = [t for t in retrieval_trace if "is_relevant" in t]
        if not scored:
            return None
        # Sort by rank ascending
        ranked = sorted(scored, key=lambda t: t.get("rank", 9999))
        dcg = sum(
            (1.0 if t.get("is_relevant") else 0.0) / math.log2(i + 2)
            for i, t in enumerate(ranked)
        )
        total_rel = sum(1 for t in ranked if t.get("is_relevant"))
        if total_rel == 0:
            return 0.0
        idcg = sum(1.0 / math.log2(i + 2) for i in range(total_rel))
        return dcg / idcg if idcg > 0 else 0.0

    @classmethod
    def compute_mrr(cls, retrieval_trace: List[Dict]) -> Optional[float]:
        """
        Mean Reciprocal Rank (MRR) — position of the first relevant result.

        MRR = 1 / rank_of_first_relevant_item.
        Returns 0.0 if no relevant item was retrieved.
        Returns None when there is no ground-truth signal.

        Args:
            retrieval_trace: List of dicts with ``rank`` (int, 1-indexed) and
                             optionally ``is_relevant`` (bool).
        """
        scored = [t for t in retrieval_trace if "is_relevant" in t]
        if not scored:
            return None
        ranked = sorted(scored, key=lambda t: t.get("rank", 9999))
        for item in ranked:
            if item.get("is_relevant"):
                rank = item.get("rank", 9999)
                return 1.0 / rank if rank > 0 else 0.0
        return 0.0
