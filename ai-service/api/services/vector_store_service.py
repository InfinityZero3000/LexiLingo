"""
Vector Store Service

Semantic vector search for concepts using sentence embeddings.
Supports hybrid search (keyword + semantic).
"""

import logging
from typing import Any, Dict, List, Optional
import hashlib

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


# ============================================================
# MODELS
# ============================================================


class ConceptEmbedding(BaseModel):
    """Concept with its vector embedding."""
    concept_id: str
    title: str
    category: str
    embedding: List[float] = Field(default_factory=list)
    text: str = ""  # Text used to generate embedding


class SemanticMatch(BaseModel):
    """Result of semantic search."""
    concept_id: str
    title: str
    category: str
    score: float  # Cosine similarity 0-1
    match_type: str = "semantic"  # semantic, keyword, hybrid


# ============================================================
# VECTOR STORE SERVICE
# ============================================================


class VectorStoreService:
    """
    Vector store for semantic concept matching.

    Uses sentence embeddings for semantic search.
    Falls back to keyword matching when embeddings unavailable.
    """

    def __init__(self):
        self._embeddings_cache: Dict[str, List[float]] = {}
        self._model = None
        self._model_loaded = False

    def _get_model(self):
        """Lazy load embedding model."""
        if not self._model_loaded:
            try:
                from sentence_transformers import SentenceTransformer
                # Use a lightweight multilingual model
                self._model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
                self._model_loaded = True
                logger.info("Loaded sentence transformer model")
            except ImportError:
                logger.warning("sentence-transformers not installed, using fallback")
                self._model = None
                self._model_loaded = True
            except Exception as e:
                logger.warning(f"Failed to load model: {e}")
                self._model = None
                self._model_loaded = True
        return self._model

    def generate_embedding(self, text: str) -> List[float]:
        """
        Generate embedding for text.

        Args:
            text: Text to embed

        Returns:
            Embedding vector (384 dimensions for MiniLM)
        """
        # Check cache first
        cache_key = hashlib.md5(text.encode()).hexdigest()
        if cache_key in self._embeddings_cache:
            return self._embeddings_cache[cache_key]

        model = self._get_model()
        if model is None:
            # Fallback: simple hash-based pseudo-embedding
            return self._fallback_embedding(text)

        try:
            embedding = model.encode(text).tolist()
            self._embeddings_cache[cache_key] = embedding
            return embedding
        except Exception as e:
            logger.warning(f"Embedding generation failed: {e}")
            return self._fallback_embedding(text)

    def _fallback_embedding(self, text: str) -> List[float]:
        """Generate pseudo-embedding when model unavailable."""
        # Create a deterministic but naive embedding from text
        import math
        text_lower = text.lower()
        dim = 128
        embedding = []
        for i in range(dim):
            val = 0.0
            for j, char in enumerate(text_lower):
                val += (ord(char) * (i + 1) * (j + 1)) % 1000 / 1000.0
            embedding.append(math.sin(val) * 0.5 + 0.5)
        return embedding

    def cosine_similarity(
        self,
        vec1: List[float],
        vec2: List[float],
    ) -> float:
        """Calculate cosine similarity between two vectors."""
        if len(vec1) != len(vec2) or len(vec1) == 0:
            return 0.0

        import math
        dot_product = sum(a * b for a, b in zip(vec1, vec2))
        norm1 = math.sqrt(sum(a * a for a in vec1))
        norm2 = math.sqrt(sum(b * b for b in vec2))

        if norm1 == 0 or norm2 == 0:
            return 0.0

        return dot_product / (norm1 * norm2)

    async def semantic_search(
        self,
        query: str,
        concepts: List[Dict[str, Any]],
        top_k: int = 5,
    ) -> List[SemanticMatch]:
        """
        Search concepts semantically.

        Args:
            query: Search query
            concepts: List of concepts to search
            top_k: Number of results

        Returns:
            Top matching concepts
        """
        if not concepts:
            return []

        query_embedding = self.generate_embedding(query)

        results = []
        for concept in concepts:
            # Generate or retrieve concept embedding
            concept_text = f"{concept.get('title', '')} {concept.get('category', '')}"
            concept_embedding = self.generate_embedding(concept_text)

            score = self.cosine_similarity(query_embedding, concept_embedding)

            results.append(SemanticMatch(
                concept_id=concept.get("concept_id", concept.get("id", "")),
                title=concept.get("title", ""),
                category=concept.get("category", ""),
                score=score,
                match_type="semantic",
            ))

        # Sort by score and return top k
        results.sort(key=lambda x: x.score, reverse=True)
        return results[:top_k]

    async def hybrid_search(
        self,
        query: str,
        concepts: List[Dict[str, Any]],
        top_k: int = 5,
        keyword_weight: float = 0.3,
    ) -> List[SemanticMatch]:
        """
        Hybrid search combining semantic and keyword matching.

        Args:
            query: Search query
            concepts: List of concepts
            top_k: Number of results
            keyword_weight: Weight for keyword matching (0-1)

        Returns:
            Combined ranking of matches
        """
        if not concepts:
            return []

        query_lower = query.lower()
        query_terms = set(query_lower.split())

        # Get semantic scores
        semantic_results = await self.semantic_search(query, concepts, len(concepts))
        semantic_scores = {r.concept_id: r.score for r in semantic_results}

        # Calculate keyword scores
        keyword_scores = {}
        for concept in concepts:
            concept_id = concept.get("concept_id", concept.get("id", ""))
            text = f"{concept.get('title', '')} {concept.get('category', '')}".lower()
            text_terms = set(text.split())

            # Jaccard-like similarity
            overlap = len(query_terms & text_terms)
            total = len(query_terms | text_terms)
            keyword_scores[concept_id] = overlap / total if total > 0 else 0.0

        # Combine scores
        results = []
        for concept in concepts:
            concept_id = concept.get("concept_id", concept.get("id", ""))
            semantic = semantic_scores.get(concept_id, 0.0)
            keyword = keyword_scores.get(concept_id, 0.0)

            combined = (1 - keyword_weight) * semantic + keyword_weight * keyword

            results.append(SemanticMatch(
                concept_id=concept_id,
                title=concept.get("title", ""),
                category=concept.get("category", ""),
                score=combined,
                match_type="hybrid",
            ))

        results.sort(key=lambda x: x.score, reverse=True)
        return results[:top_k]

    async def find_related_concepts(
        self,
        concept: Dict[str, Any],
        all_concepts: List[Dict[str, Any]],
        top_k: int = 5,
    ) -> List[SemanticMatch]:
        """
        Find concepts related to a given concept.

        Args:
            concept: Source concept
            all_concepts: Pool of concepts to search
            top_k: Number of results

        Returns:
            Related concepts
        """
        concept_text = f"{concept.get('title', '')} {concept.get('category', '')}"
        
        # Filter out self
        concept_id = concept.get("concept_id", concept.get("id", ""))
        filtered = [c for c in all_concepts 
                    if c.get("concept_id", c.get("id", "")) != concept_id]

        return await self.semantic_search(concept_text, filtered, top_k)


# ============================================================
# SINGLETON
# ============================================================

_service: Optional[VectorStoreService] = None


def get_vector_store_service() -> VectorStoreService:
    """Get or create VectorStoreService singleton."""
    global _service
    if _service is None:
        _service = VectorStoreService()
    return _service
