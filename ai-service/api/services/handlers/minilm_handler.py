"""
MiniLM Handler - Sentence Embeddings for Semantic Search

Manages sentence-transformers/all-MiniLM-L6-v2 for:
- Embedding user queries
- Semantic similarity search against KG concept descriptions
- Retrieval augmentation in the GraphCAG pipeline
"""

import asyncio
import logging
import os
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Union

import numpy as np

logger = logging.getLogger(__name__)


@dataclass
class MiniLMConfig:
    """Configuration for MiniLM embedding model."""

    model_id: str = "sentence-transformers/all-MiniLM-L6-v2"
    model_path: Optional[str] = None  # Local path override
    device: str = "cpu"  # cpu or cuda  — 22 MB model, CPU is fine
    max_seq_length: int = 256
    normalize: bool = True


class MiniLMHandler:
    """
    Handler for all-MiniLM-L6-v2 sentence embeddings.

    Uses sentence-transformers for encoding text into 384-dim vectors.
    Extremely lightweight (~22 MB) so it can stay loaded.
    """

    EMBEDDING_DIM = 384

    def __init__(self, config: Optional[MiniLMConfig] = None):
        self.config = config or MiniLMConfig()
        self.model = None  # SentenceTransformer instance
        self._loaded = False
        self._loading = False
        self._lock = asyncio.Lock()

    # ── Properties ───────────────────────────────────────────────────────
    @property
    def is_loaded(self) -> bool:
        return self._loaded

    @property
    def memory_usage_mb(self) -> float:
        return 25.0 if self._loaded else 0.0

    # ── Lifecycle ────────────────────────────────────────────────────────
    async def load(self) -> None:
        """Load the SentenceTransformer model."""
        async with self._lock:
            if self._loaded:
                return
            self._loading = True
            try:
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(None, self._load_sync)
                self._loaded = True
                logger.info(
                    "✅ MiniLM loaded (%s, device=%s)",
                    self.config.model_id,
                    self.config.device,
                )
            except Exception as e:
                logger.error("Failed to load MiniLM: %s", e)
                raise
            finally:
                self._loading = False

    def _load_sync(self) -> None:
        from sentence_transformers import SentenceTransformer

        path = self.config.model_path or self.config.model_id
        self.model = SentenceTransformer(path, device=self.config.device)
        self.model.max_seq_length = self.config.max_seq_length

    async def unload(self) -> None:
        async with self._lock:
            self.model = None
            self._loaded = False
            logger.info("MiniLM unloaded")

    # ── Core operations ──────────────────────────────────────────────────
    async def encode(
        self,
        texts: Union[str, List[str]],
        normalize: Optional[bool] = None,
    ) -> np.ndarray:
        """
        Encode text(s) into embedding vectors.

        Args:
            texts: Single string or list of strings.
            normalize: Override config normalize setting.

        Returns:
            numpy array of shape (n_texts, 384).
        """
        if not self._loaded:
            await self.load()

        if isinstance(texts, str):
            texts = [texts]

        do_normalize = normalize if normalize is not None else self.config.normalize

        loop = asyncio.get_event_loop()
        embeddings = await loop.run_in_executor(
            None,
            lambda: self.model.encode(
                texts,
                normalize_embeddings=do_normalize,
                show_progress_bar=False,
            ),
        )
        return embeddings

    async def similarity(
        self, query: str, candidates: List[str]
    ) -> List[Dict[str, Any]]:
        """
        Compute cosine similarity between a query and candidate texts.

        Returns:
            List of {"text": str, "score": float} sorted by descending score.
        """
        if not candidates:
            return []

        all_texts = [query] + candidates
        embeddings = await self.encode(all_texts, normalize=True)

        query_vec = embeddings[0]
        candidate_vecs = embeddings[1:]

        scores = candidate_vecs @ query_vec  # cos-sim (already normalized)

        results = [
            {"text": candidates[i], "score": float(scores[i])}
            for i in range(len(candidates))
        ]
        results.sort(key=lambda r: r["score"], reverse=True)
        return results

    # ── Gateway interface (invoke) ───────────────────────────────────────
    async def invoke(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Gateway-compatible invoke interface.

        Supported tasks:
        - encode: {"texts": [...]} → {"embeddings": [...]}
        - similarity: {"query": "...", "candidates": [...]} → {"results": [...]}
        """
        task = params.get("task", "encode")

        try:
            if task in ("encode", "embed"):
                texts = params.get("texts") or params.get("text", "")
                embeddings = await self.encode(texts)
                return {
                    "success": True,
                    "data": {
                        "embeddings": embeddings.tolist(),
                        "dim": self.EMBEDDING_DIM,
                    },
                }

            elif task in ("similarity", "semantic_search"):
                query = params.get("query", "")
                candidates = params.get("candidates", [])
                results = await self.similarity(query, candidates)
                return {
                    "success": True,
                    "data": {"results": results},
                }

            else:
                return {"success": False, "error": f"Unknown task: {task}"}

        except Exception as e:
            logger.error("MiniLM invoke error: %s", e)
            return {"success": False, "error": str(e)}
