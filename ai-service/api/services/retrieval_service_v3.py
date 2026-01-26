"""V3 Retrieval service (skeleton).

Hybrid retrieval design:
1) Vector retrieval (semantic match)
2) KG expansion (1-2 hops) + re-rank

This skeleton returns minimal structured output so callers can be wired now.
"""

from __future__ import annotations

from typing import Dict, List, Tuple

import numpy as np

from api.models.v3_schemas import ExamplePair, RetrievalBundleV3, V3PipelineContext, VectorHit
from api.services.embedding_service_v3 import EmbeddingServiceV3
from api.services.kg_service_v3 import KnowledgeGraphServiceV3


class RetrievalServiceV3:
    def __init__(self, kg: KnowledgeGraphServiceV3):
        self.kg = kg
        self.embedder = EmbeddingServiceV3()
        self._concept_cache: Dict[str, Dict[str, str]] = {}
        self._concept_embeddings: Dict[str, np.ndarray] = {}

    async def retrieve(self, query: str, seed_concepts: list[str], ctx: V3PipelineContext) -> RetrievalBundleV3:
        kg_hits = await self.kg.expand(seed_nodes=seed_concepts, hops=1)

        vector_hits = self._semantic_retrieval(query)

        examples = []
        if "concept:grammar.subject_verb_agreement" in seed_concepts:
            examples.append(
                ExamplePair(
                    good="I go to school every day.",
                    bad="I goes to school every day.",
                    why="With 'I', use the base verb form: 'go'.",
                )
            )

        return RetrievalBundleV3(
            query=query,
            vector_hits=vector_hits,
            kg_hits=kg_hits,
            examples=examples,
        )

    def _semantic_retrieval(self, query: str, limit: int = 5) -> List[VectorHit]:
        """Embedding-based semantic retrieval over KG concepts."""
        normalized = (query or "").strip()
        if not normalized:
            return []

        concepts = self.kg.get_concepts()
        if not concepts:
            return []

        self._refresh_concept_cache(concepts)

        query_vec = self.embedder.embed_text(normalized)

        scored: List[Tuple[str, float, str]] = []
        for concept_id, meta in self._concept_cache.items():
            concept_vec = self._concept_embeddings.get(concept_id)
            if concept_vec is None:
                continue
            score = float(np.dot(query_vec, concept_vec))
            snippet = meta.get("title", concept_id)
            scored.append((concept_id, score, snippet))

        scored.sort(key=lambda x: x[1], reverse=True)
        return [VectorHit(id=c_id, score=max(0.0, min(1.0, score)), snippet=snippet) for c_id, score, snippet in scored[:limit]]

    def _refresh_concept_cache(self, concepts: Dict[str, Dict[str, str]]) -> None:
        if concepts == self._concept_cache:
            return

        self._concept_cache = concepts
        texts = []
        ids = []
        for concept_id, meta in concepts.items():
            text = f"{meta.get('title', concept_id)}. {meta.get('keywords', '')}".strip()
            ids.append(concept_id)
            texts.append(text)

        embeddings = self.embedder.embed_texts(texts)
        self._concept_embeddings = {cid: emb for cid, emb in zip(ids, embeddings)}
