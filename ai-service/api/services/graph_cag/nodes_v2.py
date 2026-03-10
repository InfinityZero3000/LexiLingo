"""
GraphCAG Node Functions - Enhanced with ModelGateway

Each node uses ModelGateway for:
1. Lazy loading: Models load on first use
2. Smart routing: Automatic model selection
3. Memory management: Auto unload idle models
4. Unified interface: Single gateway for all AI operations

Pipeline Flow:
INPUT → KG_EXPAND → DIAGNOSE → RETRIEVE → GENERATE → [VIETNAMESE] → [TTS] → END
"""

import logging
import time
import asyncio
import re
import json
import hashlib
from typing import Dict, Any, List, Optional

from api.services.graph_cag.state import (
    GraphCAGState, DiagnosisError, CacheFingerprint, CacheEntry,
)

logger = logging.getLogger(__name__)


# ============================================================
# CEFR LEVEL UTILITIES
# ============================================================

_CEFR_ORD: Dict[str, int] = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}


def _cefr_distance(a: str, b: str) -> int:
    """Absolute ordinal distance between two CEFR levels."""
    return abs(_CEFR_ORD.get(a, 3) - _CEFR_ORD.get(b, 3))


# ============================================================
# PCC RISK SCORING (paper §4.1, Eq. 2)
# ============================================================

# Reuse-risk weights (tunable, sum to ~1.0)
_W_INTENT = 0.30     # w1: intent mismatch (0/1)
_W_CONCEPT = 0.25    # w2: concept drift (1-Jaccard)
_W_LEVEL = 0.20      # w3: normalized level drift
_W_PROGRESS = 0.10   # w4: profile progress drift
_W_STALENESS = 0.15  # w5: staleness ratio

# Thresholds for ternary decision
_TAU_REUSE = 0.25    # τ₀: max risk for direct reuse
_TAU_PATCH = 0.55    # τ₁: max risk for delta patching


def _is_exact_reuse_match(fingerprint: CacheFingerprint, entry: CacheEntry) -> bool:
    cached_fingerprint = entry.get("fingerprint") or {}
    if fingerprint.get("query_norm") != cached_fingerprint.get("query_norm"):
        return False
    if fingerprint.get("level") != cached_fingerprint.get("level"):
        return False

    current_intent = fingerprint.get("intent", "unknown")
    cached_intent = cached_fingerprint.get("intent", "unknown")
    if current_intent != "unknown" and cached_intent != "unknown" and current_intent != cached_intent:
        return False

    current_concepts = set(fingerprint.get("root_concepts") or [])
    cached_concepts = set(cached_fingerprint.get("root_concepts") or [])
    if current_concepts and cached_concepts and current_concepts != cached_concepts:
        return False

    return True


def _compute_reuse_risk(
    fingerprint: CacheFingerprint,
    entry: CacheEntry,
    now: float,
) -> float:
    """
    Compute scalar reuse risk ρ ∈ [0, 1] (paper Eq. 2).

    ρ = clip[0,1]( w1·ΔI + w2·ΔC + w3·Δℓ + w4·Δprog + w5·s )
    """
    # ΔI: intent mismatch (binary).
    # During the pre-diagnosis cache gate, intent may be unavailable; treat that
    # as "not yet observed" instead of penalizing the request immediately.
    cached_plan = entry.get("execution_plan") or {}
    cur_intent = fingerprint.get("intent", "unknown")
    cached_intent = cached_plan.get("intent", "unknown")
    if cur_intent == "unknown" or cached_intent == "unknown":
        delta_i = 0.0
    else:
        delta_i = 0.0 if cur_intent == cached_intent else 1.0

    # ΔC: concept drift (1 - Jaccard).
    # Root-cause concepts are also unavailable before diagnosis, so keep this
    # component neutral until the current request actually exposes concepts.
    cur_concepts = set(fingerprint.get("root_concepts") or [])
    cached_concepts = set((entry.get("fingerprint") or {}).get("root_concepts") or [])
    if not cur_concepts:
        delta_c = 0.0
    elif cur_concepts or cached_concepts:
        jaccard = len(cur_concepts & cached_concepts) / max(len(cur_concepts | cached_concepts), 1)
        delta_c = 1.0 - jaccard
    else:
        delta_c = 0.0  # both empty — no drift

    # Δℓ: normalized level drift
    cur_level = fingerprint.get("level", "B1")
    cached_level = (entry.get("fingerprint") or {}).get("level", "B1")
    delta_l = _cefr_distance(cur_level, cached_level) / 5.0  # max distance = 5

    # Δprog: profile progress drift (session turn difference, normalized)
    cur_turn = fingerprint.get("session_turn", 0)
    cached_turn = (entry.get("fingerprint") or {}).get("session_turn", 0)
    delta_prog = min(abs(cur_turn - cached_turn) / 10.0, 1.0)

    # s: staleness ratio
    created = entry.get("created_at", now)
    ttl = entry.get("ttl", 3600)
    staleness = min((now - created) / max(ttl, 1), 1.0)

    rho = (
        _W_INTENT * delta_i
        + _W_CONCEPT * delta_c
        + _W_LEVEL * delta_l
        + _W_PROGRESS * delta_prog
        + _W_STALENESS * staleness
    )

    # L0 exact repeats should remain direct reuses while the cache entry is live.
    if _is_exact_reuse_match(fingerprint, entry):
        rho -= _W_STALENESS * staleness

    return max(0.0, min(1.0, rho))


def _build_fingerprint(state: GraphCAGState) -> CacheFingerprint:
    """Build a cache fingerprint from current pipeline state."""
    return CacheFingerprint(
        query_norm=state.get("user_input", "").strip().lower(),
        intent=state.get("diagnosis_intent", "unknown"),
        level=state.get("learner_profile", {}).get("level", "B1"),
        root_concepts=state.get("diagnosis_root_causes", []),
        session_turn=len(state.get("conversation_history", [])),
    )


def _patch_response(entry: CacheEntry, fingerprint: CacheFingerprint) -> str:
    """
    Delta-patch a cached response for moderate drift (paper Alg. 1 line 13).

    Applies lightweight adjustments:
    - Re-target CEFR level vocabulary hints
    - Append changed concept references
    """
    response = entry.get("response", "")
    plan = entry.get("execution_plan") or {}

    # Adjust level reference if level drifted by 1
    cached_level = (entry.get("fingerprint") or {}).get("level", "B1")
    cur_level = fingerprint.get("level", "B1")
    if cached_level != cur_level:
        response = response.replace(f"({cached_level})", f"({cur_level})")

    # Append new concept references not in original evidence
    cur_concepts = set(fingerprint.get("root_concepts") or [])
    cached_concepts = set((entry.get("fingerprint") or {}).get("root_concepts") or [])
    new_concepts = cur_concepts - cached_concepts
    if new_concepts:
        extras = ", ".join(c.split(".")[-1].replace("_", " ") for c in new_concepts)
        response += f"\n\n(Also related: {extras})"

    return response


# ============================================================
# IN-PROCESS CACHE (Structured CacheEntry, fallback when Redis unavailable)
# ============================================================

_MEM_RESPONSE_CACHE: dict[str, tuple[float, CacheEntry]] = {}
_MEM_GRAPH_BUCKETS: dict[str, list[str]] = {}
_MEM_RESPONSE_CACHE_MAX_ITEMS = 1024
_MEM_BUCKET_MAX_ITEMS = 8


