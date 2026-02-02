"""V3 Retrieval service with Graph Analytics.

Hybrid retrieval design:
1) Vector retrieval (semantic match)
2) KG expansion (1-2 hops)
3) Centrality-based ranking (structural importance)
4) Community-aware pruning (output diversity + memory optimization)

Enhanced with GraphCAG principles for optimal LLM context.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import numpy as np

from api.models.v3_schemas import (
    ExamplePair,
    RetrievalBundleV3,
    V3PipelineContext,
    VectorHit,
)
from api.services.embedding_service_v3 import EmbeddingServiceV3
from api.services.graph_analytics import GraphAnalyticsService, get_graph_analytics
from api.services.kg_service_v3 import KnowledgeGraphServiceV3


logger = logging.getLogger(__name__)


@dataclass
class RetrievalConfig:
    """Configuration for retrieval behavior."""
    # Vector retrieval settings
    vector_top_k: int = 10
    min_similarity: float = 0.3
    
    # Centrality settings
    use_centrality_ranking: bool = True
    centrality_boost: float = 0.3
    min_centrality: float = 0.05
    
    # Community settings
    use_community_detection: bool = True
    community_match_boost: float = 0.2
    prefer_community_diversity: bool = True
    
    # Output pruning
    max_output_concepts: int = 5
    
    # Memory optimization
    enable_pruning: bool = True


class RetrievalServiceV3:
    """
    Enhanced retrieval service with Graph Analytics.
    
    Key optimizations:
    - Centrality ranking: Prioritize structurally important concepts
    - Community detection: Group related concepts, ensure diversity
    - Smart pruning: Output only necessary information
    """
    
    def __init__(
        self,
        kg: KnowledgeGraphServiceV3,
        config: Optional[RetrievalConfig] = None,
    ):
        self.kg = kg
        self.config = config or RetrievalConfig()
        self.embedder = EmbeddingServiceV3()
        self.analytics = get_graph_analytics(kg)
        
        # Cache for embeddings
        self._concept_cache: Dict[str, Dict[str, str]] = {}
        self._concept_embeddings: Dict[str, np.ndarray] = {}
        
        # Pre-compute analytics on init
        self._precompute_analytics()
    
    def _precompute_analytics(self) -> None:
        """Pre-compute graph analytics for faster retrieval."""
        try:
            self.analytics.compute_centrality()
            logger.info("Graph analytics pre-computed successfully")
        except Exception as e:
            logger.warning(f"Failed to pre-compute analytics: {e}")
    
    async def retrieve(
        self,
        query: str,
        seed_concepts: List[str],
        ctx: V3PipelineContext,
    ) -> RetrievalBundleV3:
        """
        Retrieve relevant concepts using hybrid approach.
        
        Steps:
        1. Semantic vector retrieval
        2. KG expansion from seeds
        3. Centrality-based ranking
        4. Community-aware pruning
        
        Args:
            query: User query text
            seed_concepts: Initial concepts from diagnosis
            ctx: Pipeline context with learner info
            
        Returns:
            RetrievalBundleV3 with optimized concept set
        """
        # Step 1: KG expansion
        kg_hits = await self.kg.expand(seed_nodes=seed_concepts, hops=1)
        
        # Step 2: Semantic retrieval
        all_vector_hits = self._semantic_retrieval(
            query,
            limit=self.config.vector_top_k,
        )
        
        # Step 3: Apply centrality ranking if enabled
        if self.config.use_centrality_ranking:
            all_vector_hits = self._rank_by_centrality(
                all_vector_hits,
                seed_concepts,
            )
        
        # Step 4: Apply community-aware pruning if enabled
        if self.config.enable_pruning:
            vector_hits = self._prune_with_diversity(
                all_vector_hits,
                max_output=self.config.max_output_concepts,
            )
            
            # Log memory savings
            if all_vector_hits:
                pruned_count = len(all_vector_hits) - len(vector_hits)
                if pruned_count > 0:
                    logger.debug(
                        f"Pruned {pruned_count} concepts, "
                        f"saved ~{pruned_count * 0.5:.1f}KB context"
                    )
        else:
            vector_hits = all_vector_hits[:self.config.max_output_concepts]
        
        # Build examples for specific concepts
        examples = self._build_examples(seed_concepts, kg_hits)
        
        return RetrievalBundleV3(
            query=query,
            vector_hits=vector_hits,
            kg_hits=kg_hits,
            examples=examples,
        )
    
    def _semantic_retrieval(
        self,
        query: str,
        limit: int = 10,
    ) -> List[VectorHit]:
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
                
            # Cosine similarity
            similarity = float(np.dot(query_vec, concept_vec))
            
            # Filter by minimum similarity
            if similarity < self.config.min_similarity:
                continue
                
            snippet = meta.get("title", concept_id)
            scored.append((concept_id, similarity, snippet))

        scored.sort(key=lambda x: x[1], reverse=True)
        
        return [
            VectorHit(id=c_id, score=max(0.0, min(1.0, score)), snippet=snippet)
            for c_id, score, snippet in scored[:limit]
        ]
    
    def _rank_by_centrality(
        self,
        hits: List[VectorHit],
        seed_concepts: List[str],
    ) -> List[VectorHit]:
        """
        Re-rank hits by combining semantic score with centrality.
        
        Combined score = semantic_score + (centrality_boost * centrality)
        """
        if not hits:
            return hits
        
        # Get community of seed concepts for bonus
        query_community: Optional[int] = None
        if seed_concepts and self.config.use_community_detection:
            query_community = self.analytics.get_concept_community(seed_concepts[0])
        
        # Rank with centrality
        ranked_ids = self.analytics.rank_concepts(
            candidates=[h.id for h in hits],
            boost_centrality=self.config.centrality_boost,
            boost_community_match=self.config.community_match_boost,
            query_community=query_community,
        )
        
        # Create ID -> analytics_score mapping
        analytics_scores = {cid: score for cid, score in ranked_ids}
        
        # Combine with semantic score
        reranked: List[Tuple[VectorHit, float]] = []
        for hit in hits:
            semantic = hit.score
            analytics = analytics_scores.get(hit.id, 1.0)
            combined = semantic * 0.7 + analytics * 0.3  # 70% semantic, 30% analytics
            reranked.append((hit, combined))
        
        # Sort by combined score
        reranked.sort(key=lambda x: x[1], reverse=True)
        
        # Update scores and return
        result = []
        for hit, combined in reranked:
            result.append(VectorHit(
                id=hit.id,
                score=round(combined, 4),
                snippet=hit.snippet,
            ))
        
        return result
    
    def _prune_with_diversity(
        self,
        hits: List[VectorHit],
        max_output: int = 5,
    ) -> List[VectorHit]:
        """
        Prune hits with community diversity.
        
        Ensures we don't return too many concepts from the same community,
        providing more diverse and useful context to LLM.
        """
        if len(hits) <= max_output:
            return hits
        
        if not self.config.use_community_detection:
            return hits[:max_output]
        
        community_map = self.analytics._detect_communities()
        
        selected: List[VectorHit] = []
        communities_used: Dict[int, int] = {}  # community_id -> count
        max_per_community = max(1, max_output // 2)  # At most half from same community
        
        # First pass: prioritize diversity
        for hit in hits:
            if len(selected) >= max_output:
                break
                
            comm = community_map.get(hit.id, -1)
            comm_count = communities_used.get(comm, 0)
            
            if comm_count < max_per_community:
                selected.append(hit)
                communities_used[comm] = comm_count + 1
        
        # Second pass: fill remaining slots if needed
        for hit in hits:
            if len(selected) >= max_output:
                break
            if hit not in selected:
                selected.append(hit)
        
        return selected
    
    def _build_examples(
        self,
        seed_concepts: List[str],
        kg_hits,
    ) -> List[ExamplePair]:
        """Build example pairs for specific grammar concepts."""
        examples = []
        
        # Subject-verb agreement examples
        if "concept:grammar.subject_verb_agreement" in seed_concepts:
            examples.append(
                ExamplePair(
                    good="I go to school every day.",
                    bad="I goes to school every day.",
                    why="With 'I', use the base verb form: 'go'.",
                )
            )
        
        # Third-person -s examples
        if "concept:grammar.third_person_s" in seed_concepts:
            examples.append(
                ExamplePair(
                    good="She goes to work by bus.",
                    bad="She go to work by bus.",
                    why="With 'she/he/it', add -s to the verb: 'goes'.",
                )
            )
        
        # Past simple examples
        if "concept:grammar.past_simple" in seed_concepts:
            examples.append(
                ExamplePair(
                    good="I went to the store yesterday.",
                    bad="I go to the store yesterday.",
                    why="Use past tense with 'yesterday': 'went' (irregular past of 'go').",
                )
            )
        
        # Articles examples
        if "concept:grammar.articles_a_an" in seed_concepts:
            examples.append(
                ExamplePair(
                    good="I saw an elephant at the zoo.",
                    bad="I saw elephant at zoo.",
                    why="Use 'an' before vowel sounds and 'the' for specific nouns.",
                )
            )
        
        return examples
    
    def _refresh_concept_cache(self, concepts: Dict[str, Dict[str, str]]) -> None:
        """Refresh cached concept embeddings."""
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
    
    def get_analytics_summary(self) -> Dict:
        """Get summary of graph analytics for debugging."""
        importance = self.analytics.compute_centrality()
        communities = self.analytics.get_communities()
        
        # Top 5 most important concepts
        top_concepts = sorted(
            importance.values(),
            key=lambda x: x.combined_score,
            reverse=True,
        )[:5]
        
        return {
            "total_concepts": len(importance),
            "total_communities": len(communities),
            "top_concepts": [
                {
                    "id": c.concept_id,
                    "title": c.title,
                    "score": round(c.combined_score, 4),
                    "community": c.community_id,
                }
                for c in top_concepts
            ],
            "communities": [
                {
                    "id": c.community_id,
                    "name": c.name,
                    "size": len(c.concepts),
                    "central": c.central_concept,
                }
                for c in communities
            ],
        }
