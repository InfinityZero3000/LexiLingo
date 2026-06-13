"""
KG query cache and CEFR level utilities.

Provides:
  _KG_QUERY_CACHE         — in-process LRU cache for KG query results
  _token_count_approx     — cheap token counter (regex-based)
  _kg_cache_key           — MD5 cache key for (query, level, top_k)
  _kg_cache_get           — TTL-aware LRU get
  _kg_cache_set           — LRU set with max-size eviction
  _pack_kg_nodes_for_context — token-budget-aware node packer
  _CEFR_ORD               — ordinal mapping for CEFR levels
  _cefr_distance          — absolute ordinal distance between two CEFR levels
"""

from __future__ import annotations

import hashlib
import logging
import re
import time
from collections import OrderedDict
from typing import Any, Dict, List, Optional

from api.services.trace_cag.env_helpers import _env_int

logger = logging.getLogger(__name__)

_KG_QUERY_CACHE: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()


def _token_count_approx(text: str) -> int:
    if not text:
        return 0
    return len(re.findall(r"\w+|[^\w\s]", text, flags=re.UNICODE))


def _kg_cache_key(query: str, level: str, top_k: int) -> str:
    raw = f"{query.strip().lower()}||{str(level).upper()}||{top_k}"
    return hashlib.md5(raw.encode("utf-8")).hexdigest()


def _kg_cache_get(key: str) -> Optional[List[Dict[str, Any]]]:
    now = time.monotonic()
    ttl_seconds = max(1, _env_int("TRACECAG_KG_QUERY_CACHE_TTL_SECONDS", 900))
    item = _KG_QUERY_CACHE.get(key)
    if not item:
        return None
    if now - float(item.get("ts", 0.0)) > ttl_seconds:
        _KG_QUERY_CACHE.pop(key, None)
        return None
    _KG_QUERY_CACHE.move_to_end(key)
    return list(item.get("data") or [])


def _kg_cache_set(key: str, data: List[Dict[str, Any]]) -> None:
    max_entries = max(1, _env_int("TRACECAG_KG_QUERY_CACHE_MAX_ENTRIES", 200))
    _KG_QUERY_CACHE[key] = {"ts": time.monotonic(), "data": list(data)}
    _KG_QUERY_CACHE.move_to_end(key)
    while len(_KG_QUERY_CACHE) > max_entries:
        _KG_QUERY_CACHE.popitem(last=False)


def _pack_kg_nodes_for_context(nodes: List[Dict[str, Any]], token_budget: int) -> List[Dict[str, Any]]:
    if token_budget <= 0:
        return []
    packed: List[Dict[str, Any]] = []
    used = 0
    for node in nodes:
        title = str(node.get("title") or node.get("id") or "")
        keywords = str(node.get("keywords") or "")
        snippet = f"Concept: {title}. Keywords: {keywords}".strip()
        cost = _token_count_approx(snippet)
        if cost <= 0:
            continue
        if used + cost > token_budget:
            break
        packed.append(node)
        used += cost
    return packed


_CEFR_ORD: Dict[str, int] = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}


def _cefr_distance(a: str, b: str) -> int:
    """Absolute ordinal distance between two CEFR levels."""
    return abs(_CEFR_ORD.get(a, 3) - _CEFR_ORD.get(b, 3))
