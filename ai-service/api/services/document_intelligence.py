"""
Document Intelligence Service (L2 Ultimate)
Supports Local Docs + Web Scraping + Automatic Web Search.
Tiered logic: L0/L1 (Fast) -> L2 Local (Moderate) -> L2 Search (Deep).
"""

import asyncio
import hashlib
import logging
import os
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx
import numpy as np

from api.services.embedding_service_v3 import EmbeddingServiceV3

logger = logging.getLogger(__name__)

DEFAULT_DOCS_PATH = Path(__file__).resolve().parents[2] / "data" / "external_docs"
MIN_CHUNK_CHARS = 40
WEB_SOURCE = "Web Search"

LOCAL_MIN_SCORE = float(os.getenv("DOC_INTEL_MIN_SCORE", "0.70"))
# Web results are realtime answers ("today", "latest"): serving them days later is wrong.
WEB_TTL_SECONDS = float(os.getenv("DOC_INTEL_WEB_TTL_SECONDS", "1800"))
WEB_MAX_CHUNKS = int(os.getenv("DOC_INTEL_WEB_MAX_CHUNKS", "200"))


class DocumentIntelligenceService:
    def __init__(self, docs_path: Optional[str] = None):
        self.embedder = EmbeddingServiceV3()
        self.external_docs_path = str(docs_path or DEFAULT_DOCS_PATH)
        self.knowledge_index: List[Dict[str, Any]] = []
        self._by_id: Dict[str, Dict[str, Any]] = {}
        self._warned_no_key = False
        self._warned_dim = False
        # Cấu hình API Search (Ví dụ: Tavily - rất phổ biến cho AI RAG)
        self.search_api_key = os.getenv("TAVILY_API_KEY", "")
        self.search_depth = os.getenv("TAVILY_SEARCH_DEPTH", "fast").strip().lower() or "fast"
        self._load_local_docs()

    def _load_local_docs(self) -> None:
        """Nạp tài liệu local làm nền tảng; một file hỏng không làm hỏng cả service."""
        if not os.path.isdir(self.external_docs_path):
            logger.warning("[L2_Local] Docs dir missing: %s", self.external_docs_path)
            return
        for file in sorted(os.listdir(self.external_docs_path)):
            if not file.endswith((".md", ".txt")):
                continue
            try:
                with open(os.path.join(self.external_docs_path, file), "r", encoding="utf-8") as f:
                    self._process_text(f.read(), file)
            except Exception as e:
                logger.warning("[L2_Local] Skipped %s: %s", file, e)
        logger.info("[L2_Local] Indexed %d chunks", len(self.knowledge_index))

    def _new_chunks(self, content: str, ephemeral: bool) -> List[Tuple[str, str]]:
        """Chunk chưa có trong index; chunk web đã có thì được làm tươi lại TTL."""
        fresh: List[Tuple[str, str]] = []
        seen = set()
        now = time.monotonic()
        for chunk in content.split("\n\n"):
            text = chunk.strip()
            if len(text) < MIN_CHUNK_CHARS:
                continue
            chunk_id = hashlib.md5(text.encode()).hexdigest()
            existing = self._by_id.get(chunk_id)
            if existing is not None:
                if ephemeral and existing["ephemeral"]:
                    existing["created_at"] = now
                continue
            if chunk_id in seen:
                continue
            seen.add(chunk_id)
            fresh.append((chunk_id, text))
        return fresh

    def _add_chunks(
        self,
        fresh: List[Tuple[str, str]],
        vectors: Any,
        source: str,
        ephemeral: bool,
    ) -> None:
        now = time.monotonic()
        for (chunk_id, text), vec in zip(fresh, vectors):
            if chunk_id in self._by_id:
                continue
            item = {
                "id": chunk_id,
                "content": text,
                "embedding": np.asarray(vec),
                "source": source,
                "hit_count": 0,
                "created_at": now,
                "ephemeral": ephemeral,
            }
            self.knowledge_index.append(item)
            self._by_id[chunk_id] = item

    def _process_text(self, content: str, source: str, ephemeral: bool = False) -> None:
        """Chuyển văn bản thô thành các chunk đã embed theo batch, tránh trùng lặp."""
        fresh = self._new_chunks(content, ephemeral)
        if fresh:
            vectors = self.embedder.embed_texts([text for _, text in fresh])
            self._add_chunks(fresh, vectors, source, ephemeral)

    async def _process_text_async(self, content: str, source: str, ephemeral: bool = False) -> None:
        fresh = self._new_chunks(content, ephemeral)
        if fresh:
            vectors = await asyncio.to_thread(
                self.embedder.embed_texts, [text for _, text in fresh]
            )
            self._add_chunks(fresh, vectors, source, ephemeral)

    def _evict_web(self) -> None:
        """Bỏ chunk web quá hạn rồi cắt phần vượt trần; chunk local không bao giờ bị bỏ."""
        now = time.monotonic()
        web = [i for i in self.knowledge_index if i["ephemeral"]]
        drop = {i["id"] for i in web if now - i["created_at"] > WEB_TTL_SECONDS}
        live = sorted((i for i in web if i["id"] not in drop), key=lambda i: i["created_at"])
        drop.update(i["id"] for i in live[: max(0, len(live) - WEB_MAX_CHUNKS)])
        if not drop:
            return
        self.knowledge_index = [i for i in self.knowledge_index if i["id"] not in drop]
        for chunk_id in drop:
            self._by_id.pop(chunk_id, None)

    async def _search_tavily(self, query: str) -> List[Dict[str, str]]:
        """Thực hiện tìm kiếm web qua API chuyên dụng; trả về nội dung kèm URL nguồn."""
        if not self.search_api_key:
            log = logger.debug if self._warned_no_key else logger.warning
            log("[L2_Search] No TAVILY_API_KEY found. Auto-search disabled.")
            self._warned_no_key = True
            return []

        allowed_depths = {"ultra-fast", "fast", "basic", "advanced"}
        depth = self.search_depth if self.search_depth in allowed_depths else "fast"

        logger.info(f"[L2_Search] Searching the web for: {query}")
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.post(
                    "https://api.tavily.com/search",
                    json={
                        "api_key": self.search_api_key,
                        "query": query,
                        "search_depth": depth,
                        "max_results": 3
                    }
                )
                if response.status_code == 200:
                    results = response.json().get("results", [])
                    return [
                        {"content": r["content"], "url": r.get("url") or ""}
                        for r in results
                        if len(r.get("content") or "") > 100
                    ]
                logger.warning(
                    "[L2_Search] Tavily returned status %s: %s",
                    response.status_code,
                    response.text[:300],
                )
        except Exception as e:
            logger.error(f"[L2_Search] Search failed: {e}")
        return []

    async def query_l2(self, query: str, top_k: int = 3) -> List[Dict[str, Any]]:
        """Truy xuất tầng L2: tìm local trước, chỉ lên Web khi không có kết quả đủ tốt."""
        self._evict_web()
        query_vec = await asyncio.to_thread(self.embedder.embed_text, query)

        hits = self._rank(query_vec, top_k)
        if hits:
            return hits

        logger.info(f"[L2_Auto] No local hit >= {LOCAL_MIN_SCORE:.2f}. Triggering Web Search...")
        results = await self._search_tavily(query)
        if not results:
            return []

        for r in results:
            await self._process_text_async(r["content"], r["url"] or WEB_SOURCE, ephemeral=True)
        self._evict_web()

        hits = self._rank(query_vec, top_k)
        if hits:
            return hits
        # Fallback an toàn: vẫn trả context web để không mất dữ liệu realtime
        return [
            {
                "content": r["content"],
                "score": 0.55,
                "id": hashlib.md5(r["content"].encode()).hexdigest(),
                "source": r["url"] or WEB_SOURCE,
            }
            for r in results[:top_k]
        ]

    def _rank(self, query_vec: np.ndarray, top_k: int) -> List[Dict[str, Any]]:
        """Top-k chunk có cosine >= ngưỡng; chỉ chunk được trả về mới tăng hit_count."""
        scored = []
        skipped = 0
        for item in self.knowledge_index:
            # ponytail: chunk embed bằng backend khác chiều bị bỏ qua, không re-embed
            if item["embedding"].shape != query_vec.shape:
                skipped += 1
                continue
            score = float(np.dot(query_vec, item["embedding"]))
            if score >= LOCAL_MIN_SCORE:
                scored.append((score, item))

        if skipped and not self._warned_dim:
            self._warned_dim = True
            logger.warning(
                "[L2_Local] %d chunks skipped: embedding dim differs from query (%s). "
                "The embedder backend changed since indexing.",
                skipped, query_vec.shape,
            )

        scored.sort(key=lambda pair: pair[0], reverse=True)
        top = scored[:top_k]
        for _, item in top:
            item["hit_count"] += 1
        return [
            {"content": i["content"], "score": s, "id": i["id"], "source": i["source"]}
            for s, i in top
        ]

    def _get_top_matches(self, query: str, top_k: int) -> List[Dict[str, Any]]:
        """Tìm các KV khớp nhất trong index hiện tại."""
        if not self.knowledge_index:
            return []
        return self._rank(self.embedder.embed_text(query), top_k)

    def should_promote_to_cache(self, chunk_id: str) -> bool:
        """Cơ chế thăng hạng: Nếu thông tin được hỏi nhiều, lưu vào L1 (Redis)."""
        item = self._by_id.get(chunk_id)
        # Dữ liệu web/external nếu hit >= 3 lần sẽ thăng hạng lên L1
        return item is not None and item["hit_count"] >= 3

# Singleton
_doc_intel_service = None
def get_doc_intel_service():
    global _doc_intel_service
    if _doc_intel_service is None:
        _doc_intel_service = DocumentIntelligenceService()
    return _doc_intel_service
