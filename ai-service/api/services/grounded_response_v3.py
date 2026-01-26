"""Grounded response builder for V3 pipeline.

Forces response content to align with RetrievalBundleV3 evidence.
This is a template-based implementation that can be swapped with LLM later.
"""

from __future__ import annotations

from typing import List

from api.models.v3_schemas import DiagnosisV3, RetrievalBundleV3
from api.services.kg_service_v3 import KnowledgeGraphServiceV3


class GroundedResponseV3:
    def __init__(self, kg: KnowledgeGraphServiceV3):
        self.kg = kg

    def build(self, text: str, diagnosis: DiagnosisV3, retrieval: RetrievalBundleV3) -> str:
        """Build a grounded tutor response using evidence + linked concepts."""
        concept_titles = self._resolve_titles(
            [c.id for c in retrieval.vector_hits][:2] + retrieval.kg_hits.seed_nodes
        )

        lines: List[str] = []
        if diagnosis.suspected_errors:
            err = diagnosis.suspected_errors[0]
            lines.append(f"Mình thấy có thể bạn đang gặp lỗi: {err.type} ({err.span}).")
        else:
            lines.append("Mình đã xem nội dung của bạn.")

        if concept_titles:
            lines.append("Các khái niệm liên quan: " + ", ".join(concept_titles) + ".")

        if retrieval.examples:
            ex = retrieval.examples[0]
            lines.append(f"Ví dụ đúng: {ex.good}")
            lines.append(f"Ví dụ sai: {ex.bad}")
            if ex.why:
                lines.append(f"Giải thích: {ex.why}")

        if diagnosis.intent == "practice":
            lines.append("Bạn muốn luyện thêm phần này chứ? Mình có thể tạo bài tập ngắn ngay.")
        else:
            lines.append("Bạn thử viết lại câu theo gợi ý trên nhé.")

        return "\n".join(lines)

    def _resolve_titles(self, concept_ids: List[str]) -> List[str]:
        concepts = self.kg.get_concepts()
        titles = []
        for cid in concept_ids:
            meta = concepts.get(cid)
            if meta and meta.get("title"):
                titles.append(meta["title"])
        return titles