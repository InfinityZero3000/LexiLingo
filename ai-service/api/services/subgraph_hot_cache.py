"""Subgraph Hot-Cache for topic-based sessions.

For each topic (story), pre-computes a KG subgraph by:
  1. Extracting vocab terms + grammar topic words from the story
  2. Finding matching KG seed concepts (keyword index + TF-IDF)
  3. Expanding 2 hops via best-first search (CEFR-weighted)
  4. Serializing the subgraph to a compact JSON buffer
  5. Storing in Redis at kg:subgraph:{story_id} with 24h TTL

On subsequent requests the pre-computed subgraph is served directly,
avoiding full KG traversal per message.

Architecture alignment with copilot-instructions:
- Graph-to-Buffer Serialization  → JSON buffer in Redis
- Graph Partitioning             → level-based edge filtering
- KV Cache Gating via KG         → topic_fingerprint field in bundle
- Subgraph Hot-Caching           → primary purpose of this module
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any, Dict, List, Optional

import redis.asyncio as redis

from api.services.kg_service_v3 import get_kg_service

logger = logging.getLogger(__name__)

# ── Redis key constants ─────────────────────────────────────────────────────
_PREFIX = "kg:subgraph:"
_TTL_SECONDS = 86_400  # 24 hours

# ── CEFR level partition ordering ──────────────────────────────────────────
_LEVEL_ORDER = {"A1": 0, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5}


def _cefr_distance(target: str, node_level: str) -> int:
    """Absolute CEFR distance between two levels (used for partition filtering)."""
    return abs(_LEVEL_ORDER.get(target, 2) - _LEVEL_ORDER.get(node_level, 2))


def _extract_text_for_seeds(story_vocab: List[Dict], story_grammar: List[Dict]) -> str:
    """Build a combined text blob from vocab terms and grammar topics."""
    parts: List[str] = []
    for v in story_vocab:
        term = v.get("term") or v.get("word") or ""
        if term:
            parts.append(term)
        defn = v.get("definition") or ""
        if defn:
            parts.append(defn)
    for g in story_grammar:
        topic = g.get("topic") or g.get("name") or ""
        if topic:
            parts.append(topic)
        explanation = g.get("explanation") or ""
        if explanation:
            parts.append(explanation)
    return " ".join(parts)


def _serialize_subgraph(
    seed_concepts: List[str],
    expanded_nodes: List[Dict],
    paths: List[Dict],
    story_level: str,
    topic_fingerprint: str,
) -> bytes:
    """Serialize subgraph to a compact JSON buffer (Graph-to-Buffer Serialization)."""
    # Graph Partitioning: only include nodes within 2 CEFR levels of the story
    filtered_nodes = [
        n for n in expanded_nodes
        if _cefr_distance(story_level, n.get("level", "B1")) <= 2
    ]
    bundle = {
        "topic_fingerprint": topic_fingerprint,
        "story_level": story_level,
        "seed_concepts": seed_concepts,
        "nodes": filtered_nodes,
        "paths": paths,
        "built_at": int(time.time()),
    }
    return json.dumps(bundle, separators=(",", ":")).encode("utf-8")


async def warm_subgraph(
    story_id: str,
    story_vocab: List[Dict],
    story_grammar: List[Dict],
    story_level: str,
    redis_client: redis.Redis,
    force: bool = False,
) -> Dict[str, Any]:
    """
    Pre-compute and cache the KG subgraph for a story.

    Returns the subgraph bundle dict (either freshly built or from cache).
    If KG is unavailable the function degrades gracefully and returns an
    empty bundle so callers don't crash.

    Args:
        story_id:      Unique story identifier used as cache key.
        story_vocab:   List of vocabulary dicts from Story.vocabulary_list.
        story_grammar: List of grammar dicts from Story.grammar_points.
        story_level:   CEFR level string (e.g. "B1").
        redis_client:  Async redis client.
        force:         If True, bypass cache and rebuild.
    """
    cache_key = f"{_PREFIX}{story_id}"

    if not force:
        cached = await redis_client.get(cache_key)
        if cached:
            try:
                bundle = json.loads(cached)
                logger.debug("[SubgraphCache] HIT for story=%s", story_id)
                return bundle
            except Exception:
                logger.warning("[SubgraphCache] Corrupt cache for story=%s, rebuilding", story_id)

    logger.info("[SubgraphCache] Building subgraph for story=%s level=%s", story_id, story_level)

    try:
        kg = get_kg_service()
    except Exception as exc:
        logger.error("[SubgraphCache] KG service unavailable: %s", exc)
        return _empty_bundle(story_id, story_level)

    # 1. Derive seed concepts from story vocabulary + grammar text
    seed_text = _extract_text_for_seeds(story_vocab, story_grammar)
    seed_concepts: List[str] = []
    try:
        fast_seeds = kg.get_seed_concepts_fast(seed_text)
        seed_concepts.extend(fast_seeds)
    except Exception as exc:
        logger.warning("[SubgraphCache] get_seed_concepts_fast failed: %s", exc)

    # Supplement with semantic seeds if we have few results
    if len(seed_concepts) < 3:
        try:
            sem_seeds = kg.semantic_seed_concepts(seed_text, top_k=8)
            for s in sem_seeds:
                if s not in seed_concepts:
                    seed_concepts.append(s)
        except Exception as exc:
            logger.warning("[SubgraphCache] semantic_seed_concepts failed: %s", exc)

    # Deduplicate, cap at 20 seeds to keep subgraph manageable
    seed_concepts = list(dict.fromkeys(seed_concepts))[:20]
    logger.info("[SubgraphCache] story=%s seeds=%d", story_id, len(seed_concepts))

    # 2. Expand subgraph 2 hops (best-first, CEFR-weighted)
    expanded_nodes: List[Dict] = []
    paths: List[Dict] = []
    if seed_concepts:
        try:
            kg_hits = await kg.expand_best_first(
                seed_nodes=seed_concepts,
                hops=2,
                max_nodes=60,
            )
            expanded_nodes = [
                {
                    "id": n.concept_id,
                    "title": n.title,
                    "level": n.level,
                    "relevance": round(n.relevance_score, 4),
                }
                for n in kg_hits.nodes
            ]
            paths = [
                {"src": p.source, "rel": p.relation, "dst": p.target}
                for p in kg_hits.paths
            ]
        except Exception as exc:
            logger.warning("[SubgraphCache] expand_best_first failed: %s", exc)

    # 3. Build cache fingerprint (used for KV Cache Gating)
    topic_fingerprint = _build_fingerprint(story_id, seed_concepts, story_level)

    # 4. Serialize + partition
    buf = _serialize_subgraph(
        seed_concepts, expanded_nodes, paths, story_level, topic_fingerprint
    )
    bundle = json.loads(buf)

    # 5. Store in Redis with TTL
    try:
        await redis_client.set(cache_key, buf, ex=_TTL_SECONDS)
        logger.info(
            "[SubgraphCache] Stored subgraph for story=%s: %d nodes, %d paths, %.1f KB",
            story_id, len(expanded_nodes), len(paths), len(buf) / 1024,
        )
    except Exception as exc:
        logger.warning("[SubgraphCache] Redis store failed: %s", exc)

    return bundle


async def get_subgraph(story_id: str, redis_client: redis.Redis) -> Optional[Dict[str, Any]]:
    """
    Fetch a pre-computed subgraph bundle from Redis cache.

    Returns None on cache miss or deserialization error.
    Used by topic_chat to load KG seed concepts for a session.
    """
    cache_key = f"{_PREFIX}{story_id}"
    try:
        cached = await redis_client.get(cache_key)
        if cached:
            return json.loads(cached)
    except Exception as exc:
        logger.warning("[SubgraphCache] get_subgraph failed for story=%s: %s", story_id, exc)
    return None


async def invalidate_subgraph(story_id: str, redis_client: redis.Redis) -> None:
    """Delete a cached subgraph (e.g. when story vocab is updated)."""
    cache_key = f"{_PREFIX}{story_id}"
    try:
        await redis_client.delete(cache_key)
        logger.info("[SubgraphCache] Invalidated subgraph for story=%s", story_id)
    except Exception as exc:
        logger.warning("[SubgraphCache] invalidate failed: %s", exc)


# ── Helpers ──────────────────────────────────────────────────────────────────

def _build_fingerprint(story_id: str, seed_concepts: List[str], level: str) -> str:
    """
    Build a short deterministic fingerprint for KV Cache Gating.

    The TraceCAG pipeline can use this to decide whether a cached response
    is still valid for the same conceptual context.
    """
    import hashlib
    raw = f"{story_id}:{level}:{':'.join(sorted(seed_concepts))}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def _empty_bundle(story_id: str, story_level: str) -> Dict[str, Any]:
    return {
        "topic_fingerprint": "",
        "story_level": story_level,
        "seed_concepts": [],
        "nodes": [],
        "paths": [],
        "built_at": int(time.time()),
    }
