import asyncio
import hashlib
import re

import numpy as np
import pytest

from api.services import document_intelligence as di

SLANG = (
    "Rizz is a shortened form of charisma. It means the ability to charm other people.\n\n"
    "Delulu is short for delusional. People use it to joke about unrealistic beliefs.\n\n"
    "tiny"
)
WEATHER = "Hanoi weather today is sunny with a high temperature of thirty five degrees celsius " * 2


class FakeEmbedder:
    dim = 64

    def embed_texts(self, texts):
        return np.asarray([self._one(t) for t in texts], dtype=np.float32)

    def embed_text(self, text):
        return self.embed_texts([text])[0]

    def _one(self, text):
        vec = np.zeros(self.dim, dtype=np.float32)
        for tok in re.findall(r"\w+", text.lower()):
            vec[int.from_bytes(hashlib.sha256(tok.encode()).digest()[:4], "big") % self.dim] += 1.0
        norm = np.linalg.norm(vec)
        return vec / norm if norm else vec


@pytest.fixture
def service(tmp_path, monkeypatch):
    (tmp_path / "slang.md").write_text(SLANG + "\n\nXin chào, đây là tài liệu tiếng Việt có dấu đầy đủ.", encoding="utf-8")
    monkeypatch.setattr(di, "EmbeddingServiceV3", FakeEmbedder)
    monkeypatch.setattr(di, "LOCAL_MIN_SCORE", 0.5)
    return di.DocumentIntelligenceService(docs_path=str(tmp_path))


def _stub_web(svc, monkeypatch, results):
    calls = []

    async def fake(query):
        calls.append(query)
        return results

    monkeypatch.setattr(svc, "_search_tavily", fake)
    return calls


def test_loads_utf8_docs_and_drops_tiny_chunks(service):
    texts = [i["content"] for i in service.knowledge_index]
    assert len(texts) == 3
    assert any("tiếng Việt" in t for t in texts)
    assert "tiny" not in texts


def test_duplicate_content_is_not_indexed_twice(service):
    before = len(service.knowledge_index)
    service._process_text(SLANG, "again")
    assert len(service.knowledge_index) == before


def test_local_hit_skips_web_and_counts_only_returned_hits(service, monkeypatch):
    calls = _stub_web(service, monkeypatch, [])
    hits = asyncio.run(service.query_l2("rizz charisma charm other people", top_k=1))
    assert [h["source"] for h in hits] == ["slang.md"]
    assert calls == []
    assert sum(i["hit_count"] for i in service.knowledge_index) == 1
    assert isinstance(hits[0]["score"], float)


def test_dimension_mismatch_is_skipped_not_raised(service, monkeypatch):
    monkeypatch.setattr(service.embedder, "dim", 32)
    _stub_web(service, monkeypatch, [])
    assert asyncio.run(service.query_l2("rizz charisma")) == []


def test_web_fallback_is_used_when_nothing_local_matches(service, monkeypatch):
    calls = _stub_web(service, monkeypatch, [{"content": WEATHER, "url": "https://w.example/hn"}])
    hits = asyncio.run(service.query_l2("Hanoi weather today sunny temperature"))
    assert calls and hits[0]["source"] == "https://w.example/hn"
    again = asyncio.run(service.query_l2("Hanoi weather today sunny temperature"))
    assert len(calls) == 1 and again[0]["id"] == hits[0]["id"]


def test_expired_web_chunk_triggers_fresh_search(service, monkeypatch):
    calls = _stub_web(service, monkeypatch, [{"content": WEATHER, "url": "u"}])
    asyncio.run(service.query_l2("Hanoi weather today sunny temperature"))
    for item in service.knowledge_index:
        if item["ephemeral"]:
            item["created_at"] -= di.WEB_TTL_SECONDS + 1
    asyncio.run(service.query_l2("Hanoi weather today sunny temperature"))
    assert len(calls) == 2


def test_web_chunks_are_capped_and_local_chunks_survive(service, monkeypatch):
    monkeypatch.setattr(di, "WEB_MAX_CHUNKS", 2)
    for n in range(5):
        service._process_text(f"web fact number {n} " * 10, "u", ephemeral=True)
    service._evict_web()
    assert sum(i["ephemeral"] for i in service.knowledge_index) == 2
    assert sum(not i["ephemeral"] for i in service.knowledge_index) == 3
    assert set(service._by_id) == {i["id"] for i in service.knowledge_index}


def test_promotion_needs_three_returned_hits(service, monkeypatch):
    _stub_web(service, monkeypatch, [])
    for _ in range(3):
        hits = asyncio.run(service.query_l2("rizz charisma charm other people", top_k=1))
    assert service.should_promote_to_cache(hits[0]["id"])
    assert not service.should_promote_to_cache("missing")