def _extract_lightweight_graph_concepts(user_input: str) -> list[str]:
    """Approximate root concepts before diagnosis for L1 bucket lookup."""
    text = user_input.lower()
    concepts: set[str] = set()

    pattern_map = {
        r"\b(i|you|we|they)\s+(is|was)\b": "concept:grammar.subject_verb_agreement",
        r"\b(he|she|it)\s+(go|want|need|have|do)\b": "concept:grammar.third_person_s",
        r"\byesterday\b.*\b(go|come|eat|buy|need|want)\b": "concept:grammar.past_time_markers",
        r"\b(have|has)\s+went\b": "concept:grammar.present_perfect",
        r"\bmore\s+better\b|\bmore\s+worse\b": "concept:grammar.comparatives",
        r"\bexplain\b|\bwhy\b|\bwhat does\b": "intent:explain",
        r"\bpractice\b|\bexercise\b|\bquiz\b": "intent:practice",
    }
    for pattern, concept in pattern_map.items():
        if re.search(pattern, text, re.IGNORECASE):
            concepts.add(concept)

    lexical_tokens = re.findall(r"[a-z]{4,}", text)
    for token in lexical_tokens[:8]:
        concepts.add(f"token:{token}")

    return sorted(concepts)


def _build_graph_bucket(user_input: str, level: str, conversation_history: list[dict[str, Any]]) -> str:
    """Cheap graph-aware bucket used for L1 candidate lookup."""
    concepts = _extract_lightweight_graph_concepts(user_input)
    if not concepts:
        concepts = ["token:generic"]
    bucket_material = "|".join([level, str(len(conversation_history) // 2)] + concepts[:5])
    return hashlib.md5(bucket_material.encode()).hexdigest()


def _register_graph_bucket(bucket: str, cache_key: str) -> None:
    if not bucket:
        return
    keys = [item for item in _MEM_GRAPH_BUCKETS.get(bucket, []) if item != cache_key]
    keys.insert(0, cache_key)
    _MEM_GRAPH_BUCKETS[bucket] = keys[:_MEM_BUCKET_MAX_ITEMS]


async def _register_graph_bucket_redis(bucket: str, cache_key: str, ttl: int) -> None:
    if not bucket:
        return
    try:
        from api.core.redis_client import RedisClient

        redis_client = await RedisClient.get_instance()
        bucket_key = f"v1:resp_bucket:{bucket}"
        raw = await redis_client.get(bucket_key)
        keys = json.loads(raw) if raw else []
        if not isinstance(keys, list):
            keys = []
        keys = [item for item in keys if isinstance(item, str) and item != cache_key]
        keys.insert(0, cache_key)
        await redis_client.set(bucket_key, json.dumps(keys[:_MEM_BUCKET_MAX_ITEMS]), ex=ttl)
    except Exception as e:
        logger.debug(f"[_register_graph_bucket_redis] Redis write failed: {e}")


async def _get_bucket_candidate_keys(bucket: str) -> list[str]:
    keys = list(_MEM_GRAPH_BUCKETS.get(bucket, []))
    if keys:
        return keys[:_MEM_BUCKET_MAX_ITEMS]

    try:
        from api.core.redis_client import RedisClient

        redis_client = await RedisClient.get_instance()
        raw = await redis_client.get(f"v1:resp_bucket:{bucket}")
        parsed = json.loads(raw) if raw else []
        if isinstance(parsed, list):
            parsed_keys = [item for item in parsed if isinstance(item, str)]
            if parsed_keys:
                _MEM_GRAPH_BUCKETS[bucket] = parsed_keys[:_MEM_BUCKET_MAX_ITEMS]
                return parsed_keys[:_MEM_BUCKET_MAX_ITEMS]
    except Exception as e:
        logger.debug(f"[_get_bucket_candidate_keys] Redis read failed: {e}")
    return []


async def _get_cache_entry(cache_key: str, level: str, now: float) -> CacheEntry | None:
    mem_entry = _MEM_RESPONSE_CACHE.get(cache_key)
    if mem_entry:
        expires_at, entry = mem_entry
        if expires_at > now:
            return entry
        _MEM_RESPONSE_CACHE.pop(cache_key, None)

    try:
        from api.core.redis_client import RedisClient

        redis_client = await RedisClient.get_instance()
        cached_json = await redis_client.get(f"v1:resp:{cache_key}")
        if not cached_json:
            return None
        raw = json.loads(cached_json)
        entry: CacheEntry = {
            "fingerprint": raw.get("fingerprint", {"level": level}),
            "graph_bucket": raw.get("graph_bucket", ""),
            "profile_snapshot": raw.get("profile_snapshot", {}),
            "response": raw.get("response", raw.get("tutor_response", "")),
            "evidence_bundle": raw.get("evidence_bundle", []),
            "execution_plan": raw.get("execution_plan", {"strategy": raw.get("strategy", "feedback")}),
            "diagnosis_errors": raw.get("diagnosis_errors", []),
            "overall_score": raw.get("overall_score", 0.8),
            "created_at": raw.get("created_at", now - 60),
            "ttl": raw.get("ttl", 3600),
        }
        ttl_remaining = max(entry["ttl"] - (now - entry.get("created_at", now)), 60)
        _MEM_RESPONSE_CACHE[cache_key] = (now + ttl_remaining, entry)
        if entry.get("graph_bucket"):
            _register_graph_bucket(entry["graph_bucket"], cache_key)
        return entry
    except Exception as e:
        logger.debug(f"[_get_cache_entry] Redis read failed: {e}")
        return None


async def _write_cache_entry(
    state: GraphCAGState,
    response: str,
    strategy: str,
    errors: list,
    overall_score: float,
    context: str = "",
) -> None:
    """Write a structured CacheEntry to both in-process and Redis caches."""
    user_input = state.get("user_input", "")
    level = state.get("learner_profile", {}).get("level", "B1")

    normalized = user_input.strip().lower()
    cache_raw = f"{normalized}||{level}"
    cache_key = hashlib.md5(cache_raw.encode()).hexdigest()
    graph_bucket = _build_graph_bucket(
        user_input,
        level,
        state.get("conversation_history", []),
    )

    ttl = 3600 if errors else 1800
    now = time.monotonic()

    # Truncate evidence_bundle to prevent large entries (max 10 items ~2KB)
    raw_bundle = [
        {"type": "kg", "content": c}
        for c in (context or "").split("\n") if c.strip()
    ]

    entry = CacheEntry(
        fingerprint=_build_fingerprint(state),
        graph_bucket=graph_bucket,
        profile_snapshot=dict(state.get("learner_profile", {})),
        response=response,
        evidence_bundle=raw_bundle[:10],
        execution_plan={
            "strategy": strategy,
            "intent": state.get("diagnosis_intent", "correct"),
        },
        diagnosis_errors=[dict(e) for e in errors] if errors else [],
        overall_score=overall_score,
        created_at=now,
        ttl=ttl,
    )

    # In-process cache — LRU eviction instead of naive clear()
    if len(_MEM_RESPONSE_CACHE) >= _MEM_RESPONSE_CACHE_MAX_ITEMS:
        # First evict all expired entries
        expired_keys = [k for k, (exp, _) in _MEM_RESPONSE_CACHE.items() if exp <= now]
        for k in expired_keys:
            _MEM_RESPONSE_CACHE.pop(k, None)
        # If still at capacity, evict oldest 25% by expiry time
        if len(_MEM_RESPONSE_CACHE) >= _MEM_RESPONSE_CACHE_MAX_ITEMS:
            evict_count = _MEM_RESPONSE_CACHE_MAX_ITEMS // 4
            oldest = sorted(_MEM_RESPONSE_CACHE.items(), key=lambda kv: kv[1][0])[:evict_count]
            for k, _ in oldest:
                _MEM_RESPONSE_CACHE.pop(k, None)
    _MEM_RESPONSE_CACHE[cache_key] = (now + ttl, entry)
    _register_graph_bucket(graph_bucket, cache_key)

    # Redis
    try:
        from api.core.redis_client import RedisClient
        redis_client = await RedisClient.get_instance()
        await redis_client.set(f"v1:resp:{cache_key}", json.dumps(entry), ex=ttl)
        await _register_graph_bucket_redis(graph_bucket, cache_key, ttl)
        logger.debug(f"[_write_cache_entry] Cached key={cache_key[:8]} ttl={ttl}s")
    except Exception as e:
        logger.debug(f"[_write_cache_entry] Redis write failed: {e}")


# ============================================================
# MODEL GATEWAY INTEGRATION
# ============================================================

_gateway_instance = None


async def get_gateway():
    """Get or initialize the ModelGateway singleton"""
    global _gateway_instance
    
    if _gateway_instance is None:
        from api.services.model_gateway import get_model_gateway
        _gateway_instance = get_model_gateway()
    
    return _gateway_instance


# ============================================================
# NODE 1: INPUT NODE
# ============================================================

async def input_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Parse and validate user input, load learner context.
    
    Responsibilities:
    - Validate input text
    - Load learner profile from Redis
    - Load conversation history
    - Set initial metadata
    """
    user_input = state.get("user_input", "")
    logger.info(f"[input_node] Processing: {user_input[:50]}...")
    start_time = time.time()
    
    try:
        # Load learner profile from Redis
        from api.core.redis_client import LearnerProfileCache, ConversationCache, RedisClient
        
        learner_profile = state.get("learner_profile", {"level": "B1"})
        conversation_history = []
        
        try:
            redis_client = await RedisClient.get_instance()
            
            # Get learner profile
            user_id = state.get("user_id")
            if user_id:
                profile_cache = LearnerProfileCache(redis_client)
                cached_profile = await profile_cache.get_profile(user_id)
                if cached_profile:
                    learner_profile = {**cached_profile, **learner_profile}
            
            # Get conversation history
            session_id = state.get("session_id", "")
            if session_id:
                conv_cache = ConversationCache(redis_client)
                conversation_history = await conv_cache.get_history(session_id)
            
        except Exception as e:
            logger.warning(f"Redis unavailable: {e}")
    
        latency_ms = int((time.time() - start_time) * 1000)
        
        return {
            "learner_profile": learner_profile,
            "conversation_history": conversation_history,
            "models_used": ["redis_cache"],
            "latency_ms": latency_ms,
        }
        
    except Exception as e:
        logger.error(f"[input_node] Error: {e}")
        return {"error": str(e)}


# ============================================================
# NODE 1.5: CACHE GATE (Response Cache Check)
# ============================================================

async def cache_gate_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    RAPID Risk-Aware Cache Gate (paper Alg. 1).

    Ternary decision:
      reuse  — ρ ≤ τ₀ and PCC-valid   → return cached response directly
      patch  — ρ ≤ τ₁ and PCC-patchable → delta-patch cached response
      full   — otherwise                → run full pipeline

    Cache key = MD5(normalized_input || level)
    Structured entry stores ⟨F, P_c, R, B, σ, t_c⟩
    """
    logger.info("[cache_gate_node] RAPID risk-aware cache check...")

    cache_policy = state.get("cache_policy", "on")
    if cache_policy != "on":
        return {
            "cache_hit": False,
            "cache_decision": "full",
            "reuse_risk": 1.0,
            "path": "slow",
        }

    user_input = state.get("user_input", "")
    level = state.get("learner_profile", {}).get("level", "B1")
    conversation_history = state.get("conversation_history", [])
    bucket = _build_graph_bucket(user_input, level, conversation_history)

    # Build lightweight fingerprint (pre-diagnosis: intent/root_concepts unknown)
    fingerprint = CacheFingerprint(
        query_norm=user_input.strip().lower(),
        intent="unknown",  # not yet diagnosed
        level=level,
        root_concepts=_extract_lightweight_graph_concepts(user_input),
        session_turn=len(conversation_history),
    )

    # Cache key (compatible with v1 scheme)
    normalized = user_input.strip().lower()
    cache_raw = f"{normalized}||{level}"
    cache_key = hashlib.md5(cache_raw.encode()).hexdigest()

    # --- Try in-process cache ---
    now = time.monotonic()
    entry = await _get_cache_entry(cache_key, level, now)
    if entry:
        rho = _compute_reuse_risk(fingerprint, entry, now)
        logger.info(f"[cache_gate_node] L0 HIT key={cache_key[:8]} ρ={rho:.3f}")

        if rho <= _TAU_REUSE:
            return {
                "cache_hit": True,
                "cache_decision": "reuse",
                "cache_layer": "L0",
                "cache_bucket": bucket,
                "reuse_risk": rho,
                "cache_fingerprint": fingerprint,
                "tutor_response": entry.get("response", ""),
                "strategy": (entry.get("execution_plan") or {}).get("strategy", "feedback"),
                "diagnosis_errors": entry.get("diagnosis_errors", []),
                "overall_score": entry.get("overall_score", 0.8),
                "path": "fast",
                "models_used": ["rapid_reuse_l0"],
            }
        elif rho <= _TAU_PATCH:
            patched = _patch_response(entry, fingerprint)
            return {
                "cache_hit": True,
                "cache_decision": "patch",
                "cache_layer": "L0",
                "cache_bucket": bucket,
                "reuse_risk": rho,
                "cache_fingerprint": fingerprint,
                "tutor_response": patched,
                "strategy": (entry.get("execution_plan") or {}).get("strategy", "feedback"),
                "diagnosis_errors": entry.get("diagnosis_errors", []),
                "overall_score": entry.get("overall_score", 0.8),
                "path": "fast",
                "models_used": ["rapid_patch_l0"],
            }

    # --- Try graph-bucket near-hit lookup (L1) ---
    candidate_keys = [item for item in await _get_bucket_candidate_keys(bucket) if item != cache_key]
    best_candidate: tuple[str, CacheEntry, float] | None = None
    for candidate_key in candidate_keys:
        candidate_entry = await _get_cache_entry(candidate_key, level, now)
        if not candidate_entry:
            continue
        rho = _compute_reuse_risk(fingerprint, candidate_entry, now)
        if rho > _TAU_PATCH:
            continue
        if best_candidate is None or rho < best_candidate[2]:
            best_candidate = (candidate_key, candidate_entry, rho)

    if best_candidate is not None:
        _, entry, rho = best_candidate
        logger.info(f"[cache_gate_node] L1 HIT bucket={bucket[:8]} ρ={rho:.3f}")
        if rho <= _TAU_REUSE:
            return {
                "cache_hit": True,
                "cache_decision": "reuse",
                "cache_layer": "L1",
                "cache_bucket": bucket,
                "reuse_risk": rho,
                "cache_fingerprint": fingerprint,
                "tutor_response": entry.get("response", ""),
                "strategy": (entry.get("execution_plan") or {}).get("strategy", "feedback"),
                "diagnosis_errors": entry.get("diagnosis_errors", []),
                "overall_score": entry.get("overall_score", 0.8),
                "path": "fast",
                "models_used": ["rapid_reuse_l1"],
            }
        patched = _patch_response(entry, fingerprint)
        return {
            "cache_hit": True,
            "cache_decision": "patch",
            "cache_layer": "L1",
            "cache_bucket": bucket,
            "reuse_risk": rho,
            "cache_fingerprint": fingerprint,
            "tutor_response": patched,
            "strategy": (entry.get("execution_plan") or {}).get("strategy", "feedback"),
            "diagnosis_errors": entry.get("diagnosis_errors", []),
            "overall_score": entry.get("overall_score", 0.8),
            "path": "fast",
            "models_used": ["rapid_patch_l1"],
        }

    logger.info(f"[cache_gate_node] Cache MISS for key {cache_key[:8]}...")
    return {
        "cache_hit": False,
        "cache_decision": "full",
        "cache_layer": "none",
        "cache_bucket": bucket,
        "reuse_risk": 1.0,
        "cache_fingerprint": fingerprint,
        "path": "slow",
    }


# ============================================================
# NODE 2: KNOWLEDGE GRAPH EXPANSION
# ============================================================

async def kg_expand_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Level-aware best-first KG expansion (paper Alg. 4).

    Phase 1: Seed concept matching (keyword + regex patterns)
    Phase 2: Best-first expansion with PedWeight priority queue
    """
    logger.info("[kg_expand_node] Expanding knowledge graph (best-first)...")
    start_time = time.time()

    try:
        from api.services.kg_service_v3 import get_kg_service

        kg = get_kg_service()
        learner_level = state.get("learner_profile", {}).get("level", "B1")

        # ── Phase 1: Seed concept matching ───────────────────────────
        user_text = state.get("user_input", "").lower()
        all_concepts = kg.get_concepts()

        seed_concepts = []
        for concept_id, meta in all_concepts.items():
            keywords = meta.get("keywords", "").lower()
            for kw in keywords.split():
                if kw in user_text or user_text in kw:
                    seed_concepts.append(concept_id)
                    break

        # Grammar error patterns (Phase 1b)
        grammar_patterns = {
            r"\bi goes\b": "concept:grammar.subject_verb_agreement",
            r"\bhe go\b": "concept:grammar.third_person_s",
            r"\byesterday\b.*\b(go|want|need)\b": "concept:grammar.past_time_markers",
            r"\bhave went\b": "concept:grammar.present_perfect",
            r"\bmore better\b": "concept:grammar.comparatives",
        }

        for pattern, concept in grammar_patterns.items():
            if re.search(pattern, user_text, re.IGNORECASE):
                if concept not in seed_concepts:
                    seed_concepts.append(concept)

        # ── Phase 2: Level-aware best-first expansion ────────────────
        expanded_nodes = []
        paths = []

        if seed_concepts:
            kg_result = await kg.expand_best_first(
                seed_nodes=seed_concepts,
                learner_level=learner_level,
                max_hops=2,
                max_nodes=10,
            )
            expanded_nodes = [
                {
                    "id": n.id,
                    "relation": n.properties.get("relation", n.type),
                    "title": n.properties.get("title", ""),
                    "keywords": n.properties.get("keywords", ""),
                }
                for n in kg_result.expanded_nodes
            ]
            paths = [
                {
                    "from_id": p.nodes[0] if len(p.nodes) > 0 else "",
                    "to_id": p.nodes[1] if len(p.nodes) > 1 else "",
                    "hops": len(p.edges),
                }
                for p in kg_result.paths
            ]

        latency_ms = int((time.time() - start_time) * 1000)
        logger.info(f"[kg_expand_node] Found {len(seed_concepts)} seed, {len(expanded_nodes)} expanded (level={learner_level})")

        return {
            "kg_seed_concepts": seed_concepts,
            "kg_expanded_nodes": expanded_nodes,
            "kg_paths": paths,
            "models_used": ["kuzu_kg_bestfirst"],
        }

    except Exception as e:
        logger.error(f"[kg_expand_node] Error: {e}")
        return {
            "kg_seed_concepts": [],
            "kg_expanded_nodes": [],
            "kg_paths": [],
        }


# ============================================================
# NODE 3: DIAGNOSIS (AI-POWERED via ModelGateway)
# ============================================================

async def diagnose_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Analyze user input for grammar, fluency, intent using AI.
    
    Uses ModelGateway to:
    - Load Qwen model on-demand (lazy loading)
    - Perform comprehensive grammar analysis
    - Detect intent (correct, explain, practice)
    - Map errors to KG concepts
    
    This is the FIRST node that uses AI models.
    """
    logger.info("[diagnose_node] Diagnosing input with AI...")
    start_time = time.time()
    
    user_text = state.get("user_input", "")
    learner_level = state.get("learner_profile", {}).get("level", "B1")

    if state.get("diagnosis_policy", "auto") == "rules":
        errors, root_causes = _rule_based_diagnosis(user_text)
        error_count = len(errors)
        confidence = 0.9 if error_count == 0 else (0.75 if error_count <= 2 else 0.65)
        grammar_score = 0.95 if error_count == 0 else 0.7
        fluency_score = 0.9 if error_count == 0 else 0.75
        return {
            "diagnosis_intent": "correct",
            "diagnosis_errors": errors,
            "diagnosis_root_causes": root_causes,
            "diagnosis_confidence": confidence,
            "grammar_score": grammar_score,
            "fluency_score": fluency_score,
            "models_used": ["rule_forced"],
        }
    
    try:
        gateway = await get_gateway()
        
        # Build diagnosis prompt
        diagnosis_prompt = f"""Analyze this English sentence from a {learner_level} level learner:

Sentence: "{user_text}"

Provide a JSON response with:
{{
    "errors": [
        {{
            "span": "the incorrect text",
            "type": "error_type (grammar, spelling, vocabulary, etc.)",
            "correction": "the correct text",
            "explanation": "brief explanation in simple English"
        }}
    ],
    "intent": "correct|explain|practice|ask",
    "fluency_score": 0.0-1.0,
    "grammar_score": 0.0-1.0,
    "confidence": 0.0-1.0
}}

If no errors, return empty errors array with high scores.
Be encouraging and focus on the most important errors first."""

        # Call Qwen via ModelGateway (lazy loads if needed)
        result = await gateway.execute_task(
            "chat",
            {
                "message": diagnosis_prompt,
                "system": "You are an English grammar analyzer. Return only valid JSON.",
                "max_tokens": 500,
            }
        )
        
        # Parse AI response
        errors: List[DiagnosisError] = []
        root_causes: List[str] = []
        intent = "correct"
        confidence = 0.9
        grammar_score = 0.8
        fluency_score = 0.8
        
        if result.get("success") and result.get("data"):
            try:
                ai_response = result["data"]
                if isinstance(ai_response, str):
                    # Extract JSON from response
                    json_match = re.search(r'\{[\s\S]*\}', ai_response)
                    if json_match:
                        ai_data = json.loads(json_match.group())
                    else:
                        ai_data = {}
                else:
                    ai_data = ai_response
                
                # Extract errors
                for err in ai_data.get("errors", []):
                    errors.append(DiagnosisError(
                        span=err.get("span", ""),
                        type=err.get("type", "unknown"),
                        correction=err.get("correction", ""),
                        explanation=err.get("explanation", ""),
                    ))
                    
                    # Map to KG concept
                    error_type = err.get("type", "").lower()
                    concept_map = {
                        "subject_verb_agreement": "concept:grammar.subject_verb_agreement",
                        "tense": "concept:grammar.tenses",
                        "article": "concept:grammar.articles",
                        "preposition": "concept:grammar.prepositions",
                        "plural": "concept:grammar.plural_nouns",
                    }
                    if error_type in concept_map:
                        root_causes.append(concept_map[error_type])
                
                intent = ai_data.get("intent", "correct")
                confidence = ai_data.get("confidence", 0.9)
                grammar_score = ai_data.get("grammar_score", 0.8)
                fluency_score = ai_data.get("fluency_score", 0.8)
                
            except (json.JSONDecodeError, TypeError) as e:
                logger.warning(f"[diagnose_node] Failed to parse AI response: {e}")
                # Fallback to rule-based
                errors, root_causes = _rule_based_diagnosis(user_text)
        else:
            # Fallback to rule-based if AI fails
            logger.warning("[diagnose_node] AI diagnosis failed, using rules")
            errors, root_causes = _rule_based_diagnosis(user_text)
        
        latency_ms = int((time.time() - start_time) * 1000)
        logger.info(f"[diagnose_node] Found {len(errors)} errors, intent={intent}, latency={latency_ms}ms")
        
        return {
            "diagnosis_intent": intent,
            "diagnosis_errors": errors,
            "diagnosis_root_causes": root_causes,
            "diagnosis_confidence": confidence,
            "grammar_score": grammar_score,
            "fluency_score": fluency_score,
            "models_used": ["qwen_grammar"],
        }
        
    except Exception as e:
        logger.error(f"[diagnose_node] Error: {e}")
        # Fallback
        errors, root_causes = _rule_based_diagnosis(user_text)
        return {
            "diagnosis_intent": "correct",
            "diagnosis_errors": errors,
            "diagnosis_root_causes": root_causes,
            "diagnosis_confidence": 0.5,
            "grammar_score": 0.7,
            "fluency_score": 0.7,
            "models_used": ["rule_fallback"],
        }


def _rule_based_diagnosis(text: str) -> tuple:
    """Fallback rule-based diagnosis when AI is unavailable"""
    errors = []
    root_causes = []
    
    rules = [
        (r"\bI goes\b", "subject_verb_agreement", "I go", "Use 'go' with 'I'"),
        (r"\bhe go\b", "third_person_s", "he goes", "Add -s for he/she/it"),
        (r"\bshe go\b", "third_person_s", "she goes", "Add -s for he/she/it"),
        (r"\byesterday I go\b", "past_tense", "yesterday I went", "Use past tense with yesterday"),
        (r"\bhave went\b", "present_perfect", "have gone", "Use past participle with have"),
        (r"\ba apple\b", "article", "an apple", "Use 'an' before vowels"),
    ]
    
    for pattern, err_type, correction, explanation in rules:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            errors.append(DiagnosisError(
                span=match.group(),
                type=err_type,
                correction=correction,
                explanation=explanation,
            ))
            root_causes.append(f"concept:grammar.{err_type}")
    
    return errors, root_causes


# ============================================================
# FUSION SCORING (paper Eq. 8: score(e) = α·s_kg + β·s_vec + γ·s_rec)
# ============================================================

_FUSION_ALPHA = 0.5   # KG structural relevance weight
_FUSION_BETA = 0.3    # Vector similarity weight
_FUSION_GAMMA = 0.2   # Recency bonus weight
_RECENCY_LAMBDA = 0.01  # Decay rate for recency bonus


def _fusion_score(
    kg_depth: int,
    vec_sim: float,
    last_used_turns_ago: int,
) -> float:
    """
    Compute fusion score for a retrieved evidence item (paper Eq. 8).

    s_kg  = 1 / (1 + depth)         — inverse hop distance
    s_vec = cosine similarity        — from MiniLM
    s_rec = exp(-λ · Δt)            — recency bonus
    """
    import math
    s_kg = 1.0 / (1.0 + kg_depth)
    s_vec = vec_sim
    s_rec = math.exp(-_RECENCY_LAMBDA * last_used_turns_ago)
    return _FUSION_ALPHA * s_kg + _FUSION_BETA * s_vec + _FUSION_GAMMA * s_rec


# ============================================================
# NODE 4: BUDGETED HYBRID RETRIEVAL (paper Alg. 5)
# ============================================================

async def retrieve_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Budgeted hybrid retrieval with fusion scoring (paper Alg. 5).

    Stage 1: Graph-local evidence (cheap) — KG concepts + diagnosis
    Stage 2: Optional vector evidence (budgeted) — MiniLM similarity
    Fusion:  score(e) = α·s_kg + β·s_vec + γ·s_rec  (Eq. 8)
    """
    logger.info("[retrieve_node] Budgeted hybrid retrieval...")
    start_time = time.time()

    retrieval_policy = state.get("retrieval_policy", "full")

    kg_concepts = state.get("kg_seed_concepts", [])
    kg_expanded = state.get("kg_expanded_nodes", [])
    session_turn = len(state.get("conversation_history", []))

    # ── Stage 1: Graph-local evidence (cheap) ────────────────────────
    # Each evidence item: {"text": ..., "kg_depth": ..., "vec_sim": ..., "turns_ago": ...}
    evidence_items: List[Dict[str, Any]] = []

    for concept_id in state.get("diagnosis_root_causes", []):
        evidence_items.append({
            "text": f"Grammar concept: {concept_id}",
            "kg_depth": 0,
            "vec_sim": 0.0,
            "turns_ago": 0,
        })

    for node in kg_expanded:
        depth = node.get("depth", 1) if isinstance(node, dict) else 1
        evidence_items.append({
            "text": f"Related: {node.get('id', '')} ({node.get('relation', '')})",
            "kg_depth": depth,
            "vec_sim": 0.0,
            "turns_ago": session_turn,
        })

    for error in state.get("diagnosis_errors", [])[:3]:
        evidence_items.append({
            "text": f"Error: '{error.get('span', '')}' → '{error.get('correction', '')}' — {error.get('explanation', '')}",
            "kg_depth": 0,
            "vec_sim": 0.0,
            "turns_ago": 0,
        })

    # ── Stage 2: Optional vector evidence (budgeted) ─────────────────
    vector_hits = []
    try:
        from api.services.model_gateway import get_gateway

        gateway = await get_gateway()

        errors = state.get("diagnosis_errors", [])
        confidence = float(state.get("diagnosis_confidence", 0.0) or 0.0)

        do_vector_search = True
        max_expanded = 10
        max_hits = 5
        threshold = 0.3

        if retrieval_policy == "rapid":
            if len(errors) == 0 and confidence >= 0.8:
                do_vector_search = False
            elif len(errors) <= 2 and confidence >= 0.7:
                max_expanded = 5
                max_hits = 2
                threshold = 0.35

        if do_vector_search:
            candidate_labels = []
            for c in kg_concepts:
                if isinstance(c, dict):
                    candidate_labels.append(c.get("id", "") + " " + c.get("label", ""))
                else:
                    candidate_labels.append(str(c))
            for node in kg_expanded[:max_expanded]:
                label = node.get("id", "") + " " + node.get("label", node.get("relation", ""))
                if label.strip() and label not in candidate_labels:
                    candidate_labels.append(label)

            if candidate_labels:
                user_input = state.get("user_input", "")
                result = await gateway.invoke(
                    "minilm", "invoke",
                    {"task": "similarity", "query": user_input, "candidates": candidate_labels},
                )
                if result.get("success"):
                    sim_results = result.get("data", {}).get("results", [])
                    for r in sim_results:
                        if r["score"] >= threshold:
                            vector_hits.append({"text": r["text"], "score": r["score"]})
                            evidence_items.append({
                                "text": f"Semantic match: {r['text']}",
                                "kg_depth": 2,  # treat vector hits as depth-2
                                "vec_sim": r["score"],
                                "turns_ago": session_turn,
                            })

                    vector_hits = vector_hits[:max_hits]
                    logger.info(f"[retrieve_node] MiniLM found {len(vector_hits)} semantic hits")
    except Exception as e:
        logger.warning(f"[retrieve_node] Vector search skipped: {e}")

    # ── Fusion scoring and ranking ───────────────────────────────────
    for item in evidence_items:
        item["fusion_score"] = _fusion_score(
            kg_depth=item["kg_depth"],
            vec_sim=item["vec_sim"],
            last_used_turns_ago=item["turns_ago"],
        )

    evidence_items.sort(key=lambda x: x["fusion_score"], reverse=True)
    top_evidence = evidence_items[:5]  # budget: top-5

    context_parts = [item["text"] for item in top_evidence]
    retrieved_context = "\n".join(context_parts) if context_parts else ""

    latency_ms = int((time.time() - start_time) * 1000)
    logger.info(f"[retrieve_node] {len(evidence_items)} candidates → top {len(top_evidence)} via fusion scoring")

    return {
        "vector_hits": vector_hits,
        "retrieved_context": retrieved_context,
        "models_used": ["retrieval_fusion"] + (["minilm"] if vector_hits else []),
    }


# ============================================================
# NODE 5: GROUNDED GENERATION (LLM call with context)
# ============================================================

async def generate_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Generate the tutor response using LLM grounded in KG evidence.
    
    This node calls the LLM fallback chain (Groq → Gemini → Ollama)
    with the Lexi persona, KG context, and diagnosis data injected
    into the system prompt. This is the SINGLE place where LLM
    generation happens — callers should NOT make a separate LLM call.
    """
    logger.info("[generate_node] Generating grounded tutor response...")
    start_time = time.time()
    
    errors = state.get("diagnosis_errors", [])
    intent = state.get("diagnosis_intent", "correct")
    level = state.get("learner_profile", {}).get("level", "B1")
    user_input = state.get("user_input", "")
    context = state.get("retrieved_context", "")
    vietnamese_hint = state.get("vietnamese_hint")
    
    # Determine strategy (paper Eq. strategy)
    error_count = len(errors)
    fluency_score = state.get("fluency_score", 0.8)

    if intent == "explain" and fluency_score > 0.7:
        strategy = "socratic"
    elif error_count == 0:
        strategy = "praise"
    elif error_count <= 2:
        strategy = "feedback"
    else:
        strategy = "scaffold"

    generation_policy = state.get("generation_policy", "auto")
    if generation_policy == "template":
        response = _generate_template_response(errors, strategy, user_input)
        model_used = "template_forced"

        if strategy == "socratic":
            next_action = "ask"
        elif error_count == 0:
            next_action = "continue"
        elif error_count <= 2:
            next_action = "hint"
        else:
            next_action = "correct"

        grammar_score = state.get("grammar_score", 0.8)
        fluency_score = state.get("fluency_score", 0.8)
        overall_score = (grammar_score * 0.6 + fluency_score * 0.4)

        # Store response in cache even when generation is forced to template.
        # This keeps benchmark runs deterministic while still measuring cache wins.
        if state.get("cache_policy", "on") == "on":
            try:
                await _write_cache_entry(state, response, strategy, errors, overall_score, context)
            except Exception as e:
                logger.debug(f"[generate_node] Cache write failed: {e}")

        latency_ms = int((time.time() - start_time) * 1000)
        logger.info(f"[generate_node] Generated response via {model_used} in {latency_ms}ms")

        return {
            "tutor_response": response,
            "strategy": strategy,
            "next_action": next_action,
            "overall_score": overall_score,
            "models_used": [model_used],
        }
    
    # Build system prompt with Lexi persona + grounded context
    system_prompt = (
        "You are Lexi 🦜, a cheerful, witty parrot who is an expert English tutor.\n"
        "You speak in a warm, encouraging tone — like a fun game character guiding an adventure.\n"
        "Keep responses concise (2-4 sentences). Use the knowledge context provided.\n"
        "Gently correct mistakes with encouraging context.\n"
        f"The learner's current CEFR level is: {level}\n"
    )
    
    if context:
        system_prompt += f"\n--- Knowledge Graph Context ---\n{context}\n"
    
    if strategy == "socratic":
        system_prompt += (
            "\nStrategy: SOCRATIC. The learner asked for an explanation and is fairly fluent.\n"
            "Guide them through a chain of short questions so they discover the answer themselves.\n"
            "Do NOT give the answer directly — instead ask 1-2 leading questions.\n"
        )
        if errors:
            errors_text = "\n".join([
                f"- '{e.get('span','')}' → '{e.get('correction','')}' ({e.get('explanation','')})"
                for e in errors[:3]
            ])
            system_prompt += f"\n--- Errors Found (use as hints, don't reveal directly) ---\n{errors_text}\n"
    elif errors:
        errors_text = "\n".join([
            f"- '{e.get('span','')}' → '{e.get('correction','')}' ({e.get('explanation','')})"
            for e in errors[:3]
        ])
        system_prompt += f"\n--- Errors Found ---\n{errors_text}\n"
        system_prompt += f"Strategy: {strategy}. Weave corrections naturally into your response.\n"
    else:
        system_prompt += "\nNo errors found — praise the learner's effort!\n"
    
    if vietnamese_hint:
        system_prompt += f"\n--- Vietnamese Hint (for reference) ---\n{vietnamese_hint}\n"
    
    # Call LLM via fallback chain (Groq → Gemini → Ollama)
    response = ""
    model_used = "template_fallback"
    
    try:
        import os
        import httpx
        
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_input},
        ]
        
        # 1. Try Groq
        groq_key = os.getenv("GROQ_API_KEY", "")
        groq_model = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
        if groq_key:
            try:
                async with httpx.AsyncClient(timeout=30.0) as client:
                    resp = await client.post(
                        "https://api.groq.com/openai/v1/chat/completions",
                        headers={"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"},
                        json={"model": groq_model, "messages": messages, "max_tokens": 512, "temperature": 0.7},
                    )
                    if resp.status_code == 200:
                        response = resp.json()["choices"][0]["message"]["content"]
                        model_used = f"groq/{groq_model}"
            except Exception as e:
                logger.warning(f"[generate_node] Groq failed: {e}")
        
        # 2. Try Gemini
        if not response:
            gemini_key = os.getenv("GEMINI_API_KEY", "")
            if gemini_key:
                try:
                    gemini_contents = [{"role": "user", "parts": [{"text": user_input}]}]
                    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={gemini_key}"
                    request_body = {
                        "contents": gemini_contents,
                        "systemInstruction": {"parts": [{"text": system_prompt}]},
                    }
                    async with httpx.AsyncClient(timeout=30.0) as client:
                        resp = await client.post(url, json=request_body)
                        if resp.status_code == 200:
                            candidates = resp.json().get("candidates", [])
                            if candidates:
                                response = candidates[0]["content"]["parts"][0]["text"]
                                model_used = "gemini-2.0-flash"
                except Exception as e:
                    logger.warning(f"[generate_node] Gemini failed: {e}")
        
        # 3. Try Ollama
        if not response:
            ollama_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
            ollama_model = os.getenv("OLLAMA_MODEL", "qwen3:4b")
            try:
                async with httpx.AsyncClient(timeout=60.0) as client:
                    resp = await client.post(
                        f"{ollama_url}/api/chat",
                        json={"model": ollama_model, "messages": messages, "stream": False,
                              "options": {"num_predict": 256, "temperature": 0.7}},
                    )
                    if resp.status_code == 200:
                        response = resp.json().get("message", {}).get("content", "")
                        model_used = f"ollama/{ollama_model}"
            except Exception as e:
                logger.warning(f"[generate_node] Ollama failed: {e}")
    
    except Exception as e:
        logger.error(f"[generate_node] LLM chain error: {e}")
    
    # 4. Template fallback
    if not response:
        response = _generate_template_response(errors, strategy, user_input)
        model_used = "template_fallback"
    
    # Determine next action
    if strategy == "socratic":
        next_action = "ask"
    elif error_count == 0:
        next_action = "continue"
    elif error_count <= 2:
        next_action = "hint"
    else:
        next_action = "correct"
    
    # Calculate overall score
    grammar_score = state.get("grammar_score", 0.8)
    fluency_score = state.get("fluency_score", 0.8)
    overall_score = (grammar_score * 0.6 + fluency_score * 0.4)
    
    # Store response in Redis cache for future hits
    if state.get("cache_policy", "on") == "on":
        try:
            await _write_cache_entry(state, response, strategy, errors, overall_score, context)
        except Exception as e:
            logger.debug(f"[generate_node] Cache write failed: {e}")
    
    latency_ms = int((time.time() - start_time) * 1000)
    logger.info(f"[generate_node] Generated response via {model_used} in {latency_ms}ms")
    
    return {
        "tutor_response": response,
        "strategy": strategy,
        "next_action": next_action,
        "overall_score": overall_score,
        "models_used": [model_used],
    }


def _generate_template_response(errors: list, strategy: str, user_input: str) -> str:
    """Fallback template response when AI is unavailable"""
    if strategy == "praise":
        return "Great job! Your sentence is grammatically correct. Keep up the excellent work! 🎉"
    elif strategy == "socratic":
        if errors:
            error = errors[0]
            return (
                f"Interesting sentence! Let me ask you something: look at '{error.get('span', '')}' "
                f"— can you think of another way to phrase that? What rule might apply here? 🤔"
            )
        return "Good question! Before I explain, what do you already know about this topic? 🤔"
    elif errors:
        error = errors[0]
        corrected = user_input.replace(error.get("span", ""), error.get("correction", ""))
        return (
            f"Good effort! I noticed a small issue: '{error.get('span', '')}' should be "
            f"'{error.get('correction', '')}'. {error.get('explanation', '')}. "
            f"Try saying: \"{corrected}\" 💪"
        )
    else:
        return "Good attempt! Let me help you improve that sentence."


# ============================================================
# NODE 6: VIETNAMESE EXPLANATION (AI-POWERED, Lazy Load)
# ============================================================

async def vietnamese_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Generate Vietnamese explanation for beginners using AI.
    
    Uses ModelGateway to:
    - Load LLaMA-VI only when needed (lazy loading)
    - Generate natural Vietnamese explanations
    - Auto-unload after idle timeout
    
    Only called when:
    - Level is A1/A2
    - Confidence is low
    - Complex grammar detected
    """
    logger.info("[vietnamese_node] Generating Vietnamese explanation...")
    start_time = time.time()
    
    errors = state.get("diagnosis_errors", [])
    level = state.get("learner_profile", {}).get("level", "B1")
    tutor_response = state.get("tutor_response", "")
    
    try:
        gateway = await get_gateway()
        
        # Build Vietnamese explanation prompt
        if errors:
            error = errors[0]
            vi_prompt = f"""Giải thích ngắn gọn lỗi ngữ pháp sau cho học sinh Việt Nam trình độ {level}:

Lỗi: "{error.get('span', '')}" → "{error.get('correction', '')}"
Loại lỗi: {error.get('type', 'unknown')}
Giải thích tiếng Anh: {error.get('explanation', '')}

Yêu cầu:
1. Giải thích bằng tiếng Việt dễ hiểu
2. Cho ví dụ minh họa
3. Mẹo ghi nhớ nếu có
4. Tối đa 2-3 câu"""
        else:
            vi_prompt = f"Khen ngợi học sinh bằng tiếng Việt vì họ đã viết đúng ngữ pháp. Tối đa 1-2 câu."
        
        # Use Qwen with Vietnamese system prompt (llama_vi is not registered)
        result = await gateway.execute_task(
            "chat",
            {
                "message": vi_prompt,
                "system": "You are a Vietnamese language teacher. Respond in Vietnamese only.",
                "max_tokens": 200,
            }
        )
        
        if result.get("success") and result.get("data"):
            vietnamese_hint = result["data"]
            if isinstance(vietnamese_hint, dict):
                vietnamese_hint = vietnamese_hint.get("text", vietnamese_hint.get("response", ""))
        else:
            # Fallback to predefined explanations
            vietnamese_hint = _get_predefined_vietnamese(errors)
        
        latency_ms = int((time.time() - start_time) * 1000)
        
        return {
            "vietnamese_hint": vietnamese_hint,
            "models_used": ["qwen_vietnamese"],
        }
        
    except Exception as e:
        logger.error(f"[vietnamese_node] Error: {e}")
        vietnamese_hint = _get_predefined_vietnamese(errors)
        return {
            "vietnamese_hint": vietnamese_hint,
            "models_used": ["vietnamese_fallback"],
        }


def _get_predefined_vietnamese(errors: list) -> str:
    """Fallback predefined Vietnamese explanations"""
    if not errors:
        return "Câu của bạn rất tốt! Tiếp tục cố gắng nhé! 🌟"
    
    error_type = errors[0].get("type", "").lower()
    explanations = {
        "subject_verb_agreement": "Trong tiếng Anh, động từ phải hòa hợp với chủ ngữ. Với 'I/you/we/they' dùng động từ nguyên mẫu, với 'he/she/it' thêm -s hoặc -es.",
        "third_person_s": "Với chủ ngữ ngôi thứ 3 số ít (he, she, it), động từ cần thêm -s hoặc -es. Ví dụ: He goes, She works.",
        "past_tense": "Khi nói về quá khứ (yesterday, last week...), cần dùng thì quá khứ đơn. Động từ bất quy tắc cần học thuộc!",
        "present_perfect": "Thì hiện tại hoàn thành dùng: have/has + past participle. Ví dụ: have gone, has eaten.",
        "article": "Dùng 'a' trước phụ âm, 'an' trước nguyên âm (a, e, i, o, u). Ví dụ: a book, an apple.",
    }
    
    return explanations.get(error_type, "Hãy chú ý quy tắc ngữ pháp này nhé!")


# ============================================================
# NODE 7: TEXT-TO-SPEECH (AI-POWERED via ModelGateway)
# ============================================================

async def tts_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Convert tutor response to speech using TTS model.
    
    Uses ModelGateway to:
    - Load Piper TTS only when audio is requested
    - Generate natural speech
    - Auto-unload after idle timeout
    """
    logger.info("[tts_node] Generating speech...")
    start_time = time.time()
    
    tutor_response = state.get("tutor_response", "")
    if not tutor_response:
        return {"tts_audio_bytes": None, "tts_audio_url": None}
    
    try:
        gateway = await get_gateway()
        
        # Clean response for TTS (remove emojis, etc.)
        clean_text = re.sub(r'[^\w\s.,!?\'-]', '', tutor_response)
        clean_text = clean_text[:500]  # Limit length
        
        # Call Piper TTS via ModelGateway
        result = await gateway.execute_task(
            "tts",
            {
                "text": clean_text,
                "voice_id": "en_US-lessac-medium",
                "speed": 0.9,  # Slightly slower for learners
            }
        )
        
        if result.get("success") and result.get("data"):
            audio_data = result["data"]
            audio_bytes = audio_data.get("audio_bytes")
            
            latency_ms = int((time.time() - start_time) * 1000)
            
            return {
                "tts_audio_bytes": audio_bytes,
                "tts_duration_ms": audio_data.get("duration", 0) * 1000,
                "models_used": ["piper_tts"],
            }
        else:
            return {"tts_audio_bytes": None, "tts_audio_url": None}
        
    except Exception as e:
        logger.warning(f"[tts_node] TTS failed: {e}")
        return {
            "tts_audio_bytes": None,
            "tts_audio_url": None,
        }


# ============================================================
# NODE 8: ASK CLARIFICATION (Low Confidence Path)
# ============================================================

async def ask_clarify_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Generate clarification question when confidence is low.
    
    Uses AI for more natural clarification questions.
    """
    logger.info("[ask_clarify_node] Generating clarification question...")
    start_time = time.time()
    
    user_input = state.get("user_input", "")
    level = state.get("learner_profile", {}).get("level", "B1")
    
    try:
        gateway = await get_gateway()
        
        clarify_prompt = f"""A {level} level English learner said: "{user_input}"

I'm not sure what they need. Generate a friendly clarification question asking if they want:
1. Grammar correction
2. Explanation of a rule  
3. Practice exercises

Keep it short and friendly (1-2 sentences)."""

        result = await gateway.execute_task(
            "chat",
            {
                "message": clarify_prompt,
                "max_tokens": 100,
            }
        )
        
        if result.get("success") and result.get("data"):
            response = result["data"]
            if isinstance(response, dict):
                response = response.get("text", response.get("response", ""))
        else:
            response = (
                "I'm not quite sure what you need. Would you like me to:\n"
                "1. Correct your sentence\n"
                "2. Explain the grammar rule\n"
                "3. Create a practice exercise\n"
                "Please let me know!"
            )
        
        vietnamese_hint = "Mình cần thêm thông tin: bạn muốn sửa câu, giải thích ngữ pháp, hay tạo bài tập?"
        
        return {
            "tutor_response": response,
            "vietnamese_hint": vietnamese_hint,
            "strategy": "ask",
            "next_action": "ask",
            "path": "fast",
            "models_used": ["qwen_clarify"],
        }
        
    except Exception as e:
        logger.error(f"[ask_clarify_node] Error: {e}")
        return {
            "tutor_response": "Could you please clarify what you'd like help with?",
            "vietnamese_hint": "Bạn muốn được giúp đỡ điều gì ạ?",
            "strategy": "ask",
            "next_action": "ask",
            "path": "fast",
            "models_used": ["template_fallback"],
        }


# ============================================================
# NODE 9: PRONUNCIATION ANALYSIS (Optional, Heavy Model)
# ============================================================

async def pronunciation_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Analyze pronunciation from audio input.
    
    Uses ModelGateway to:
    - Load HuBERT only when audio analysis is requested
    - Perform phoneme-level analysis
    - Auto-unload quickly (LOW priority) to save RAM
    
    Only called when:
    - Input type is "voice"
    - User explicitly asks for pronunciation feedback
    """
    logger.info("[pronunciation_node] Analyzing pronunciation...")
    start_time = time.time()
    
    audio_bytes = state.get("audio_bytes")
    reference_text = state.get("user_input", "")
    
    if not audio_bytes:
        return {"pronunciation_score": None, "phoneme_errors": []}
    
    try:
        gateway = await get_gateway()
        
        # Call HuBERT via ModelGateway (lazy loads, auto-unloads quickly)
        result = await gateway.execute_task(
            "pronunciation",
            {
                "audio_bytes": audio_bytes,
                "reference_text": reference_text,
                "return_phonemes": True,
            }
        )
        
        if result.get("success") and result.get("data"):
            pron_data = result["data"]
            
            latency_ms = int((time.time() - start_time) * 1000)
            
            return {
                "pronunciation_score": pron_data.get("overall_score", 0.0),
                "phoneme_errors": pron_data.get("errors", []),
                "pronunciation_tip": pron_data.get("tip", ""),
                "models_used": ["hubert_pronunciation"],
            }
        else:
            return {"pronunciation_score": None, "phoneme_errors": []}
        
    except Exception as e:
        logger.warning(f"[pronunciation_node] Error: {e}")
        return {
            "pronunciation_score": None,
            "phoneme_errors": [],
        }


# ============================================================
# NODE 10: STT NODE (Speech-to-Text for Voice Input)
# ============================================================

async def stt_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Convert speech to text for voice input.
    
    Uses ModelGateway to:
    - Load Whisper on-demand
    - Transcribe audio with word timestamps
    - Support pronunciation analysis pipeline
    """
    logger.info("[stt_node] Transcribing audio...")
    start_time = time.time()
    
    audio_bytes = state.get("audio_bytes")
    
    if not audio_bytes:
        return {"transcribed_text": None}
    
    try:
        gateway = await get_gateway()
        
        # Call Whisper via ModelGateway
        result = await gateway.execute_task(
            "stt",
            {
                "audio_bytes": audio_bytes,
                "language": "en",
                "return_timestamps": True,
            }
        )
        
        if result.get("success") and result.get("data"):
            stt_data = result["data"]
            
            latency_ms = int((time.time() - start_time) * 1000)
            
            return {
                "transcribed_text": stt_data.get("text", ""),
                "word_timestamps": stt_data.get("segments", []),
                "stt_confidence": stt_data.get("confidence", 0.0),
                "models_used": ["whisper_stt"],
            }
        else:
            return {"transcribed_text": None}
        
    except Exception as e:
        logger.warning(f"[stt_node] Error: {e}")
        return {"transcribed_text": None}
