"""RecGraph nodes. I/O and model calls live here; the maths lives in scoring."""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
from typing import Any, Dict, List, Optional, TypedDict

from api.core.redis_client import get_redis
from api.services.model_gateway import get_model_gateway
from api.services.rec_graph import scoring

logger = logging.getLogger(__name__)

CACHE_TTL_SECONDS = 900
_MAX_CANDIDATES = 400
# The shared Redis client retries 10 times with backoff (~40s) before giving
# up. That is right for a chat turn and fatal here: a cache lookup must never
# cost more than the work it saves, so cap it and move on.
_CACHE_TIMEOUT_SECONDS = 0.25

class RecState(TypedDict, total=False):
    user_id: str
    surface: str
    k: int
    profile: Dict[str, Any]
    candidates: List[Dict[str, Any]]
    cache_key: str
    cache_hit: bool
    scored: List[Dict[str, Any]]
    recommendations: List[Dict[str, Any]]
    latency_ms: int


def build_cache_key(state: RecState) -> str:
    """Keyed on state_epoch (graded activity) and interaction_epoch (browsing)
    so either kind of learner change invalidates on its own."""
    profile = state.get("profile") or {}
    parts = [
        state.get("user_id", ""),
        state.get("surface", "home"),
        str(state.get("k", 10)),
        str(profile.get("state_epoch", 0)),
        str(profile.get("interaction_epoch", 0)),
        str(profile.get("catalog_version", 0)),
    ]
    return "rec:v1:" + hashlib.sha256(":".join(parts).encode()).hexdigest()[:32]


async def cache_gate_node(state: RecState) -> RecState:
    key = build_cache_key(state)
    try:
        cached = await asyncio.wait_for(
            _cache_get(key), timeout=_CACHE_TIMEOUT_SECONDS
        )
        if cached:
            return {
                "cache_key": key,
                "cache_hit": True,
                "recommendations": json.loads(cached),
            }
    except Exception as exc:  # cache must never fail the request
        logger.warning("rec_graph cache read failed: %s", exc)
    return {"cache_key": key, "cache_hit": False}


async def embed_node(state: RecState) -> RecState:
    """Attach a content-embedding similarity to every candidate.

    This is the cold-start path: it needs no interaction history at all, only
    the learner's stated level, weak skills and topic affinity.

    Embedding goes through ModelGateway's `minilm` rather than a local
    SentenceTransformer so this shares one loaded model with TraceCAG retrieval
    and stays inside the gateway's memory accounting and idle-unload.
    """
    candidates = (state.get("candidates") or [])[:_MAX_CANDIDATES]
    if not candidates:
        return {"candidates": []}

    profile_text = _profile_text(state.get("profile") or {})
    item_texts = [_item_text(item) for item in candidates]

    try:
        gateway = get_model_gateway()
        # Call `similarity` directly, not the handler's own `invoke` — the
        # gateway already wraps the return in {"success", "data"}, so going
        # through invoke() nests the payload twice.
        result = await gateway.invoke(
            "minilm",
            "similarity",
            {"query": profile_text, "candidates": item_texts},
        )
        if not result.get("success"):
            raise RuntimeError(result.get("error", "minilm similarity failed"))
        # ponytail: re-encodes the pool on every cache miss (~200 texts, ~150ms
        # on CPU). Cache per item_id + content_version if the catalog grows.
        scores = {row["text"]: row["score"] for row in result.get("data") or []}
    except Exception as exc:
        logger.warning("rec_graph embedding failed, similarity=0: %s", exc)
        return {"candidates": [{**item, "similarity": 0.0} for item in candidates]}

    return {
        "candidates": [
            # Cosine is in [-1,1]; the score layer expects [0,1].
            {**item, "similarity": max(0.0, float(scores.get(text, 0.0)))}
            for item, text in zip(candidates, item_texts)
        ]
    }


async def score_node(state: RecState) -> RecState:
    profile = state.get("profile") or {}
    weights = profile.get("weights") or None
    scored = [
        scoring.score_candidate(
            item,
            profile,
            weights=weights,
            similarity=item.get("similarity", 0.0),
            sequential=item.get("sequential", 0.0),
        )
        for item in state.get("candidates") or []
    ]
    return {"scored": scored}


async def rerank_node(state: RecState) -> RecState:
    scored = state.get("scored") or []
    k = int(state.get("k", 10))
    ranked = scoring.mmr_rerank(scored, k)
    required = (state.get("profile") or {}).get("required_types") or []
    ranked = scoring.enforce_type_quota(ranked, scored, required)
    return {"recommendations": ranked}


async def explain_node(state: RecState) -> RecState:
    """Attach a Vietnamese reason and persist the result.

    ponytail: templates, not an LLM call — the reason is a restatement of
    features we already computed, and an LLM here would add ~1s to every
    request. Swap in generate.py's client if the copy ever needs to vary.
    """
    profile = state.get("profile") or {}
    explained = [
        {**item, "reason": _reason_for(item, profile)}
        for item in state.get("recommendations") or []
    ]

    key = state.get("cache_key")
    if key:
        try:
            await asyncio.wait_for(
                _cache_set(key, json.dumps(explained)),
                timeout=_CACHE_TIMEOUT_SECONDS,
            )
        except Exception as exc:
            logger.warning("rec_graph cache write failed: %s", exc)

    return {"recommendations": explained}


def _reason_for(item: Dict[str, Any], profile: Dict[str, Any]) -> str:
    features = item.get("features") or {}
    topic = item.get("topic")
    if features.get("due", 0) >= 0.5:
        return "Đã đến hạn ôn lại phần này"
    if features.get("topic", 0) >= 0.5 and topic:
        return f"Bạn học nhiều về chủ đề {topic}"
    if features.get("mastery_gap", 0) >= 0.6:
        return "Phần này bạn chưa nắm vững"
    if features.get("cefr_fit", 0) >= 1.0:
        return f"Vừa sức với trình độ {profile.get('level', '')}".strip()
    if features.get("similarity", 0) >= 0.4:
        return "Gần với nội dung bạn đang học"
    return "Gợi ý cho bạn"


async def _cache_get(key: str) -> Optional[str]:
    client = await get_redis()
    return await client.get(key)


async def _cache_set(key: str, value: str) -> None:
    client = await get_redis()
    await client.setex(key, CACHE_TTL_SECONDS, value)


def _profile_text(profile: Dict[str, Any]) -> str:
    affinity = profile.get("topic_affinity") or {}
    top_topics = sorted(affinity, key=affinity.get, reverse=True)[:5]
    weak = profile.get("weak_skills") or []
    goal = profile.get("goal") or ""
    return " ".join(
        filter(
            None,
            [
                f"CEFR level {profile.get('level', 'A1')}",
                "topics: " + ", ".join(top_topics) if top_topics else "",
                "needs practice in: " + ", ".join(weak) if weak else "",
                f"goal: {goal}" if goal else "",
            ],
        )
    )


def _item_text(item: Dict[str, Any]) -> str:
    return " ".join(
        filter(
            None,
            [
                item.get("title") or "",
                item.get("description") or "",
                item.get("topic") or "",
                " ".join(item.get("tags") or []),
                item.get("skill") or "",
                item.get("level") or "",
            ],
        )
    ).strip() or (item.get("item_id") or "")


