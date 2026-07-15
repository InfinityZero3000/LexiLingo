"""
PCC Risk-Aware Cache Gate — risk scoring, bucket management, and cache_gate_node.

Implements the RAPID cache algorithm (paper §4.1):
  L0  — exact cache key match with risk score
  L1  — graph-bucket near-hit with SCAR-L1 certificate
  write — structured CacheEntry with PCC-stable promotion

Public node entry-point:
  cache_gate_node  — ternary decision: reuse / patch / full
  _write_cache_entry — write a CacheEntry to in-process + Redis caches
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import logging
import re
import time
from dataclasses import replace
from typing import Any, Dict, Mapping, Optional, Sequence

from api.services.trace_cag.state import (
    TraceCAGState, CacheFingerprint, CacheEntry, BucketVersionRecord,
    CacheAdmissibilityCertificate,
)
from api.core.config import settings
from api.services.trace_cag.l1_state_cache import (
    BASE_REQUIRED_DIMENSIONS,
    CERTIFICATE_SCHEMA_VERSION,
    L1Candidate,
    L1Request,
    decide_l1_reuse,
)
from api.services.trace_cag.env_helpers import _env_float
from api.services.trace_cag.kg_utils import _cefr_distance

logger = logging.getLogger(__name__)

# ============================================================
# PCC RISK SCORING (paper §4.1, Eq. 2)
# ============================================================

# Reuse-risk weights (tunable, sum to ~1.0)
_W_INTENT = _env_float("TRACECAG_PCC_W_INTENT", 0.30)      # w1: intent mismatch (0/1)
_W_CONCEPT = _env_float("TRACECAG_PCC_W_CONCEPT", 0.25)    # w2: concept drift (1-Jaccard)
_W_LEVEL = _env_float("TRACECAG_PCC_W_LEVEL", 0.20)        # w3: normalized level drift
_W_PROGRESS = _env_float("TRACECAG_PCC_W_PROGRESS", 0.10)  # w4: profile progress drift
_W_STALENESS = _env_float("TRACECAG_PCC_W_STALENESS", 0.15)  # w5: staleness ratio

# Thresholds for ternary decision
_TAU_REUSE = _env_float("TRACECAG_PCC_TAU_REUSE", 0.25)  # τ₀: max risk for direct reuse
_TAU_PATCH = _env_float("TRACECAG_PCC_TAU_PATCH", 0.55)  # τ₁: max risk for delta patching

# L1 ranking weights (paper-inspired: risk + overlap + recency)
_L1_RISK_WEIGHT = _env_float("TRACECAG_L1_RISK_WEIGHT", 1.0)
_L1_OVERLAP_WEIGHT = _env_float("TRACECAG_L1_OVERLAP_WEIGHT", 0.5)
_L1_RECENCY_WEIGHT = _env_float("TRACECAG_L1_RECENCY_WEIGHT", 0.3)
_L1_RECENCY_LAMBDA = _env_float("TRACECAG_L1_RECENCY_LAMBDA", 0.10)


def _is_exact_reuse_match(fingerprint: CacheFingerprint, entry: CacheEntry) -> bool:
    cached_fingerprint = entry.get("fingerprint") or {}
    if fingerprint.get("query_norm") != cached_fingerprint.get("query_norm"):
        return False
    if fingerprint.get("level") != cached_fingerprint.get("level"):
        return False

    cur_lang = fingerprint.get("native_language")
    cached_lang = cached_fingerprint.get("native_language")
    if cur_lang and cached_lang and cur_lang != cached_lang:
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
    # A cached response generated for a different native language can't be
    # reused or patched — the hint/explanation text is in the wrong language
    # regardless of how close the grammar/intent/level match is.
    cached_fp = entry.get("fingerprint") or {}
    cur_lang = fingerprint.get("native_language")
    cached_lang = cached_fp.get("native_language")
    if cur_lang and cached_lang and cur_lang != cached_lang:
        return 1.0

    # Compare intents fingerprint-to-fingerprint: both sides are built with the
    # same pre-diagnosis extractor. execution_plan.intent is diagnosis-stage
    # vocabulary and would read as drift even for identical queries.
    cur_intent = fingerprint.get("intent", "unknown")
    cached_intent = cached_fp.get("intent") or (entry.get("execution_plan") or {}).get("intent", "unknown")
    if cur_intent == "unknown" or cached_intent == "unknown":
        delta_i = 0.0
    else:
        delta_i = 0.0 if cur_intent == cached_intent else 1.0

    cur_concepts = set(fingerprint.get("root_concepts") or [])
    cached_concepts = set((entry.get("fingerprint") or {}).get("root_concepts") or [])
    if not cur_concepts or not cached_concepts:
        # Missing concepts on either side means "no evidence", not max drift —
        # mirrors the unknown-intent handling for ΔI above.
        delta_c = 0.0
    else:
        jaccard = len(cur_concepts & cached_concepts) / max(len(cur_concepts | cached_concepts), 1)
        delta_c = 1.0 - jaccard

    cur_level = fingerprint.get("level", "B1")
    cached_level = (entry.get("fingerprint") or {}).get("level", "B1")
    delta_l = _cefr_distance(cur_level, cached_level) / 5.0  # max distance = 5

    cur_turn = fingerprint.get("session_turn", 0)
    cached_turn = (entry.get("fingerprint") or {}).get("session_turn", 0)
    delta_prog = min(abs(cur_turn - cached_turn) / 10.0, 1.0)

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

    # Round to keep float artifacts (e.g. 0.25000000000000006) from leaking
    # across the τ decision boundaries.
    return round(max(0.0, min(1.0, rho)), 6)


def _build_fingerprint(state: TraceCAGState) -> CacheFingerprint:
    """Build a cache fingerprint from current pipeline state.

    root_concepts MUST use the same extractor as the gate-side fingerprint in
    cache_gate_node (pre-diagnosis lightweight concepts); otherwise the stored
    and requested concept sets live in different vocabularies and ΔC in
    _compute_reuse_risk reads as max drift even for identical queries.
    """
    return CacheFingerprint(
        query_norm=state.get("user_input", "").strip().lower(),
        intent=_infer_intent_pre_diagnosis(state.get("user_input", "")),
        level=state.get("learner_profile", {}).get("level", "B1"),
        native_language=state.get("learner_profile", {}).get("native_language", "Vietnamese"),
        root_concepts=_extract_lightweight_graph_concepts(state.get("user_input", "")),
        session_turn=len(state.get("conversation_history", [])),
    )


def _build_admissibility_certificate(
    *,
    state: TraceCAGState,
    fingerprint: CacheFingerprint,
    profile_epoch: int,
    state_hints: Mapping[str, Any],
    now: float,
) -> CacheAdmissibilityCertificate:
    """Build the reusable artifact contract checked before cache reuse."""
    retrieval_meta = state.get("retrieval_meta") or {}
    # Store concepts in the same signature space used by the request-side
    # verifier.  Mixing lightweight fingerprint tokens with the richer L1
    # signature made identical requests fail the concept-overlap hard gate.
    concepts = state_hints.get("concepts") or _l1_signature_concepts(
        state.get("user_input", ""), fingerprint
    )
    relation_path = state_hints.get("relation_path")
    if not relation_path:
        relation_hints = _canonical_relation_hints(state.get("user_input", ""))
        relation_path = next(iter(relation_hints), "")

    required_dimensions = set(BASE_REQUIRED_DIMENSIONS)
    dependencies = {
        "evidence_hash": state_hints.get("evidence_hash") or retrieval_meta.get("evidence_hash"),
        "source_version": state_hints.get("source_version") or retrieval_meta.get("source_version"),
        "freshness_class": state_hints.get("freshness_class") or retrieval_meta.get("freshness_class"),
        "relation_path": relation_path,
        "native_language": fingerprint.get("native_language"),
    }
    required_dimensions.update(name for name, value in dependencies.items() if value not in (None, "", [], set()))

    return CacheAdmissibilityCertificate(
        schema_version=CERTIFICATE_SCHEMA_VERSION,
        required_dimensions=sorted(required_dimensions),
        query_norm=str(fingerprint.get("query_norm") or ""),
        intent=str(state_hints.get("intent") or fingerprint.get("intent") or ""),
        level=str(fingerprint.get("level") or ""),
        native_language=str(fingerprint.get("native_language") or ""),
        profile_epoch=_hint_profile_epoch(state_hints, profile_epoch),
        policy_version=str(state_hints.get("policy_version") or f"policy_v{_POLICY_VERSION}"),
        kg_version=str(state_hints.get("kg_version") or f"kg_schema_v{_GRAPH_SCHEMA_VERSION}"),
        evidence_hash=str(state_hints.get("evidence_hash") or retrieval_meta.get("evidence_hash") or ""),
        source_version=str(state_hints.get("source_version") or retrieval_meta.get("source_version") or ""),
        freshness_class=str(state_hints.get("freshness_class") or retrieval_meta.get("freshness_class") or ""),
        answer_target=str(state_hints.get("answer_target") or _answer_target_hint(state.get("user_input", ""))),
        relation_path=str(relation_path or ""),
        concepts=[str(item) for item in concepts],
        graph_fingerprint=str(state_hints.get("graph_fingerprint") or retrieval_meta.get("graph_fingerprint") or ""),
        patchable_slots=[str(item) for item in (state_hints.get("patchable_slots") or [])],
        created_at=now,
    )


def _certificate_from_entry(entry: CacheEntry) -> Mapping[str, Any]:
    cert = entry.get("admissibility_certificate") or {}
    if cert:
        return cert
    fp = entry.get("fingerprint") or {}
    execution_plan = entry.get("execution_plan") or {}
    state_hints = execution_plan.get("benchmark_state") or {}
    return {
        "schema_version": 1,
        "required_dimensions": [],
        "query_norm": fp.get("query_norm") or "",
        "intent": state_hints.get("intent") or fp.get("intent") or "",
        "level": fp.get("level") or "",
        "native_language": fp.get("native_language") or "",
        "profile_epoch": _hint_profile_epoch(state_hints, 0),
        "policy_version": state_hints.get("policy_version") or "",
        "kg_version": state_hints.get("kg_version") or "",
        "evidence_hash": state_hints.get("evidence_hash") or _evidence_dependency_hash(entry),
        "source_version": state_hints.get("source_version") or "",
        "freshness_class": state_hints.get("freshness_class") or "",
        "answer_target": state_hints.get("answer_target") or "",
        "relation_path": state_hints.get("relation_path") or "",
        "concepts": state_hints.get("concepts") or fp.get("root_concepts") or [],
    }


def _l1_signature_concepts(user_input: str, fingerprint: Mapping[str, Any]) -> set[str]:
    raw_concepts = {str(concept) for concept in (fingerprint.get("root_concepts") or [])}
    concepts = {concept for concept in raw_concepts if not concept.startswith("token:")}
    concepts.update(f"entity:{entity}" for entity in _extract_l1_entities(user_input))
    if not concepts:
        concepts.update(raw_concepts)
    return {str(concept) for concept in concepts if str(concept).strip()}


def _evidence_dependency_hash(entry: CacheEntry) -> str:
    parts: list[str] = []
    for item in entry.get("retrieval_trace") or []:
        if isinstance(item, dict):
            item_id = str(item.get("item_id") or "")
            title = str(item.get("title") or "")
            if item_id or title:
                parts.append(f"{item_id}:{title}")
    if not parts:
        for item in entry.get("evidence_bundle") or []:
            if isinstance(item, dict):
                content = str(item.get("content") or "")
                if content:
                    parts.append(content[:120])
    if not parts:
        return ""
    material = "|".join(sorted(parts))
    return hashlib.md5(material.encode()).hexdigest()


def _build_l1_request_signature(
    *,
    user_input: str,
    normalized: str,
    fingerprint: CacheFingerprint,
    level: str,
    intent_hint: str,
    profile_epoch: int,
    conversation_history: list[dict[str, Any]],
    state_hints: Mapping[str, Any] | None = None,
) -> L1Request:
    hints = state_hints or {}
    # Certificates store one deterministic coarse relation path.  Compare the
    # request in the same representation; otherwise an identical query with
    # multiple lexical cues (e.g. author + time_order) rejects its own entry.
    primary_relation = _canonical_relation_hints(user_input)
    required_dimensions = set(BASE_REQUIRED_DIMENSIONS)
    required_dimensions.update(
        name for name, value in {
            "evidence_hash": hints.get("evidence_hash"),
            "source_version": hints.get("source_version"),
            "freshness_class": hints.get("freshness_class"),
            "relation_path": hints.get("relation_path") or primary_relation,
            "native_language": fingerprint.get("native_language"),
        }.items() if value not in (None, "", [], set())
    )
    request = L1Request(
        query_norm=normalized,
        intent=intent_hint,
        level=level,
        profile_epoch=profile_epoch,
        session_turn=len(conversation_history),
        concepts=_l1_signature_concepts(user_input, fingerprint),
        entities=_extract_l1_entities(user_input),
        answer_target=_answer_target_hint(user_input),
        relation_hints=primary_relation,
        evidence_hash="",
        policy_version=f"policy_v{_POLICY_VERSION}",
        kg_version=f"kg_schema_v{_GRAPH_SCHEMA_VERSION}",
        source_version="",
        freshness_class="",
        native_language=str(fingerprint.get("native_language") or ""),
        schema_version=CERTIFICATE_SCHEMA_VERSION,
        required_dimensions=required_dimensions,
    )
    return replace(
        request,
        intent=str(hints.get("intent") or request.intent),
        profile_epoch=_hint_profile_epoch(hints, request.profile_epoch),
        concepts={str(item) for item in (hints.get("concepts") or request.concepts)},
        answer_target=str(hints.get("answer_target") or request.answer_target),
        relation_hints={str(item) for item in ([hints.get("relation_path")] if hints.get("relation_path") else request.relation_hints)},
        evidence_hash=str(hints.get("evidence_hash") or ""),
        policy_version=str(hints.get("policy_version") or request.policy_version),
        kg_version=str(hints.get("kg_version") or request.kg_version),
        source_version=str(hints.get("source_version") or request.source_version),
        freshness_class=str(hints.get("freshness_class") or request.freshness_class),
    )


def _hint_profile_epoch(hints: Mapping[str, Any], fallback: int) -> int:
    """Map an oracle profile-epoch hint (e.g. 'profile_v1') to a stable int."""
    raw = hints.get("profile_epoch")
    if raw is None or raw == "":
        return fallback
    if isinstance(raw, int):
        return raw
    return int(hashlib.md5(str(raw).encode()).hexdigest()[:8], 16)


def _build_l1_candidate_signature(
    *,
    cache_key: str,
    entry: CacheEntry,
    current_level: str,
    current_profile: Mapping[str, Any],
) -> L1Candidate:
    candidate_fp = entry.get("fingerprint") or {}
    certificate = _certificate_from_entry(entry)
    candidate_query = str(certificate.get("query_norm") or candidate_fp.get("query_norm") or "").strip().lower()
    candidate_profile = entry.get("profile_snapshot") or dict(current_profile)
    candidate_level = str(
        candidate_fp.get("level")
        or (candidate_profile if isinstance(candidate_profile, Mapping) else {}).get("level")
        or current_level
    )
    execution_plan = entry.get("execution_plan") or {}
    state_hints = execution_plan.get("benchmark_state") or {}
    candidate_intent = str(candidate_fp.get("intent") or execution_plan.get("intent") or "")

    candidate = L1Candidate(
        cache_key=cache_key,
        query_norm=candidate_query,
        intent=str(certificate.get("intent") or candidate_intent),
        level=str(certificate.get("level") or candidate_level),
        profile_epoch=int(certificate.get("profile_epoch") or _profile_epoch(candidate_profile if isinstance(candidate_profile, Mapping) else current_profile)),
        session_turn=int(candidate_fp.get("session_turn") or 0),
        concepts={str(item) for item in (certificate.get("concepts") or [])} or _l1_signature_concepts(candidate_query, candidate_fp),
        entities=_extract_l1_entities(candidate_query),
        answer_target=str(certificate.get("answer_target") or _answer_target_hint(candidate_query)),
        relation_hints={str(certificate.get("relation_path"))} if certificate.get("relation_path") else _canonical_relation_hints(candidate_query),
        evidence_hash=str(certificate.get("evidence_hash") or _evidence_dependency_hash(entry)),
        policy_version=str(certificate.get("policy_version") or ""),
        kg_version=str(certificate.get("kg_version") or ""),
        source_version=str(certificate.get("source_version") or ""),
        freshness_class=str(certificate.get("freshness_class") or ""),
        native_language=str(certificate.get("native_language") or candidate_fp.get("native_language") or ""),
        schema_version=int(certificate.get("schema_version") or 1),
        required_dimensions={str(item) for item in (certificate.get("required_dimensions") or [])},
        created_at=float(entry.get("created_at") or time.time()),
        ttl=int(entry.get("ttl") or 3600),
    )
    return replace(
        candidate,
        intent=str(state_hints.get("intent") or candidate.intent),
        profile_epoch=_hint_profile_epoch(state_hints, candidate.profile_epoch),
        concepts={str(item) for item in (state_hints.get("concepts") or candidate.concepts)},
        answer_target=str(state_hints.get("answer_target") or candidate.answer_target),
        relation_hints={str(item) for item in ([state_hints.get("relation_path")] if state_hints.get("relation_path") else candidate.relation_hints)},
        evidence_hash=str(state_hints.get("evidence_hash") or candidate.evidence_hash),
        policy_version=str(state_hints.get("policy_version") or candidate.policy_version),
        kg_version=str(state_hints.get("kg_version") or candidate.kg_version),
        source_version=str(state_hints.get("source_version") or candidate.source_version),
        freshness_class=str(state_hints.get("freshness_class") or candidate.freshness_class),
    )


def _patch_response(entry: CacheEntry, fingerprint: CacheFingerprint) -> str:
    """
    Delta-patch a cached response for moderate drift (paper Alg. 1 line 13).

    Applies lightweight adjustments:
    - Re-target CEFR level vocabulary hints
    - Append changed concept references
    """
    response = entry.get("response", "")

    cached_level = (entry.get("fingerprint") or {}).get("level", "B1")
    cur_level = fingerprint.get("level", "B1")
    if cached_level != cur_level:
        response = response.replace(f"({cached_level})", f"({cur_level})")

    cur_concepts = set(fingerprint.get("root_concepts") or [])
    cached_concepts = set((entry.get("fingerprint") or {}).get("root_concepts") or [])
    new_concepts = cur_concepts - cached_concepts
    if new_concepts:
        extras = ", ".join(c.split(".")[-1].replace("_", " ") for c in new_concepts)
        response += f"\n\n(Also related: {extras})"

    return response


def _patch_allowed(entry: CacheEntry, fingerprint: CacheFingerprint) -> bool:
    """Permit patching only for explicitly declared non-factual slots."""
    declared = {str(item) for item in (_certificate_from_entry(entry).get("patchable_slots") or [])}
    cached = set((entry.get("fingerprint") or {}).get("root_concepts") or [])
    current = set(fingerprint.get("root_concepts") or [])
    changed = {"concepts"} if cached != current else set()
    if (entry.get("fingerprint") or {}).get("query_norm") != fingerprint.get("query_norm"):
        changed.add("query")
    return bool(changed) and changed.issubset(declared)


def _concept_overlap_score(current: CacheFingerprint, candidate: CacheEntry) -> float:
    cur_concepts = set(current.get("root_concepts") or [])
    cached_concepts = set((candidate.get("fingerprint") or {}).get("root_concepts") or [])
    if not cur_concepts and not cached_concepts:
        return 0.5
    return len(cur_concepts & cached_concepts) / max(len(cur_concepts | cached_concepts), 1)


def _recency_score(current: CacheFingerprint, candidate: CacheEntry) -> float:
    import math

    cur_turn = int(current.get("session_turn") or 0)
    cached_turn = int((candidate.get("fingerprint") or {}).get("session_turn") or 0)
    turn_gap = abs(cur_turn - cached_turn)
    return math.exp(-_L1_RECENCY_LAMBDA * turn_gap)


def _rank_l1_candidate(
    fingerprint: CacheFingerprint,
    candidate: CacheEntry,
    now: float,
) -> tuple[float, float]:
    """Return (rank_score, rho) for L1 candidate ordering."""
    rho = _compute_reuse_risk(fingerprint, candidate, now)
    overlap = _concept_overlap_score(fingerprint, candidate)
    recency = _recency_score(fingerprint, candidate)
    score = (
        -_L1_RISK_WEIGHT * rho
        + _L1_OVERLAP_WEIGHT * overlap
        + _L1_RECENCY_WEIGHT * recency
    )
    return score, rho


# ============================================================
# IN-PROCESS CACHE (Structured CacheEntry, fallback when Redis unavailable)
# ============================================================

_MEM_RESPONSE_CACHE: dict[str, tuple[float, CacheEntry]] = {}
_MEM_GRAPH_BUCKETS: dict[str, list[str]] = {}
_MEM_RESPONSE_CACHE_MAX_ITEMS = 1024
_MEM_BUCKET_MAX_ITEMS = 8

# ── L1 Bucket Version Store (paper §5.3, Algorithm 3) ───────────────────────
# v_b = ⟨ν_graph, ν_policy, ν_profile, t_refresh⟩
# Increment a version constant to invalidate all buckets at startup.
_MEM_BUCKET_VERSIONS: dict[str, BucketVersionRecord] = {}
_GRAPH_SCHEMA_VERSION: int = 1   # bump when KG topology / node schema changes
_POLICY_VERSION: int = 1          # bump when strategy / prompt templates change
_DEFAULT_BUCKET_TTL: int = 7200   # 2 h: max age of a valid L1 bucket


def _write_bucket_version(bucket: str, profile_epoch: Optional[int] = None) -> None:
    """Record current deployment version tuple for *bucket* (Algorithm 3, PromoteToL1)."""
    _MEM_BUCKET_VERSIONS[bucket] = BucketVersionRecord(
        nu_graph=_GRAPH_SCHEMA_VERSION,
        nu_policy=_POLICY_VERSION,
        nu_profile=int(profile_epoch or 0),
        t_refresh=time.monotonic(),
    )


def _bucket_version_valid(bucket: str, current_profile_epoch: Optional[int] = None) -> bool:
    """
    Algorithm 3, lines 3–5: return False when the bucket should be invalidated.

    A bucket is stale when:
      - its graph-schema version ≠ current (KG rebuild happened), OR
      - its policy version ≠ current (prompt templates changed), OR
      - its age exceeds _DEFAULT_BUCKET_TTL.
    A bucket with *no* version record is treated as fresh (first write hasn't
    happened yet) to avoid spuriously invalidating cold buckets.
    """
    rec = _MEM_BUCKET_VERSIONS.get(bucket)
    if rec is None:
        return True
    if rec.get("nu_graph", _GRAPH_SCHEMA_VERSION) != _GRAPH_SCHEMA_VERSION:
        return False
    if rec.get("nu_policy", _POLICY_VERSION) != _POLICY_VERSION:
        return False
    if current_profile_epoch is not None and int(rec.get("nu_profile", 0)) != int(current_profile_epoch):
        return False
    age = time.monotonic() - rec.get("t_refresh", 0.0)
    return age <= _DEFAULT_BUCKET_TTL


def _invalidate_bucket(bucket: str) -> None:
    """
    Evict all candidates registered under *bucket* from the in-process caches
    and remove the version record (Algorithm 3, InvalidateBucket).
    """
    orphan_keys = _MEM_GRAPH_BUCKETS.pop(bucket, [])
    _MEM_BUCKET_VERSIONS.pop(bucket, None)
    for key in orphan_keys:
        _MEM_RESPONSE_CACHE.pop(key, None)
    if orphan_keys:
        logger.debug(f"[_invalidate_bucket] invalidated bucket={bucket[:8]} evicted={len(orphan_keys)} keys")


def _is_pcc_stable(state: TraceCAGState) -> bool:
    """
    WriteL1(x) = PCCStable ∧ Confident ∧ ¬HighlySpecific  (paper §4.1).

    PCCStable  — diagnosis produced at least one root-cause concept so the
                 bucket is anchored to a stable graph neighbourhood.
    Confident  — diagnosis_confidence ≥ 0.70 (arbitrary but conservative).
    ¬HighlySpec— input is at least 3 words long; single-word or two-word queries
                 are too instance-specific to be useful L1 artifacts.
    """
    word_count = len((state.get("user_input") or "").split())
    if word_count < 3:
        return False
    state_hints = (state.get("benchmark_metadata") or {}).get("_tracecag_state") or {}
    if state_hints.get("concepts"):
        # Benchmark bypass skips the diagnosis stage (no confidence score is
        # produced); oracle-provided concepts anchor the bucket instead.
        return True
    if state.get("diagnosis_confidence", 0.0) < 0.70:
        return False
    return bool(state.get("diagnosis_root_causes"))


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


_L1_ENTITY_STOPWORDS = {
    "what", "which", "who", "whom", "whose", "where", "when", "why", "how",
    "many", "much", "the", "a", "an", "of", "in", "on", "for", "to", "from",
    "by", "with", "and", "or", "that", "this", "those", "these", "was", "were",
    "is", "are", "did", "does", "do", "had", "has", "have", "came", "come",
    "out", "first", "film", "movie", "person", "company", "corporation",
    "behind", "makes", "made", "make", "creator", "created", "founder",
    "founded", "director", "directed", "writer", "author", "mother", "father",
    "wife", "brother", "grandfather", "born", "birth", "year", "date", "times",
    "taller", "higher", "country", "city", "language", "award", "won",
}


def _extract_l1_entities(user_input: str) -> set[str]:
    """Extract cheap stable entity-ish tokens for SCAR-L1 candidate pooling."""
    text = (user_input or "").lower()
    tokens = re.findall(r"[a-z0-9][a-z0-9'-]{2,}", text)
    entities = {
        token.strip("-'")
        for token in tokens
        if token not in _L1_ENTITY_STOPWORDS and len(token.strip("-'")) >= 3
    }
    return {token for token in entities if token}


def _answer_target_hint(user_input: str) -> str:
    """Cheap answer-target class used as a hard SCAR-L1 compatibility signal."""
    text = (user_input or "").lower()
    if any(token in text for token in ["when", "what year", "which year", "date"]):
        return "time"
    if any(token in text for token in ["where", "country", "city", "place", "located"]):
        return "place"
    if any(token in text for token in ["how many", "how much", "times", "number"]):
        return "number"
    if any(token in text for token in ["who", "mother", "father", "wife", "brother", "grandfather", "founder", "director"]):
        return "person"
    if any(token in text for token in ["which", "what"]):
        return "entity"
    return "feedback"


def _relation_hints(user_input: str) -> set[str]:
    """Map lexical cues into coarse relation classes for SCAR-L1 safety checks."""
    text = (user_input or "").lower()
    relation_map = {
        "founder": ("founder", "founded", "co-founded", "created", "creator"),
        "maker": ("makes", "made by", "manufacturer", "behind"),
        "birth": ("born", "birth"),
        "director": ("director", "directed"),
        "author": ("writer", "author", "wrote"),
        "family": ("mother", "father", "wife", "brother", "grandfather"),
        "mother": ("mother",),
        "father": ("father",),
        "wife": ("wife",),
        "brother": ("brother",),
        "grandfather": ("grandfather",),
        "time_order": ("came out first", "came first", "first", "earlier", "before", "released", "debut"),
        "comparison": ("taller", "higher", "larger", "older", "younger"),
        "location": ("where", "country", "city", "located", "place"),
        "award": ("award", "won"),
        "predecessor": ("predecessor", "succeeded"),
    }
    hints: set[str] = set()
    for relation, cues in relation_map.items():
        if any(cue in text for cue in cues):
            hints.add(relation)
    return hints


def _canonical_relation_hints(user_input: str) -> set[str]:
    """Encode the complete relation set as one deterministic certificate value."""
    hints = _relation_hints(user_input)
    return {"|".join(sorted(hints))} if hints else set()


def _infer_intent_pre_diagnosis(user_input: str) -> str:
    text = (user_input or "").lower()
    if any(token in text for token in ["why", "explain", "what does", "how does"]):
        return "explain"
    if any(token in text for token in ["practice", "exercise", "quiz", "train"]):
        return "practice"
    if text.rstrip().endswith("?") or any(token in text for token in ["who", "where", "when", "which", "what", "how many"]):
        return "ask"
    return "correct"


# Common phrases users write to request a native-language explanation.
# Covers English phrases and common native scripts for supported languages.
_NATIVE_REQUEST_PHRASES = (
    "explain in",
    "explain it in",
    "say it in",
    "tell me in",
    "in my language",
    # Vietnamese
    "giải thích bằng",
    "bằng tiếng việt",
    "dùng tiếng việt",
    "nói bằng tiếng",
    # Japanese
    "日本語で",
    "説明して",
    # Korean
    "한국어로",
    "설명해",
    # Chinese
    "用中文",
    "用中文解释",
    # Spanish
    "explícame en",
    "en español",
    # French
    "expliquer en",
    "en français",
)


def _detect_native_request(user_input: str) -> bool:
    """Return True when the user is explicitly asking for a native-language explanation."""
    lower = (user_input or "").lower()
    return any(phrase in lower for phrase in _NATIVE_REQUEST_PHRASES)


def _profile_epoch(profile: Mapping[str, Any]) -> int:
    level = str(profile.get("level") or "B1").upper()
    sessions_completed = int(profile.get("sessions_completed") or 0)
    vocabulary_count = int(profile.get("vocabulary_count") or 0)
    common_errors = profile.get("common_errors") or []
    error_bucket = len(common_errors) // 2 if isinstance(common_errors, list) else 0
    learner_state_epoch = int(profile.get("_learner_state_epoch") or 0)
    key = (
        f"{level}|{sessions_completed // 3}|{vocabulary_count // 200}|"
        f"{error_bucket}|{learner_state_epoch}"
    )
    return int(hashlib.md5(key.encode()).hexdigest()[:8], 16)


def _user_cache_scope(state: Mapping[str, Any]) -> str:
    """Non-reversible scope for personalized response caches only."""
    if settings.LEARNER_STATE_MODE == "off" or not state.get("user_id"):
        return ""
    secret = settings.SECRET_KEY or settings.LEARNER_STATE_INTERNAL_TOKEN
    if not secret:
        return "unavailable"
    return hmac.new(
        secret.encode(), str(state["user_id"]).encode(), hashlib.sha256
    ).hexdigest()[:24]


def _build_graph_bucket(
    user_input: str,
    level: str,
    intent: str,
    profile_epoch: int,
    conversation_history: list[dict[str, Any]],
) -> str:
    """Cheap graph-aware bucket used for L1 candidate lookup."""
    concepts = _extract_lightweight_graph_concepts(user_input)
    if not concepts:
        concepts = ["token:generic"]
    bucket_material = "|".join([
        level,
        intent,
        str(profile_epoch),
        str(len(conversation_history) // 2),
    ] + concepts[:5])
    return hashlib.md5(bucket_material.encode()).hexdigest()


def _build_l1_bucket_aliases(
    user_input: str,
    level: str,
    intent: str,
    profile_epoch: int,
    conversation_history: list[dict[str, Any]],
) -> list[str]:
    """Return primary and SCAR-L1 alias buckets for near-hit candidate pooling."""
    primary = _build_graph_bucket(user_input, level, intent, profile_epoch, conversation_history)
    aliases = [primary]
    conv_bucket = str(len(conversation_history) // 2)
    entities = sorted(_extract_l1_entities(user_input))[:8]
    relations = sorted(_relation_hints(user_input))[:5]
    answer_target = _answer_target_hint(user_input)

    if entities or relations:
        material = "|".join([
            "scar_l1_state",
            str(level),
            str(intent),
            str(profile_epoch),
            conv_bucket,
            answer_target,
        ] + relations + entities)
        aliases.append(hashlib.md5(material.encode()).hexdigest())

    if entities:
        material = "|".join([
            "scar_l1_entity",
            str(level),
            str(intent),
            str(profile_epoch),
            conv_bucket,
        ] + entities)
        aliases.append(hashlib.md5(material.encode()).hexdigest())

    # Per-entity aliases: hashing the full entity set makes the pool brittle —
    # one extra surface token in a paraphrase changes the hash entirely. A
    # coarse per-entity pool lets near-hits collide; safety is enforced
    # downstream by the PCC hard gates and risk scoring in decide_l1_reuse.
    for entity in entities[:5]:
        material = "|".join([
            "scar_l1_entity1",
            str(level),
            str(profile_epoch),
            entity,
        ])
        aliases.append(hashlib.md5(material.encode()).hexdigest())

    return list(dict.fromkeys(alias for alias in aliases if alias))


def _register_graph_bucket(
    bucket: str,
    cache_key: str,
    *,
    profile_epoch: Optional[int] = None,
    refresh_version: bool = True,
) -> None:
    if not bucket:
        return
    keys = [item for item in _MEM_GRAPH_BUCKETS.get(bucket, []) if item != cache_key]
    keys.insert(0, cache_key)
    _MEM_GRAPH_BUCKETS[bucket] = keys[:_MEM_BUCKET_MAX_ITEMS]
    if refresh_version:
        _write_bucket_version(bucket, profile_epoch=profile_epoch)


def _register_l1_bucket_aliases(
    user_input: str,
    level: str,
    intent: str,
    profile_epoch: int,
    conversation_history: list[dict[str, Any]],
    cache_key: str,
) -> list[str]:
    buckets = _build_l1_bucket_aliases(user_input, level, intent, profile_epoch, conversation_history)
    for alias in buckets:
        _register_graph_bucket(alias, cache_key, profile_epoch=profile_epoch)
    return buckets


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
            "admissibility_certificate": raw.get("admissibility_certificate", {}),
            "graph_bucket": raw.get("graph_bucket", ""),
            "profile_snapshot": raw.get("profile_snapshot", {}),
            "response": raw.get("response", raw.get("tutor_response", "")),
            "evidence_bundle": raw.get("evidence_bundle", []),
            "retrieval_trace": raw.get("retrieval_trace", []),
            "execution_plan": raw.get("execution_plan", {"strategy": raw.get("strategy", "feedback")}),
            "diagnosis_errors": raw.get("diagnosis_errors", []),
            "grammar_score": raw.get("grammar_score", 0.0),
            "fluency_score": raw.get("fluency_score", 0.0),
            "vocabulary_level": raw.get("vocabulary_level", "B1"),
            "action_plan": raw.get("action_plan", []),
            "overall_score": raw.get("overall_score", 0.8),
            "created_at": raw.get("created_at", now - 60),
            "ttl": raw.get("ttl", 3600),
        }
        ttl_remaining = max(entry["ttl"] - (now - entry.get("created_at", now)), 60)
        _MEM_RESPONSE_CACHE[cache_key] = (now + ttl_remaining, entry)
        if entry.get("graph_bucket"):
            _register_graph_bucket(entry["graph_bucket"], cache_key, refresh_version=False)
        return entry
    except Exception as e:
        logger.debug(f"[_get_cache_entry] Redis read failed: {e}")
        return None


async def _write_cache_entry(
    state: TraceCAGState,
    response: str,
    strategy: str,
    errors: list,
    overall_score: float,
    context: str = "",
    model_used: str = "",
) -> None:
    """Write a structured CacheEntry to both in-process and Redis caches."""
    user_input = state.get("user_input", "")
    learner_profile = state.get("learner_profile", {})
    level = learner_profile.get("level", "B1")
    state_hints = (state.get("benchmark_metadata") or {}).get("_tracecag_state") or {}
    intent_hint = str(state_hints.get("intent") or state.get("diagnosis_intent") or _infer_intent_pre_diagnosis(user_input))
    profile_epoch = _profile_epoch(learner_profile)
    if (
        settings.LEARNER_STATE_MODE != "off"
        and state.get("user_id")
        and not learner_profile.get("_learner_state_available")
    ):
        logger.debug("[_write_cache_entry] Skip personalized cache: learner epoch unavailable")
        return
    user_scope = _user_cache_scope(state)
    scoped_input = f"{user_scope}:{user_input}" if user_scope else user_input

    normalized = user_input.strip().lower()
    cache_raw = (
        f"{user_scope}||{normalized}||{level}"
        if user_scope
        else f"{normalized}||{level}"
    )
    cache_key = hashlib.md5(cache_raw.encode()).hexdigest()
    graph_bucket = _build_graph_bucket(
        scoped_input,
        level,
        intent_hint,
        profile_epoch,
        state.get("conversation_history", []),
    )

    ttl = 3600 if errors else 1800
    # Wall-clock, not monotonic: created_at is serialized into Redis and read
    # back by other processes/hosts, where monotonic()'s reference point is
    # undefined (Python docs) and only happens to align on a single host.
    now = time.time()

    raw_bundle = [
        {"type": "kg", "content": c}
        for c in (context or "").split("\n") if c.strip()
    ]
    retrieval_trace = list(state.get("retrieval_trace") or [])[:8]

    fingerprint = _build_fingerprint(state)
    certificate = _build_admissibility_certificate(
        state=state,
        fingerprint=fingerprint,
        profile_epoch=profile_epoch,
        state_hints=state_hints,
        now=now,
    )

    entry = CacheEntry(
        fingerprint=fingerprint,
        admissibility_certificate=certificate,
        graph_bucket=graph_bucket,
        profile_snapshot=dict(state.get("learner_profile", {})),
        response=response,
        evidence_bundle=raw_bundle[:10],
        retrieval_trace=retrieval_trace,
        execution_plan={
            "strategy": strategy,
            "intent": state.get("diagnosis_intent", "correct"),
            "model": model_used or "unknown",
            "benchmark_state": dict((state.get("benchmark_metadata") or {}).get("_tracecag_state") or {}),
        },
        diagnosis_errors=[dict(e) for e in errors] if errors else [],
        grammar_score=state.get("grammar_score", 0.0),
        fluency_score=state.get("fluency_score", 0.0),
        vocabulary_level=state.get("vocabulary_level", "B1"),
        action_plan=state.get("action_plan", []),
        overall_score=overall_score,
        created_at=now,
        ttl=ttl,
    )

    # In-process cache — LRU eviction instead of naive clear()
    if len(_MEM_RESPONSE_CACHE) >= _MEM_RESPONSE_CACHE_MAX_ITEMS:
        expired_keys = [k for k, (exp, _) in _MEM_RESPONSE_CACHE.items() if exp <= now]
        for k in expired_keys:
            _MEM_RESPONSE_CACHE.pop(k, None)
        if len(_MEM_RESPONSE_CACHE) >= _MEM_RESPONSE_CACHE_MAX_ITEMS:
            evict_count = _MEM_RESPONSE_CACHE_MAX_ITEMS // 4
            oldest = sorted(_MEM_RESPONSE_CACHE.items(), key=lambda kv: kv[1][0])[:evict_count]
            for k, _ in oldest:
                _MEM_RESPONSE_CACHE.pop(k, None)
    _MEM_RESPONSE_CACHE[cache_key] = (now + ttl, entry)

    if _is_pcc_stable(state):
        buckets = _register_l1_bucket_aliases(
            scoped_input,
            level,
            intent_hint,
            profile_epoch,
            state.get("conversation_history", []),
            cache_key,
        )
        logger.debug(
            f"[_write_cache_entry] L1 promote key={cache_key[:8]} "
            f"buckets={','.join(bucket[:8] for bucket in buckets)}"
        )
    else:
        logger.debug(f"[_write_cache_entry] L1 skipped (not PCC-stable) key={cache_key[:8]}")

    should_promote_l1 = _is_pcc_stable(state)

    try:
        from api.core.redis_client import RedisClient
        redis_client = await RedisClient.get_instance()
        await redis_client.set(f"v1:resp:{cache_key}", json.dumps(entry), ex=ttl)
        if should_promote_l1:
            for alias in _build_l1_bucket_aliases(
                scoped_input,
                level,
                intent_hint,
                profile_epoch,
                state.get("conversation_history", []),
            ):
                await _register_graph_bucket_redis(alias, cache_key, ttl)
        logger.debug(f"[_write_cache_entry] Cached key={cache_key[:8]} ttl={ttl}s")
    except Exception as e:
        logger.debug(f"[_write_cache_entry] Redis write failed: {e}")


# ============================================================
# NODE 1.5: CACHE GATE (Response Cache Check)
# ============================================================

async def cache_gate_node(state: TraceCAGState) -> Dict[str, Any]:
    """
    RAPID Risk-Aware Cache Gate (paper Alg. 1).

    Ternary decision:
      reuse  — ρ ≤ τ₀ and PCC-valid   → return cached response directly
      patch  — ρ ≤ τ₁ and PCC-patchable → delta-patch cached response
      full   — otherwise                → run full pipeline

    Cache key = MD5(normalized_input || level)
    Structured entry stores ⟨F, P_c, R, B, σ, t_c⟩
    """
    from api.services.trace_cag.benchmark.adaptive import _choose_adaptive_profile
    from api.services.trace_cag.benchmark.quality import _cache_entry_quality_ok_for_benchmark

    logger.info("[cache_gate_node] RAPID risk-aware cache check...")
    routing_started = time.perf_counter()

    cache_policy = state.get("cache_policy", "on")
    if cache_policy != "on":
        return {
            "cache_hit": False,
            "cache_decision": "full",
            "reuse_risk": 1.0,
            "path": "slow",
            "cache_gate_meta": {
                "pcc_passed": False,
                "reasons": ["cache_disabled"],
                "risk": 1.0,
                "routing_latency_ms": (time.perf_counter() - routing_started) * 1000.0,
            },
        }

    user_input = state.get("user_input", "")
    learner_profile = state.get("learner_profile", {})
    level = learner_profile.get("level", "B1")
    conversation_history = state.get("conversation_history", [])
    intent_hint = _infer_intent_pre_diagnosis(user_input)
    benchmark_task = state.get("benchmark_task") or ""
    profile_epoch = _profile_epoch(learner_profile)
    if (
        settings.LEARNER_STATE_MODE != "off"
        and state.get("user_id")
        and not learner_profile.get("_learner_state_available")
    ):
        return {
            "cache_hit": False,
            "cache_decision": "full",
            "reuse_risk": 1.0,
            "path": "slow",
            "cache_gate_meta": {
                "pcc_passed": False,
                "reasons": ["learner_epoch_unavailable"],
                "risk": 1.0,
            },
        }
    user_scope = _user_cache_scope(state)
    scoped_input = f"{user_scope}:{user_input}" if user_scope else user_input
    bucket = _build_graph_bucket(scoped_input, level, intent_hint, profile_epoch, conversation_history)
    l1_buckets = _build_l1_bucket_aliases(scoped_input, level, intent_hint, profile_epoch, conversation_history)

    native_language = learner_profile.get("native_language", "Vietnamese")
    fingerprint = CacheFingerprint(
        query_norm=user_input.strip().lower(),
        intent=intent_hint,
        level=level,
        native_language=native_language,
        root_concepts=_extract_lightweight_graph_concepts(user_input),
        session_turn=len(conversation_history),
    )

    benchmark_metadata = state.get("benchmark_metadata") or {}
    state_hints = benchmark_metadata.get("_tracecag_state") or {}
    request_certificate = _build_admissibility_certificate(
        state=state,
        fingerprint=fingerprint,
        profile_epoch=profile_epoch,
        state_hints=state_hints,
        now=time.time(),
    )
    benchmark_mode = str(benchmark_metadata.get("_benchmark_mode") or "").strip().lower()
    adaptive_choice = _choose_adaptive_profile(
        state=state,
        user_input=user_input,
        benchmark_task=benchmark_task,
        benchmark_mode=benchmark_mode,
        benchmark_metadata=benchmark_metadata,
    )
    tau_reuse = float(adaptive_choice.get("tau_reuse", _TAU_REUSE))
    tau_patch = float(adaptive_choice.get("tau_patch", _TAU_PATCH))

    adaptive_payload = {
        "adaptive_profile": adaptive_choice.get("profile"),
        "adaptive_features": adaptive_choice.get("features", {}),
        "adaptive_controller": {
            **(adaptive_choice.get("controller") or {}),
            "explore": bool(adaptive_choice.get("explore", False)),
            "objective_map": adaptive_choice.get("objective_map", {}),
            "tau_reuse": tau_reuse,
            "tau_patch": tau_patch,
            "support_floor": adaptive_choice.get("support_floor"),
            "evidence_budget_delta": adaptive_choice.get("evidence_budget_delta"),
        },
    }

    def _with_adaptive(payload: Dict[str, Any]) -> Dict[str, Any]:
        if not adaptive_choice:
            return payload
        merged = dict(payload)
        merged.update(adaptive_payload)
        return merged

    def _with_gate_meta(
        payload: Dict[str, Any],
        *,
        pcc_passed: bool,
        reasons: Sequence[str],
        risk: float,
    ) -> Dict[str, Any]:
        merged = dict(payload)
        merged["cache_gate_meta"] = {
            "pcc_passed": pcc_passed,
            "reasons": list(reasons),
            "risk": float(risk),
            "tau_reuse": tau_reuse,
            "tau_patch": tau_patch,
            "routing_latency_ms": (time.perf_counter() - routing_started) * 1000.0,
            "request_state": dict(state_hints),
            "admissibility_certificate": dict(request_certificate),
        }
        try:
            from api.services.telemetry import get_telemetry

            decision = str(merged.get("cache_decision") or "full")
            telemetry = get_telemetry()
            telemetry.increment_counter("tracecag_personalized_cache_decision_total")
            telemetry.record_metric(
                "tracecag_personalized_cache_decision",
                1,
                unit="count",
                tags={"decision": decision},
            )
        except Exception:
            pass
        return _with_adaptive(merged)

    normalized = user_input.strip().lower()
    cache_raw = (
        f"{user_scope}||{normalized}||{level}"
        if user_scope
        else f"{normalized}||{level}"
    )
    cache_key = hashlib.md5(cache_raw.encode()).hexdigest()
    l1_request = _build_l1_request_signature(
        # The user-scope HMAC belongs in cache keys/buckets only.  Feeding it
        # to semantic extractors creates a synthetic entity and makes an
        # identical personalized request diverge from its stored certificate.
        user_input=user_input,
        normalized=normalized,
        fingerprint=fingerprint,
        level=level,
        intent_hint=intent_hint,
        profile_epoch=profile_epoch,
        conversation_history=conversation_history,
        state_hints=state_hints,
    )
    best_rejection: tuple[float, tuple[str, ...]] | None = None

    # --- Try in-process cache ---
    # Wall-clock (see _write_cache_entry): must compare against created_at
    # values that may have been written by a different process/host via Redis.
    now = time.time()
    entry = await _get_cache_entry(cache_key, level, now)
    if entry:
        if not _cache_entry_quality_ok_for_benchmark(entry, benchmark_task):
            logger.info(f"[cache_gate_node] L0 skip low-quality benchmark cache key={cache_key[:8]}")
            entry = None
    if entry:
        rho = _compute_reuse_risk(fingerprint, entry, now)

        l0_candidate = _build_l1_candidate_signature(
            cache_key=cache_key,
            entry=entry,
            current_level=level,
            current_profile=learner_profile,
        )
        l0_certificate = decide_l1_reuse(
            l1_request,
            l0_candidate,
            now=now,
            tau_reuse=tau_reuse,
            tau_patch=tau_patch,
        )
        l0_safe = l0_certificate.safe_to_reuse
        l0_reasons = l0_certificate.reasons
        if not l0_safe:
            best_rejection = (l0_certificate.risk, l0_certificate.reasons)

        logger.info(f"[cache_gate_node] L0 HIT key={cache_key[:8]} ρ={rho:.3f} safe={l0_safe}")

        if l0_safe and rho <= tau_reuse:
            _resp_text = entry.get("response", "")
            return _with_gate_meta({
                "cache_hit": True,
                "cache_decision": "reuse",
                "cache_layer": "L0",
                "cache_bucket": bucket,
                "reuse_risk": rho,
                "cache_fingerprint": fingerprint,
                "tutor_response": _resp_text,
                "retrieval_trace": entry.get("retrieval_trace", []),
                "strategy": (entry.get("execution_plan") or {}).get("strategy", "feedback"),
                "diagnosis_errors": entry.get("diagnosis_errors", []),
                "grammar_score": entry.get("grammar_score", 0.0),
                "fluency_score": entry.get("fluency_score", 0.0),
                "vocabulary_level": entry.get("vocabulary_level", "B1"),
                "action_plan": entry.get("action_plan", []),
                "overall_score": entry.get("overall_score", 0.8),
                "path": "fast",
                "ttft_ms": 1,
                "tokens_saved": 650 + len(_resp_text) // 4,
                "models_used": ["rapid_reuse_l0"],
            }, pcc_passed=True, reasons=l0_reasons, risk=rho)
        elif l0_safe and rho <= tau_patch and _patch_allowed(entry, fingerprint):
            patched = _patch_response(entry, fingerprint)
            return _with_gate_meta({
                "cache_hit": True,
                "cache_decision": "patch",
                "cache_layer": "L0",
                "cache_bucket": bucket,
                "reuse_risk": rho,
                "cache_fingerprint": fingerprint,
                "tutor_response": patched,
                "retrieval_trace": entry.get("retrieval_trace", []),
                "strategy": (entry.get("execution_plan") or {}).get("strategy", "feedback"),
                "diagnosis_errors": entry.get("diagnosis_errors", []),
                "grammar_score": entry.get("grammar_score", 0.0),
                "fluency_score": entry.get("fluency_score", 0.0),
                "vocabulary_level": entry.get("vocabulary_level", "B1"),
                "action_plan": entry.get("action_plan", []),
                "overall_score": entry.get("overall_score", 0.8),
                "path": "fast",
                "ttft_ms": 1,
                "tokens_saved": 650 + len(patched) // 4,
                "models_used": ["rapid_patch_l0"],
            }, pcc_passed=True, reasons=l0_reasons, risk=rho)

    # --- Try graph-bucket near-hit lookup (L1) ---
    valid_l1_buckets: list[str] = []
    for candidate_bucket in l1_buckets:
        if _bucket_version_valid(candidate_bucket, current_profile_epoch=profile_epoch):
            valid_l1_buckets.append(candidate_bucket)
            continue
        _invalidate_bucket(candidate_bucket)
        logger.info(
            f"[cache_gate_node] L1 bucket stale/invalid -> invalidated "
            f"(bucket={candidate_bucket[:8]})"
        )

    candidate_keys: list[str] = []
    seen_candidate_keys: set[str] = set()
    for candidate_bucket in valid_l1_buckets:
        for item in await _get_bucket_candidate_keys(candidate_bucket):
            if item == cache_key or item in seen_candidate_keys:
                continue
            seen_candidate_keys.add(item)
            candidate_keys.append(item)

    best_candidate: tuple[str, CacheEntry, float, float, str] | None = None

    candidate_entries = await asyncio.gather(
        *[_get_cache_entry(k, level, now) for k in candidate_keys],
        return_exceptions=True,
    )
    for candidate_key, candidate_entry in zip(candidate_keys, candidate_entries):
        if not isinstance(candidate_entry, dict) or not candidate_entry:
            continue
        if not _cache_entry_quality_ok_for_benchmark(candidate_entry, benchmark_task):
            continue
        l1_candidate = _build_l1_candidate_signature(
            cache_key=candidate_key,
            entry=candidate_entry,
            current_level=level,
            current_profile=learner_profile,
        )
        decision = decide_l1_reuse(
            l1_request,
            l1_candidate,
            now=now,
            tau_reuse=tau_reuse,
            tau_patch=tau_patch,
        )
        if decision.decision == "full":
            if best_rejection is None or decision.risk < best_rejection[0]:
                best_rejection = (decision.risk, decision.reasons)
            logger.debug(
                f"[cache_gate_node] L1 reject key={candidate_key[:8]} "
                f"reasons={','.join(decision.reasons)}"
            )
            continue
        if decision.decision == "patch" and not _patch_allowed(candidate_entry, fingerprint):
            best_rejection = (decision.risk, ("patch_slots_not_declared",))
            continue
        if best_candidate is None or decision.rank_score > best_candidate[2]:
            best_candidate = (
                candidate_key,
                candidate_entry,
                decision.rank_score,
                decision.risk,
                decision.decision,
            )

    if best_candidate is not None:
        _, entry, _, rho, l1_decision = best_candidate
        logger.info(f"[cache_gate_node] L1 HIT bucket={bucket[:8]} decision={l1_decision} ρ={rho:.3f}")
        if l1_decision == "reuse":
            _resp_text = entry.get("response", "")
            return _with_gate_meta({
                "cache_hit": True,
                "cache_decision": "reuse",
                "cache_layer": "L1",
                "cache_bucket": bucket,
                "reuse_risk": rho,
                "cache_fingerprint": fingerprint,
                "tutor_response": _resp_text,
                "retrieval_trace": entry.get("retrieval_trace", []),
                "strategy": (entry.get("execution_plan") or {}).get("strategy", "feedback"),
                "diagnosis_errors": entry.get("diagnosis_errors", []),
                "grammar_score": entry.get("grammar_score", 0.0),
                "fluency_score": entry.get("fluency_score", 0.0),
                "vocabulary_level": entry.get("vocabulary_level", "B1"),
                "action_plan": entry.get("action_plan", []),
                "overall_score": entry.get("overall_score", 0.8),
                "path": "fast",
                "ttft_ms": 1,
                "tokens_saved": 650 + len(_resp_text) // 4,
                "models_used": ["rapid_reuse_l1"],
            }, pcc_passed=True, reasons=("state_compatible_near_hit",), risk=rho)
        patched = _patch_response(entry, fingerprint)
        return _with_gate_meta({
            "cache_hit": True,
            "cache_decision": "patch",
            "cache_layer": "L1",
            "cache_bucket": bucket,
            "reuse_risk": rho,
            "cache_fingerprint": fingerprint,
            "tutor_response": patched,
            "retrieval_trace": entry.get("retrieval_trace", []),
            "strategy": (entry.get("execution_plan") or {}).get("strategy", "feedback"),
            "diagnosis_errors": entry.get("diagnosis_errors", []),
            "grammar_score": entry.get("grammar_score", 0.0),
            "fluency_score": entry.get("fluency_score", 0.0),
            "vocabulary_level": entry.get("vocabulary_level", "B1"),
            "action_plan": entry.get("action_plan", []),
            "overall_score": entry.get("overall_score", 0.8),
            "path": "fast",
            "ttft_ms": 1,
            "tokens_saved": 650 + len(patched) // 4,
            "models_used": ["rapid_patch_l1"],
        }, pcc_passed=True, reasons=("state_compatible_near_hit",), risk=rho)

    logger.info(f"[cache_gate_node] Cache MISS for key {cache_key[:8]}...")
    rejection_risk, rejection_reasons = best_rejection or (1.0, ("no_compatible_candidate",))
    return _with_gate_meta({
        "cache_hit": False,
        "cache_decision": "full",
        "cache_layer": "none",
        "cache_bucket": bucket,
        "reuse_risk": 1.0,
        "cache_fingerprint": fingerprint,
        "path": "slow",
    }, pcc_passed=False, reasons=rejection_reasons, risk=rejection_risk)
