"""Embedding service for V3 retrieval.

Uses Sentence-Transformers to encode text into embeddings.
"""

from __future__ import annotations

import hashlib
import importlib.metadata
import logging
import os
import re
from typing import Any, List

import numpy as np

from api.core.config import settings

logger = logging.getLogger(__name__)


class EmbeddingServiceV3:
    def __init__(self) -> None:
        self._model = None
        self._fallback_mode = False
        self._fallback_reason: str | None = None
        self._fallback_dim = 384
        self._model_name = getattr(settings, "EMBEDDING_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
        self._device = getattr(settings, "EMBEDDING_DEVICE", "cpu")

    def _should_force_fallback(self) -> tuple[bool, str | None]:
        if os.getenv("V3_FORCE_HASH_EMBEDDINGS", "").strip() in {"1", "true", "yes"}:
            return True, "forced by V3_FORCE_HASH_EMBEDDINGS"

        try:
            numpy_version = importlib.metadata.version("numpy")
            torch_version = importlib.metadata.version("torch")
        except importlib.metadata.PackageNotFoundError:
            return False, None
        except Exception:
            return False, None

        def _major_minor(version: str) -> tuple[int, int]:
            parts = re.findall(r"\d+", version)
            if not parts:
                return (0, 0)
            major = int(parts[0])
            minor = int(parts[1]) if len(parts) > 1 else 0
            return (major, minor)

        np_major, _ = _major_minor(numpy_version)
        torch_major, torch_minor = _major_minor(torch_version)
        if np_major >= 2 and torch_major == 2 and torch_minor < 4:
            return True, f"incompatible torch/numpy combo detected (torch={torch_version}, numpy={numpy_version})"

        return False, None

    def _load_model(self) -> Any:
        if self._model is None and not self._fallback_mode:
            force_fallback, reason = self._should_force_fallback()
            if force_fallback:
                self._fallback_mode = True
                self._fallback_reason = reason
                logger.warning(
                    "Embedding model disabled (%s). Using deterministic hash embeddings.",
                    reason,
                )
                return None
            try:
                from sentence_transformers import SentenceTransformer  # lazy import: not available on all platforms

                logger.info(f"Loading embedding model: {self._model_name} on {self._device}")
                self._model = SentenceTransformer(self._model_name, device=self._device)
            except Exception as exc:  # pragma: no cover - environment-dependent
                self._fallback_mode = True
                self._fallback_reason = str(exc)
                logger.warning(
                    "Embedding model unavailable (%s). Falling back to deterministic hash embeddings.",
                    exc,
                )
        return self._model

    def embed_texts(self, texts: List[str]) -> np.ndarray:
        model = self._load_model()
        if model is None:
            return self._embed_texts_fallback(texts)
        embeddings = model.encode(texts, normalize_embeddings=True)
        return np.asarray(embeddings)

    def embed_text(self, text: str) -> np.ndarray:
        return self.embed_texts([text])[0]

    def _embed_texts_fallback(self, texts: List[str]) -> np.ndarray:
        """Generate lightweight deterministic embeddings without external ML deps."""
        vectors = [self._embed_one_fallback(text) for text in texts]
        return np.asarray(vectors, dtype=np.float32)

    def _embed_one_fallback(self, text: str) -> np.ndarray:
        vec = np.zeros(self._fallback_dim, dtype=np.float32)
        tokens = re.findall(r"\w+", (text or "").lower())
        if not tokens:
            return vec

        for token in tokens:
            digest = hashlib.sha256(token.encode("utf-8")).digest()
            # Use 4 bytes to choose index and one byte for sign/magnitude.
            idx = int.from_bytes(digest[:4], "big") % self._fallback_dim
            sign = -1.0 if (digest[4] & 1) else 1.0
            weight = 0.5 + (digest[5] / 255.0)
            vec[idx] += sign * weight

        norm = float(np.linalg.norm(vec))
        if norm > 0:
            vec /= norm
        return vec
