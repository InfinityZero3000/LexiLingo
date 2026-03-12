"""
EvaluationAgent — centralised scoring and vocabulary estimation for GraphCAG pipeline.

Pure-logic class (no I/O, no framework dependencies).
All methods are @classmethod so no instantiation is needed.
"""

from __future__ import annotations

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
