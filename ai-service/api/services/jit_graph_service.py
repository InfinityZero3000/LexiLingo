"""JIT mini-graph extraction service for TraceCAG.

This service is designed for low-latency query-time extraction:
- Entity extraction via GLiNER (lazy-loaded)
- Lightweight relation stitching via adjacency heuristics
- Compact JSON serialization for soft graph prompts

The service is optional at runtime. If GLiNER is unavailable, it degrades
gracefully and returns an empty graph payload instead of failing requests.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import time
from collections import OrderedDict
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

import networkx as nx

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class JITGraphConfig:
    enabled: bool
    model_name: str
    threshold: float
    max_nodes: int
    max_edges: int
    max_chars: int
    cache_ttl_seconds: int
    cache_max_entries: int


class JITGraphService:
    """Reusable async service for JIT mini-graph extraction."""

    DEFAULT_LABELS: Tuple[str, ...] = (
        "person",
        "organization",
        "location",
        "event",
        "product",
        "technology",
        "date",
        "time",
    )

    def __init__(self) -> None:
        self._model = None
        self._model_lock = asyncio.Lock()
        self._query_cache: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()

    async def extract_soft_graph(self, query: str) -> Dict[str, Any]:
        cfg = self._load_config()
        if not cfg.enabled:
            return {
                "enabled": False,
                "model": "jit_graph_disabled",
                "latency_ms": 0.0,
                "node_count": 0,
                "edge_count": 0,
                "soft_graph": "",
            }

        normalized = str(query or "").strip()
        if not normalized:
            return {
                "enabled": True,
                "model": "jit_graph_empty_query",
                "latency_ms": 0.0,
                "node_count": 0,
                "edge_count": 0,
                "soft_graph": "",
            }

        cache_key = normalized.lower()
        cached = self._cache_get(cache_key, cfg)
        if cached is not None:
            payload = dict(cached)
            payload["cache_hit"] = True
            return payload

        started = time.perf_counter()
        gliner_model = await self._ensure_gliner_model(cfg.model_name)

        entities: List[Dict[str, Any]] = []
        model_name = "jit_graph_fallback"
        if gliner_model is not None:
            try:
                raw = await asyncio.to_thread(
                    gliner_model.predict_entities,
                    normalized,
                    labels=list(self.DEFAULT_LABELS),
                    threshold=cfg.threshold,
                )
                entities = self._normalize_entities(raw, normalized)
                model_name = cfg.model_name
            except Exception as exc:
                logger.warning("[JITGraphService] GLiNER extraction failed, fallback mode: %s", exc)

        if not entities:
            entities = self._fallback_entities(normalized)

        entities = self._dedupe_entities(entities)[: cfg.max_nodes]
        graph = self._build_graph(normalized, entities, max_edges=cfg.max_edges)
        compact = self._serialize_graph(graph, max_chars=cfg.max_chars)
        latency_ms = (time.perf_counter() - started) * 1000.0

        payload = {
            "enabled": True,
            "model": model_name,
            "latency_ms": round(latency_ms, 3),
            "node_count": graph.number_of_nodes(),
            "edge_count": graph.number_of_edges(),
            "soft_graph": compact,
        }

        self._cache_set(cache_key, payload, cfg)
        payload["cache_hit"] = False
        return payload

    async def _ensure_gliner_model(self, model_name: str) -> Optional[Any]:
        if self._model is not None:
            return self._model

        async with self._model_lock:
            if self._model is not None:
                return self._model

            try:
                from gliner import GLiNER
            except Exception as exc:
                logger.warning("[JITGraphService] gliner import unavailable: %s", exc)
                return None

            try:
                self._model = await asyncio.to_thread(GLiNER.from_pretrained, model_name)
                logger.info("[JITGraphService] Loaded GLiNER model: %s", model_name)
                return self._model
            except Exception as exc:
                logger.warning("[JITGraphService] Failed to load GLiNER model %s: %s", model_name, exc)
                self._model = None
                return None

    @staticmethod
    def _normalize_entities(raw_entities: Any, text: str) -> List[Dict[str, Any]]:
        normalized: List[Dict[str, Any]] = []
        if not isinstance(raw_entities, list):
            return normalized

        for item in raw_entities:
            if not isinstance(item, dict):
                continue
            entity_text = str(item.get("text") or "").strip()
            if not entity_text:
                continue

            start = item.get("start")
            end = item.get("end")
            if not isinstance(start, int) or not isinstance(end, int) or end <= start:
                pos = text.lower().find(entity_text.lower())
                if pos < 0:
                    continue
                start = pos
                end = pos + len(entity_text)

            normalized.append(
                {
                    "text": entity_text,
                    "label": str(item.get("label") or "entity").strip().lower(),
                    "score": float(item.get("score") or 0.0),
                    "start": start,
                    "end": end,
                }
            )

        normalized.sort(key=lambda e: (int(e.get("start", 0)), -float(e.get("score", 0.0))))
        return normalized

    @staticmethod
    def _fallback_entities(text: str) -> List[Dict[str, Any]]:
        entities: List[Dict[str, Any]] = []
        for match in re.finditer(r"\b[A-Z][a-zA-Z0-9_\-]{2,}\b", text):
            entities.append(
                {
                    "text": match.group(0),
                    "label": "entity",
                    "score": 0.35,
                    "start": match.start(),
                    "end": match.end(),
                }
            )
        return entities

    @staticmethod
    def _dedupe_entities(entities: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
        deduped: List[Dict[str, Any]] = []
        seen = set()
        for entity in entities:
            key = (str(entity.get("text", "")).lower(), str(entity.get("label", "entity")))
            if key in seen:
                continue
            seen.add(key)
            deduped.append(dict(entity))
        return deduped

    @staticmethod
    def _infer_relation(span_text: str) -> str:
        compact = re.sub(r"\s+", " ", span_text).strip(" ,.;:\n\t")
        if not compact:
            return "related_to"
        if len(compact) > 32:
            return "contextual_link"
        if re.search(r"\b(in|on|at|from|to|with|for|by|of|during|through)\b", compact, re.IGNORECASE):
            return compact.lower()
        return "related_to"

    def _build_graph(self, text: str, entities: Sequence[Dict[str, Any]], max_edges: int) -> nx.DiGraph:
        graph = nx.DiGraph()
        node_ids: List[str] = []
        for idx, entity in enumerate(entities):
            node_id = f"n{idx}"
            node_ids.append(node_id)
            graph.add_node(
                node_id,
                t=str(entity.get("text") or ""),
                l=str(entity.get("label") or "entity"),
                s=round(float(entity.get("score") or 0.0), 3),
            )

        edge_count = 0
        for i in range(len(entities) - 1):
            if edge_count >= max_edges:
                break
            left = entities[i]
            right = entities[i + 1]
            left_end = int(left.get("end") or 0)
            right_start = int(right.get("start") or 0)
            between = text[left_end:right_start]
            graph.add_edge(
                node_ids[i],
                node_ids[i + 1],
                r=self._infer_relation(between),
                s=round(max(0.05, min(float(left.get("score") or 0.0), float(right.get("score") or 0.0))), 3),
            )
            edge_count += 1

        return graph

    @staticmethod
    def _serialize_graph(graph: nx.DiGraph, max_chars: int) -> str:
        payload = {
            "v": 1,
            "n": [
                {
                    "id": node_id,
                    "t": str(attrs.get("t") or ""),
                    "l": str(attrs.get("l") or "entity"),
                    "s": float(attrs.get("s") or 0.0),
                }
                for node_id, attrs in graph.nodes(data=True)
            ],
            "e": [
                {
                    "u": src,
                    "v": dst,
                    "r": str(attrs.get("r") or "related_to"),
                    "s": float(attrs.get("s") or 0.0),
                }
                for src, dst, attrs in graph.edges(data=True)
            ],
        }

        compact = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        if len(compact) <= max_chars:
            return compact

        shrunk = {
            "v": payload.get("v", 1),
            "n": list(payload.get("n", [])),
            "e": list(payload.get("e", [])),
        }

        while len(json.dumps(shrunk, separators=(",", ":"), ensure_ascii=False)) > max_chars and shrunk["e"]:
            shrunk["e"].pop()
        while len(json.dumps(shrunk, separators=(",", ":"), ensure_ascii=False)) > max_chars and len(shrunk["n"]) > 2:
            shrunk["n"].pop()

        return json.dumps(shrunk, separators=(",", ":"), ensure_ascii=False)

    def _cache_get(self, key: str, cfg: JITGraphConfig) -> Optional[Dict[str, Any]]:
        entry = self._query_cache.get(key)
        if not entry:
            return None
        now = time.monotonic()
        if now - float(entry.get("ts") or 0.0) > cfg.cache_ttl_seconds:
            self._query_cache.pop(key, None)
            return None
        self._query_cache.move_to_end(key)
        return dict(entry.get("payload") or {})

    def _cache_set(self, key: str, payload: Dict[str, Any], cfg: JITGraphConfig) -> None:
        self._query_cache[key] = {"ts": time.monotonic(), "payload": dict(payload)}
        self._query_cache.move_to_end(key)
        while len(self._query_cache) > cfg.cache_max_entries:
            self._query_cache.popitem(last=False)

    @staticmethod
    def _load_config() -> JITGraphConfig:
        def _flag(name: str, default: bool = False) -> bool:
            raw = str(os.getenv(name, "1" if default else "0")).strip().lower()
            return raw in {"1", "true", "yes", "on"}

        def _f(name: str, default: float) -> float:
            raw = os.getenv(name)
            if raw is None:
                return default
            try:
                return float(raw)
            except ValueError:
                return default

        def _i(name: str, default: int) -> int:
            raw = os.getenv(name)
            if raw is None:
                return default
            try:
                return int(raw)
            except ValueError:
                return default

        return JITGraphConfig(
            enabled=_flag("TRACECAG_ENABLE_JIT_MINIGRAPH", True),
            model_name=os.getenv("TRACECAG_JIT_GLINER_MODEL", "urchade/gliner_small-v2.1"),
            threshold=max(0.05, min(0.95, _f("TRACECAG_JIT_GLINER_THRESHOLD", 0.45))),
            max_nodes=max(2, _i("TRACECAG_JIT_MAX_NODES", 10)),
            max_edges=max(1, _i("TRACECAG_JIT_MAX_EDGES", 14)),
            max_chars=max(240, _i("TRACECAG_JIT_MAX_CHARS", 1200)),
            cache_ttl_seconds=max(10, _i("TRACECAG_JIT_CACHE_TTL_SECONDS", 900)),
            cache_max_entries=max(16, _i("TRACECAG_JIT_CACHE_MAX_ENTRIES", 512)),
        )


_jit_graph_instance: Optional[JITGraphService] = None


def get_jit_graph_service() -> JITGraphService:
    global _jit_graph_instance
    if _jit_graph_instance is None:
        _jit_graph_instance = JITGraphService()
    return _jit_graph_instance
