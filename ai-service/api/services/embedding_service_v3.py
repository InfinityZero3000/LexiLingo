"""Embedding service for V3 retrieval.

Uses Sentence-Transformers to encode text into embeddings.
"""

from __future__ import annotations

import logging
from typing import List

import numpy as np
from sentence_transformers import SentenceTransformer

from api.core.config import settings

logger = logging.getLogger(__name__)


class EmbeddingServiceV3:
    def __init__(self) -> None:
        self._model = None
        self._model_name = getattr(settings, "EMBEDDING_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
        self._device = getattr(settings, "EMBEDDING_DEVICE", "cpu")

    def _load_model(self) -> SentenceTransformer:
        if self._model is None:
            logger.info(f"Loading embedding model: {self._model_name} on {self._device}")
            self._model = SentenceTransformer(self._model_name, device=self._device)
        return self._model

    def embed_texts(self, texts: List[str]) -> np.ndarray:
        model = self._load_model()
        embeddings = model.encode(texts, normalize_embeddings=True)
        return np.asarray(embeddings)

    def embed_text(self, text: str) -> np.ndarray:
        return self.embed_texts([text])[0]
