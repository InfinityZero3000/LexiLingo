"""
KG query cache and CEFR level utilities.

Provides:
  _KG_QUERY_CACHE         — in-process LRU cache for KG query results
  _token_count_approx     — cheap token counter (regex-based)
  _kg_cache_key           — MD5 cache key for (query, level, top_k)
  _kg_cache_get           — TTL-aware LRU get
  _kg_cache_set           — LRU set with max-size eviction
  _pack_kg_nodes_for_context — token-budget-aware node packer
  kg_concept_text         — the one place a concept becomes prompt text
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

from api.services.trace_cag.env_helpers import _env_int, kg_context_v2

logger = logging.getLogger(__name__)

_KG_QUERY_CACHE: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()

# A keyword field can be a whole forum answer (file 09 holds 1,000 of them). Clipped, one such node costs a few dozen
# tokens instead of eating a 160-token budget alone, or being dropped for not fitting.
_NODE_KEYWORD_WORD_CAP = 48
_CEFR_LEVELS = frozenset({"A1", "A2", "B1", "B2", "C1", "C2"})
# The loader stores "B1" for a concept whose source file gave no level (kg_data_loader.merge_knowledge_payload), so a stored
# "B1" cannot be told from a real one. A level reaches the prompt only for ids whose source files do label it.
_LEVELLED_ID_PREFIXES = (
    "concept:vocab.word.", "concept:phrase.cefr-sp-", "concept:grammar.", "concept:function.", "concept:conversation.",
    "concept:skill.", "concept:phonology.", "concept:pronunciation.", "concept:error.", "concept:wordform.",
)
_HASHED_ID = re.compile(r"-[0-9a-f]{10}$")   # file 09 (forum Q&A) ids: "concept:grammar.<question-slug>-<10 hex>", no level in source


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


def level_is_reliable(concept_id: str) -> bool:
    cid = str(concept_id or "")
    if cid.startswith("concept:grammar.") and _HASHED_ID.search(cid):
        return False   # file 09 only: the CEFR sentences (concept:phrase.cefr-sp-...) also end in a hash and are labelled
    return cid.startswith(_LEVELLED_ID_PREFIXES)


def kg_concept_text(
    title: str, keywords: str = "", level: str = "", concept_id: str = "", *, label: str = "Concept", max_words: int = _NODE_KEYWORD_WORD_CAP,
    keywords_always: bool = False,
) -> str:
    """How a KG concept is written into the prompt: title, CEFR level when the source labelled it, clipped keywords.

    Used for both the cost the packer counts and the text the prompt gets, so the two cannot drift apart.
    """
    if not kg_context_v2():   # the text before 2026-11-11: no level, whole keyword field
        kw = str(keywords or "")
        return f"{label}: {title}. Keywords: {kw}" if (kw or keywords_always) else f"{label}: {title}"
    tag = f" (CEFR {level.upper()})" if str(level).upper() in _CEFR_LEVELS and level_is_reliable(concept_id) else ""
    words = str(keywords or "").split()
    clipped = " ".join(words[:max_words])
    text = f"{label}: {title}{tag}"
    return f"{text}. Keywords: {clipped}" if clipped else text


def _pack_kg_nodes_for_context(nodes: List[Dict[str, Any]], token_budget: int) -> List[Dict[str, Any]]:
    """Fill the budget in rank order. A node that does not fit is skipped, not the end of the list: the next one may be short.

    Returns copies carrying `context_text`, the exact text whose cost was counted.
    """
    if token_budget <= 0:
        return []
    packed: List[Dict[str, Any]] = []
    used = 0
    v2 = kg_context_v2()
    for node in nodes:
        title = str(node.get("title") or node.get("id") or "")
        text = kg_concept_text(title, str(node.get("keywords") or ""), str(node.get("level") or ""), str(node.get("id") or ""),
                               keywords_always=True)
        cost = _token_count_approx(text.strip())
        if cost <= 0:
            continue
        if used + cost > token_budget:
            if v2:
                continue
            break   # before 2026-11-11: one oversize node ended the list
        packed.append({**node, "context_text": text})
        used += cost
        if used >= token_budget:
            break
    return packed


_CEFR_ORD: Dict[str, int] = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}


def _cefr_distance(a: str, b: str) -> int:
    """Absolute ordinal distance between two CEFR levels."""
    return abs(_CEFR_ORD.get(a, 3) - _CEFR_ORD.get(b, 3))
