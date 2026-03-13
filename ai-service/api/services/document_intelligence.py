"""
Document Intelligence Service (L2 Ultimate)
Supports Local Docs + Web Scraping + Automatic Web Search.
Tiered logic: L0/L1 (Fast) -> L2 Local (Moderate) -> L2 Search (Deep).
"""

import os
import hashlib
import logging
import httpx
import re
from typing import List, Dict, Any, Optional
import numpy as np
from api.services.embedding_service_v3 import EmbeddingServiceV3

logger = logging.getLogger(__name__)

class DocumentIntelligenceService:
    def __init__(self):
        self.embedder = EmbeddingServiceV3()
        self.external_docs_path = "data/external_docs"
        self.knowledge_index: List[Dict[str, Any]] = []
        # Cấu hình API Search (Ví dụ: Tavily - rất phổ biến cho AI RAG)
        self.search_api_key = os.getenv("TAVILY_API_KEY", "")
        self._load_local_docs()

    def _load_local_docs(self):
        """Nạp tài liệu local làm nền tảng."""
        if os.path.exists(self.external_docs_path):
            for file in os.listdir(self.external_docs_path):
                if file.endswith((".md", ".txt")):
                    with open(os.path.join(self.external_docs_path, file), "r") as f:
                        self._process_text(f.read(), file)

    def _process_text(self, content: str, source: str):
        """Chuyển đổi văn bản thô thành các cặp KV thông minh, tránh trùng lặp."""
        chunks = content.split("\n\n")
        for chunk in chunks:
            text = chunk.strip()
            if len(text) < 40: continue
            
            chunk_id = hashlib.md5(text.encode()).hexdigest()
            # Kiểm tra xem KV này đã có trong index chưa
            if any(item["id"] == chunk_id for item in self.knowledge_index):
                continue

            embedding = self.embedder.embed_text(text)
            self.knowledge_index.append({
                "id": chunk_id,
                "content": text,
                "embedding": embedding,
                "source": source,
                "hit_count": 0,
                "created_at": os.times().elapsed
            })

    async def _search_tavily(self, query: str) -> List[str]:
        """Thực hiện tìm kiếm web qua API chuyên dụng (Fast & Accurate)."""
        if not self.search_api_key:
            logger.warning("[L2_Search] No TAVILY_API_KEY found. Auto-search disabled.")
            return []

        logger.info(f"[L2_Search] Searching the web for: {query}")
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.post(
                    "https://api.tavily.com/search",
                    json={
                        "api_key": self.search_api_key,
                        "query": query,
                        "search_depth": "smart",
                        "max_results": 3
                    }
                )
                if response.status_code == 200:
                    results = response.json().get("results", [])
                    return [r["content"] for r in results if len(r["content"]) > 100]
        except Exception as e:
            logger.error(f"[L2_Search] Search failed: {e}")
        return []

    async def query_l2(self, query: str, top_k: int = 3) -> List[Dict[str, Any]]:
        """Truy xuất tầng L2 với cơ chế Tự động Tìm kiếm khi tri thức thiếu hụt."""
        
        # 1. Tìm trong tri thức Local L2 hiện có
        local_hits = self._get_top_matches(query, top_k)
        best_score = local_hits[0]["score"] if local_hits else 0

        # 2. Cơ chế Tự động (Quality Gate): Nếu không có kết quả tốt (> 0.65), lên Web tìm
        if best_score < 0.65:
            logger.info(f"[L2_Auto] Low confidence ({best_score:.2f}). Triggering Web Search...")
            web_contents = await self._search_tavily(query)
            
            if web_contents:
                for content in web_contents:
                    self._process_text(content, "Web Search")
                # Tìm lại lần nữa sau khi đã nạp tri thức Web
                local_hits = self._get_top_matches(query, top_k)

        return local_hits

    def _get_top_matches(self, query: str, top_k: int) -> List[Dict[str, Any]]:
        """Tìm các KV khớp nhất trong index hiện tại."""
        if not self.knowledge_index: return []
        
        query_vec = self.embedder.embed_text(query)
        scored_chunks = []

        for item in self.knowledge_index:
            score = np.dot(query_vec, item["embedding"])
            if score > 0.70: # Chỉ lấy KV chuẩn xác cao
                scored_chunks.append({
                    "content": item["content"],
                    "score": score,
                    "id": item["id"],
                    "source": item["source"]
                })
                item["hit_count"] += 1

        scored_chunks.sort(key=lambda x: x["score"], reverse=True)
        return scored_chunks[:top_k]

    def should_promote_to_cache(self, chunk_id: str) -> bool:
        """Cơ chế thăng hạng: Nếu thông tin được hỏi nhiều, lưu vào L1 (Redis)."""
        for item in self.knowledge_index:
            if item["id"] == chunk_id:
                # Dữ liệu web/external nếu hit > 3 lần sẽ thăng hạng lên L1
                return item["hit_count"] >= 3
        return False

# Singleton
_doc_intel_service = None
def get_doc_intel_service():
    global _doc_intel_service
    if _doc_intel_service is None:
        _doc_intel_service = DocumentIntelligenceService()
    return _doc_intel_service
