"""V3 Diagnoser service.

Goal: produce a stable, cheap, JSON-structured diagnosis that drives routing.

This is intentionally heuristic-first (fast). You can later swap in a small
classifier/LLM without changing the contract.
"""

from __future__ import annotations

import re
from typing import Optional

from api.models.v3_schemas import DiagnosisV3, SuspectedError, V3PipelineContext


_VI_CHARS_RE = re.compile(r"[ăâđêôơưáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]", re.IGNORECASE)


class DiagnoserV3:
    async def diagnose(self, text: str, ctx: V3PipelineContext) -> DiagnosisV3:
        normalized = (text or "").strip()
        lower = normalized.lower()

        need_vietnamese = bool(_VI_CHARS_RE.search(lower)) or ("tiếng việt" in lower) or ("vietnamese" in lower)

        intent: DiagnosisV3.model_fields["intent"].annotation  # type: ignore[attr-defined]
        skill: DiagnosisV3.model_fields["skill"].annotation  # type: ignore[attr-defined]

        if any(k in lower for k in ["explain", "why", "what is", "rule", "tại sao", "giải thích"]):
            intent = "explain_rule"
            skill = "grammar"
        elif any(k in lower for k in ["translate", "dịch", "meaning", "nghĩa"]):
            intent = "translate"
            skill = "vocabulary"
        elif any(k in lower for k in ["practice", "bài tập", "luyện", "exercise"]):
            intent = "practice"
            skill = "mixed"
        else:
            intent = "fix_grammar"
            skill = "grammar"

        suspected_errors = []
        root_causes = []

        # Very small starter patterns
        if re.search(r"\bI\s+goes\b", normalized, re.IGNORECASE):
            suspected_errors.append(SuspectedError(type="subject_verb_agreement", span="I goes"))
            root_causes.append("concept:grammar.subject_verb_agreement")

        confidence = 0.55
        next_best_action = "answer"
        if not normalized:
            confidence = 0.2
            next_best_action = "ask_clarify"
        elif len(normalized) < 4:
            confidence = 0.35
            next_best_action = "ask_clarify"
        elif suspected_errors:
            confidence = 0.75
        elif "?" in normalized:
            confidence = 0.6
        else:
            confidence = 0.5

        if confidence < 0.45:
            next_best_action = "ask_clarify"

        user_problem = "User wants help improving English." if not suspected_errors else "User likely has a grammar error to fix."

        return DiagnosisV3(
            intent=intent,
            skill=skill,
            user_problem=user_problem,
            suspected_errors=suspected_errors,
            root_cause_candidates=root_causes,
            need_vietnamese=need_vietnamese,
            confidence=confidence,
            next_best_action=next_best_action,
        )
