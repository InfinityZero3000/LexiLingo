"""
TraceCAG retrieve_node — budgeted hybrid retrieval with fusion scoring (paper Alg. 5).

Split out of nodes_v2.py (Phase 4 refactor) since this node alone carries the
KG/vector/L2-external retrieval stages and fusion-score ranking logic.
"""

import asyncio
import logging
import math
import re
import time
from datetime import datetime, timezone
from typing import Any, Dict, List

from api.services.trace_cag.state import TraceCAGState
from api.services.document_intelligence import get_doc_intel_service
from api.services.trace_cag.env_helpers import _env_float, _env_int, _clip01
from api.services.trace_cag.retrieval_ranker import get_retrieval_ranker
from api.services.learner_overlay import rank_with_learner_overlay
from api.core.config import settings
from api.services.trace_cag.dependencies import dependency_record, stable_version_token

from api.services.trace_cag.kg_utils import (
    _KG_QUERY_CACHE, _kg_cache_key, _kg_cache_get, _kg_cache_set,
    _pack_kg_nodes_for_context,
)

from api.services.trace_cag.benchmark.adaptive import (
    _adaptive_mode_enabled, _choose_adaptive_profile,
)
from api.services.trace_cag.benchmark.ranking import (
    _benchmark_evidence_snippet,
    _build_benchmark_candidates,
    _compute_evidence_budget,
    _rank_benchmark_candidates,
    _rank_with_online_ranker,
    _ranker_enabled,
    _interleave_explicit_second_hop,
    _select_diverse_multihop_evidence,
)

logger = logging.getLogger(__name__)

_FUSION_ALPHA = 0.5   # KG structural relevance weight
_FUSION_BETA = 0.3    # Vector similarity weight
_FUSION_GAMMA = 0.2   # Recency bonus weight
_RECENCY_LAMBDA = 0.01  # Decay rate for recency bonus

_retrieval_v3_instance = None
_retrieval_v3_lock = asyncio.Lock()


async def _get_retrieval_v3():
    """Lazy singleton for RetrievalServiceV3 (centrality + community ranking).

    The constructor synchronously builds the NetworkX graph, computes
    centrality, and pre-warms concept embeddings — measured at 169.5s on the
    real production KG (15,129 concepts / 145,387 edges). Building it inline
    would block the event loop for that long on whichever request hits it
    first; ``asyncio.to_thread`` keeps this call safe both from a boot-time
    warmup (see AIOrchestrator.initialize) and from a live request in the
    rare case warmup was skipped. The lock ensures a live request racing a
    still-running background warmup awaits the same in-flight build instead
    of starting a second, redundant 169.5s construction.
    """
    global _retrieval_v3_instance
    if _retrieval_v3_instance is not None:
        return _retrieval_v3_instance
    async with _retrieval_v3_lock:
        if _retrieval_v3_instance is None:
            from api.services.kg_service_v3 import get_kg_service
            from api.services.retrieval_service_v3 import RetrievalServiceV3
            _retrieval_v3_instance = await asyncio.to_thread(RetrievalServiceV3, get_kg_service())
    return _retrieval_v3_instance


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
    s_kg = 1.0 / (1.0 + kg_depth)
    s_vec = vec_sim
    s_rec = math.exp(-_RECENCY_LAMBDA * last_used_turns_ago)
    return _FUSION_ALPHA * s_kg + _FUSION_BETA * s_vec + _FUSION_GAMMA * s_rec


async def retrieve_node(state: TraceCAGState) -> Dict[str, Any]:
    """
    Budgeted hybrid retrieval with fusion scoring (paper Alg. 5).

    Stage 1: Graph-local evidence (cheap) — KG concepts + diagnosis
    Stage 2: Optional vector evidence (budgeted) — MiniLM similarity
    Fusion:  score(e) = α·s_kg + β·s_vec + γ·s_rec  (Eq. 8)
    """
    logger.info("[retrieve_node] Budgeted hybrid retrieval...")
    start_time = time.time()
    retrieve_start = time.monotonic()

    kg_budget_ms = max(0.0, _env_float("TRACECAG_RETRIEVE_BUDGET_KG_MS", 120.0))
    vector_budget_ms = max(0.0, _env_float("TRACECAG_RETRIEVE_BUDGET_VECTOR_MS", 80.0))
    fusion_budget_ms = max(0.0, _env_float("TRACECAG_RETRIEVE_BUDGET_FUSION_MS", 40.0))
    total_budget_ms = kg_budget_ms + vector_budget_ms + fusion_budget_ms

    def _elapsed_ms() -> float:
        return (time.monotonic() - retrieve_start) * 1000.0

    budget_exhausted = False

    retrieval_policy = state.get("retrieval_policy", "full")
    benchmark_context = (state.get("benchmark_context") or "").strip()
    benchmark_task = state.get("benchmark_task") or ""
    benchmark_metadata = state.get("benchmark_metadata") or {}
    benchmark_ranker = str(benchmark_metadata.get("_benchmark_ranker") or "graph").strip().lower()
    benchmark_mode = str(benchmark_metadata.get("_benchmark_mode") or "").strip().lower()
    user_input = state.get("user_input", "")
    adaptive_profile = str(state.get("adaptive_profile") or "").strip().lower()
    adaptive_features = dict(state.get("adaptive_features") or {})
    adaptive_controller = dict(state.get("adaptive_controller") or {})

    if _adaptive_mode_enabled(state, benchmark_mode) and not adaptive_profile:
        adaptive_choice = _choose_adaptive_profile(
            state=state,
            user_input=user_input,
            benchmark_task=benchmark_task,
            benchmark_mode=benchmark_mode,
            benchmark_metadata=benchmark_metadata,
        )
        adaptive_profile = str(adaptive_choice.get("profile") or "balanced")
        adaptive_features = dict(adaptive_choice.get("features") or {})
        adaptive_controller = {
            **dict(adaptive_choice.get("controller") or {}),
            "explore": bool(adaptive_choice.get("explore", False)),
            "objective_map": adaptive_choice.get("objective_map", {}),
            "tau_reuse": adaptive_choice.get("tau_reuse"),
            "tau_patch": adaptive_choice.get("tau_patch"),
            "support_floor": adaptive_choice.get("support_floor"),
            "evidence_budget_delta": adaptive_choice.get("evidence_budget_delta"),
        }

    kg_concepts = state.get("kg_seed_concepts", [])
    kg_expanded = state.get("kg_expanded_nodes", [])
    session_turn = len(state.get("conversation_history", []))
    benchmark_candidates, relevant_ids = _build_benchmark_candidates(state)

    async def _run_vector_stage(max_hits: int, errors: list, confidence: float) -> tuple:
        """Stage 2: RetrievalServiceV3 (centrality + community ranking), with
        MiniLM-gateway fallback. Returns its own (vector_hits, evidence_items)
        rather than mutating the caller's lists — this coroutine is started
        via asyncio.create_task and runs concurrently with Stage 1 below (its
        inputs — kg_concepts/kg_expanded/user_input — don't depend on Stage
        1's output), so sharing mutable lists across both would race."""
        local_vector_hits: List[Dict[str, Any]] = []
        local_evidence: List[Dict[str, Any]] = []
        try:
            from api.models.v3_schemas import V3PipelineContext

            retrieval_v3 = await _get_retrieval_v3()
            ctx = V3PipelineContext(
                user_input=user_input,
                session_id=state.get("session_id", ""),
                user_id=state.get("user_id"),
            )
            seed_nodes = [
                c if isinstance(c, str) else c.get("id", "")
                for c in kg_concepts[:5]
            ]
            bundle = await retrieval_v3.retrieve(user_input, seed_nodes, ctx)

            for hit in bundle.vector_hits[:max_hits]:
                snippet = getattr(hit, "snippet", hit.id)
                local_vector_hits.append({"text": snippet, "score": hit.score})
                local_evidence.append({
                    "item_id": hit.id,
                    "title": snippet,
                    "text": f"Concept ({hit.id}): {snippet}",
                    "kg_depth": 2,
                    "vec_sim": hit.score,
                    "turns_ago": session_turn,
                })

            logger.info(
                f"[retrieve_node] RetrievalServiceV3: {len(local_vector_hits)} hits "
                f"(centrality+community ranked)"
            )

        except Exception as e:
            logger.warning(
                f"[retrieve_node] RetrievalServiceV3 unavailable, "
                f"falling back to MiniLM gateway: {e}"
            )
            # ── Fallback: MiniLM gateway ──────────────────────────────────
            try:
                from api.services.model_gateway import get_gateway

                gateway = await get_gateway()
                max_expanded = 10
                threshold = 0.3

                if retrieval_policy == "rapid" and len(errors) <= 2 and confidence >= 0.7:
                    max_expanded = 5
                    threshold = 0.35

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
                    # Call `similarity` directly, not the handler's own
                    # `invoke`: gateway.invoke already wraps the return in
                    # {"success", "data"}, so routing through invoke() nested
                    # the payload twice and this read {} every time — the
                    # MiniLM fallback silently contributed zero hits.
                    result = await gateway.invoke(
                        "minilm", "similarity",
                        {"query": user_input, "candidates": candidate_labels},
                    )
                    if result.get("success"):
                        sim_results = result.get("data") or []
                        for r in sim_results:
                            if r["score"] >= threshold:
                                local_vector_hits.append({"text": r["text"], "score": r["score"]})
                                local_evidence.append({
                                    "text": f"Semantic match: {r['text']}",
                                    "kg_depth": 2,
                                    "vec_sim": r["score"],
                                    "turns_ago": session_turn,
                                })

                        local_vector_hits = local_vector_hits[:max_hits]
                        logger.info(f"[retrieve_node] MiniLM fallback: {len(local_vector_hits)} hits")
            except Exception as e2:
                logger.warning(f"[retrieve_node] Vector search fully skipped: {e2}")

        return local_vector_hits, local_evidence

    # Decide + start Stage 2 now (before Stage 1 runs) — the decision only
    # depends on diagnosis_errors/confidence/policy, all already available,
    # never on Stage 1's output, so it can run concurrently with Stage 1
    # instead of waiting for it to finish first.
    vector_hits: List[Dict[str, Any]] = []
    stage2_task = None
    if not benchmark_candidates:
        _errors = state.get("diagnosis_errors", [])
        _confidence = float(state.get("diagnosis_confidence", 0.0) or 0.0)
        _is_multihop_task = benchmark_task == "multihop_qa"

        _do_vector_search = True
        _max_hits = 5
        if retrieval_policy == "rapid":
            if len(_errors) == 0 and _confidence >= 0.85 and not _is_multihop_task:
                _do_vector_search = False
            elif len(_errors) <= 2 and _confidence >= 0.72:
                _max_hits = 3

        if _do_vector_search:
            stage2_task = asyncio.create_task(
                _run_vector_stage(_max_hits, _errors, _confidence)
            )

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
        title = str(node.get("title") or "").strip()
        if not title:
            # No title means nothing readable to ground on — the id alone
            # ("concept:vocab.word.nerve") is noise in the prompt.
            continue
        keywords = str(node.get("keywords") or "").strip()
        relation = str(node.get("relation") or "related_to")
        text = f"Related concept ({relation}): {title}"
        if keywords:
            text = f"{text}. Keywords: {keywords}"
        evidence_items.append({
            "item_id": str(node.get("id") or title),
            "title": title,
            "text": text,
            "kg_depth": depth,
            "vec_sim": 0.0,
            "turns_ago": session_turn,
        })

    # Query KG with top-K node retrieval and bounded context packing to control prompt size.
    if not benchmark_candidates and not benchmark_context:
        try:
            from api.services.kg_service_v3 import get_kg_service

            learner_level = state.get("learner_profile", {}).get("level", "B1")
            top_k = max(1, _env_int("TRACECAG_KG_TOPK", 8))
            token_budget = max(32, _env_int("TRACECAG_KG_CONTEXT_TOKEN_BUDGET", 160))

            cache_key = _kg_cache_key(user_input, learner_level, top_k)
            queried_nodes = _kg_cache_get(cache_key)
            if queried_nodes is not None:
                try:
                    from api.services.telemetry import get_telemetry

                    get_telemetry().increment_counter(
                        "tracecag_shared_subgraph_cache_hit_total"
                    )
                except Exception:
                    pass
            if queried_nodes is None:
                kg = get_kg_service()
                # query_concepts() is a synchronous, in-memory call with no
                # await points of its own — running it inline would hold the
                # event loop for its full duration and starve the Stage 2
                # task (created above) of any chance to run concurrently.
                # run_in_executor hands it to a worker thread so Stage 2's
                # own awaits (network/model calls) can actually interleave.
                queried_nodes = await asyncio.get_event_loop().run_in_executor(
                    None, lambda: kg.query_concepts(user_input, learner_level=learner_level, top_k=top_k)
                )
                _kg_cache_set(cache_key, queried_nodes)

            packed_nodes = _pack_kg_nodes_for_context(queried_nodes, token_budget)
            for node in packed_nodes:
                title = str(node.get("title") or node.get("id") or "")
                keywords = str(node.get("keywords") or "")
                score = float(node.get("score") or 0.0)
                evidence_items.append({
                    "item_id": str(node.get("id") or title),
                    "title": title,
                    "text": f"Concept: {title}. Keywords: {keywords}",
                    "kg_depth": 1,
                    "vec_sim": max(0.0, min(1.0, score)),
                    "turns_ago": session_turn,
                })
        except Exception as kg_exc:
            logger.warning(f"[retrieve_node] KG top-K query skipped: {kg_exc}")

    for error in state.get("diagnosis_errors", [])[:3]:
        evidence_items.append({
            "text": f"Error: '{error.get('span', '')}' → '{error.get('correction', '')}' — {error.get('explanation', '')}",
            "kg_depth": 0,
            "vec_sim": 0.0,
            "turns_ago": 0,
        })

    if benchmark_candidates:
        evidence_items = []
        ranked_candidates = _rank_benchmark_candidates(
            user_input,
            benchmark_candidates,
            benchmark_ranker,
            benchmark_mode,
            adaptive_profile,
        )
        for candidate in ranked_candidates:
            final_score = float(candidate.get("fusion_score", candidate.get("vec_sim", 0.0)))
            evidence_item = {
                "item_id": candidate["item_id"],
                "title": candidate["title"],
                "text": candidate["text"],
                "kg_depth": candidate["kg_depth"],
                "vec_sim": final_score,
                "turns_ago": candidate["turns_ago"],
                "graph_score": float(candidate.get("graph_score") or 0.0),
                "memory_score": float(candidate.get("memory_score") or 0.0),
                "precomputed_score": final_score,
            }
            if relevant_ids:
                evidence_item["is_relevant"] = candidate["item_id"] in relevant_ids
            evidence_items.append(evidence_item)
    elif benchmark_context:
        evidence_items.insert(0, {
            "item_id": "benchmark_context",
            "title": "benchmark_context",
            "text": benchmark_context,
            "kg_depth": 0,
            "vec_sim": 1.0,
            "turns_ago": 0,
            "is_relevant": True,
        })

    # ── Stage 2 results: the task was already started (in parallel with
    # Stage 1) before Stage 1 began — await it here, capped to whatever's
    # left of vector_budget_ms measured from the same retrieve_start clock
    # Stage 1 uses. If it hasn't finished by then, cancel and treat as
    # exhausted rather than let one slow stage blow the whole node's budget.
    if stage2_task is not None:
        remaining_s = max(0.0, vector_budget_ms / 1000.0 - (time.monotonic() - retrieve_start))
        try:
            vector_hits, stage2_evidence = await asyncio.wait_for(stage2_task, timeout=remaining_s)
            evidence_items.extend(stage2_evidence)
        except asyncio.TimeoutError:
            stage2_task.cancel()
            budget_exhausted = True
            logger.warning("[retrieve_node] Vector stage exceeded budget, skipping its results")
    elif not benchmark_candidates:
        # do_vector_search was False (rapid-policy short-circuit) — not a
        # budget miss, nothing to flag.
        pass

    # ── Stage 3: L2 External Knowledge (Selective Retrieval) ─────────
    # Phân tích xem có nên ép buộc tìm kiếm bên ngoài không (Proactive Dynamic Retrieval)
    force_external = False
    dynamic_patterns = [
        r"\bhôm (qua|nay|kia)\b", r"\bmới (đây|nhất)\b", r"\bvừa mới\b",
        r"\brecently\b", r"\byesterday\b", r"\btoday\b", r"\blatest\b", r"\bcurrent\b",
        r"\bdo you know\b", r"\bnghe nói\b", r"\bbạn có biết\b", r"\bnews\b", r"\btin tức\b"
    ]
    if any(re.search(p, user_input, re.IGNORECASE) for p in dynamic_patterns):
        force_external = True
        logger.info("[retrieve_node] Dynamic intent detected. Forcing L2 Search.")

    # Kích hoạt L2 nếu (thiếu dữ liệu) HOẶC (phát hiện intent cần tin tức thực tế)
    if (len(evidence_items) < 3 or force_external) and not benchmark_candidates:
        try:
            doc_service = get_doc_intel_service()
            # Nếu force_external, ta có thể điều chỉnh query để search hiệu quả hơn
            search_query = user_input
            if force_external and len(user_input) < 100:
                # Bổ sung ngữ cảnh để search Tavily tốt hơn
                search_query = f"latest information about {user_input}"

            external_hits = await asyncio.wait_for(
                doc_service.query_l2(search_query), timeout=5.0
            )
            for hit in external_hits:
                # Tránh trùng lặp nếu đã có trong evidence_items
                if any(e.get("chunk_id") == hit["id"] for e in evidence_items):
                    continue

                evidence_items.append({
                    "item_id": f"ext_{hit['id']}",
                    "title": "External Knowledge",
                    "text": f"Context: {hit['content']}",
                    "kg_depth": 3, # Tầng sâu hơn KG
                    "vec_sim": hit["score"],
                    "turns_ago": session_turn,
                    "is_external": True,
                    "chunk_id": hit["id"]
                })
            if external_hits:
                logger.info(f"[retrieve_node] L2 Context injected: {len(external_hits)} chunks")
        except Exception as e3:
            logger.warning(f"[retrieve_node] L2 retrieval failed: {e3}")

    # ── Fusion scoring and ranking ───────────────────────────────────
    if _elapsed_ms() <= total_budget_ms:
        for item in evidence_items:
            if benchmark_candidates and "precomputed_score" in item:
                item["fusion_score"] = float(item.get("precomputed_score") or 0.0)
            else:
                item["fusion_score"] = _fusion_score(
                    kg_depth=item["kg_depth"],
                    vec_sim=item["vec_sim"],
                    last_used_turns_ago=item["turns_ago"],
                )
    else:
        budget_exhausted = True
        for item in evidence_items:
            if "fusion_score" not in item:
                item["fusion_score"] = float(item.get("vec_sim") or 0.0)

    evidence_items = _rank_with_online_ranker(
        question=user_input,
        evidence_items=evidence_items,
        allow_exploration=_adaptive_mode_enabled(state, benchmark_mode),
        benchmark_mode=benchmark_mode,
    )
    if (
        settings.LEARNER_STATE_MODE in {"read", "primary"}
        and not benchmark_candidates
        and evidence_items
    ):
        overlay_candidates = [
            {
                **item,
                "concept_id": str(item.get("item_id") or item.get("title") or ""),
                "relevance": float(item.get("fusion_score") or item.get("vec_sim") or 0.0),
            }
            for item in evidence_items
        ]
        evidence_items = rank_with_learner_overlay(
            overlay_candidates,
            dict(state.get("learner_concept_states") or {}),
            now=datetime.now(timezone.utc),
            top_k=len(overlay_candidates),
        )
    evidence_budget = _compute_evidence_budget(
        question=user_input,
        retrieval_policy=retrieval_policy,
        benchmark_mode=benchmark_mode,
        benchmark_candidates=bool(benchmark_candidates),
        adaptive_profile=adaptive_profile,
        benchmark_task=benchmark_task,
    )
    if benchmark_candidates and benchmark_task in {"multihop_qa", "retrieval_qa"}:
        evidence_items = _interleave_explicit_second_hop(evidence_items)
        top_evidence = _select_diverse_multihop_evidence(
            items=evidence_items,
            question=user_input,
            budget=evidence_budget,
        )
        shaped_evidence = []
        for idx, item in enumerate(top_evidence):
            text = str(item.get("text") or "")
            if idx >= 2:
                text = _benchmark_evidence_snippet(
                    question=user_input,
                    title=str(item.get("title") or ""),
                    text=text,
                )
            shaped_evidence.append({**item, "text": text})
        top_evidence = shaped_evidence
    else:
        top_evidence = evidence_items[:evidence_budget]
    retrieval_trace = []
    for idx, item in enumerate(top_evidence):
        trace_item = {
            "item_id": str(item.get("item_id") or item.get("title") or f"item_{idx}"),
            "title": str(item.get("title") or item.get("item_id") or ""),
            "text": str(item.get("text") or ""),
            "rank": idx + 1,
            "score": float(item.get("fusion_score") or 0.0),
        }
        if "is_relevant" in item:
            trace_item["is_relevant"] = bool(item["is_relevant"])
        retrieval_trace.append(trace_item)

    if benchmark_candidates:
        context_parts = []
        for item in top_evidence:
            title = str(item.get("title") or "").strip()
            text = str(item.get("text") or "").strip()
            context_parts.append(f"[{title}] {text}" if title else text)
        retrieved_context = "\n".join(part for part in context_parts if part).strip()
    elif benchmark_context and benchmark_task in {"multihop_qa", "retrieval_qa"}:
        retrieved_context = benchmark_context
    else:
        context_parts = [item["text"] for item in top_evidence]
        retrieved_context = "\n".join(context_parts) if context_parts else ""

    jit_soft_graph = str(state.get("jit_soft_graph") or "").strip()
    jit_graph_meta = dict(state.get("jit_graph_meta") or {})
    if jit_soft_graph:
        retrieved_context = (
            f"[JIT_SOFT_GRAPH]\n{jit_soft_graph}\n\n"
            f"{retrieved_context}".strip()
        )

    latency_ms = int((time.time() - start_time) * 1000)
    logger.info(
        f"[retrieve_node] {len(evidence_items)} candidates → top {len(top_evidence)} via fusion scoring"
        f" (mode={benchmark_mode or 'default'}, ranker={benchmark_ranker}, latency={latency_ms}ms)"
    )

    ranker_snapshot = get_retrieval_ranker().snapshot() if _ranker_enabled() else {}
    graph_update = dict(state.get("graph_update") or {})
    evidence_projection = [
        {"item_id": str(item.get("item_id") or ""), "title": str(item.get("title") or "")}
        for item in retrieval_trace
    ]
    evidence_version = stable_version_token(evidence_projection, prefix="evidence")
    # Scope by retrieval_policy, not just the question text: "full" (cag_vanilla)
    # and "rapid" (tracecag_rapid) select different top-k evidence for the SAME
    # question, but observe_dependency_tokens uses setdefault (first-write-wins)
    # on this key — without the policy in the key, whichever mode processes a
    # question first "poisons" the shared token, so every later mode's cache
    # entry for that question fails its own freshness recheck against a token
    # it never wrote (confirmed: retrieval_trace identical, only the recorded
    # dependency version differs across modes for the same query).
    query_scope = stable_version_token(
        f"{retrieval_policy}:{user_input.strip().lower()}", prefix="query"
    )
    state_hints = (state.get("benchmark_metadata") or {}).get("_tracecag_state") or {}
    source_version = str(state_hints.get("source_version") or evidence_version)

    return {
        "vector_hits": vector_hits,
        "retrieved_context": retrieved_context,
        "jit_soft_graph": jit_soft_graph or None,
        "jit_graph_meta": jit_graph_meta,
        "retrieval_trace": retrieval_trace,
        "adaptive_profile": adaptive_profile or None,
        "adaptive_features": adaptive_features,
        "adaptive_controller": adaptive_controller,
        "retrieval_meta": {
            "budget": {
                "kg_ms": kg_budget_ms,
                "vector_ms": vector_budget_ms,
                "fusion_ms": fusion_budget_ms,
                "total_ms": total_budget_ms,
                "elapsed_ms": _elapsed_ms(),
                "exhausted": budget_exhausted,
            },
            "fusion": {
                "alpha": _FUSION_ALPHA,
                "beta": _FUSION_BETA,
                "gamma": _FUSION_GAMMA,
                "recency_lambda": _RECENCY_LAMBDA,
            },
            "kg_topk": {
                "top_k": max(1, _env_int("TRACECAG_KG_TOPK", 8)),
                "context_token_budget": max(32, _env_int("TRACECAG_KG_CONTEXT_TOKEN_BUDGET", 160)),
                "query_cache_size": len(_KG_QUERY_CACHE),
            },
            "jit_graph": jit_graph_meta,
            "graph_update": {
                "latency_ms": int(graph_update.get("latency_ms") or 0),
                "nodes_added": int(graph_update.get("nodes_added") or 0),
                "edges_added": int(graph_update.get("edges_added") or 0),
            },
            "mode": benchmark_mode or "default",
            "ranker": benchmark_ranker,
            "learned_ranker": {
                "enabled": _ranker_enabled(),
                "blend": _clip01(_env_float("TRACECAG_RANKER_BLEND", 0.42)),
                "snapshot": ranker_snapshot,
            },
            "adaptive": {
                "profile": adaptive_profile or None,
                "features": adaptive_features,
                "controller": adaptive_controller,
            },
            "learner_state": {
                "mode": settings.LEARNER_STATE_MODE,
                "epoch": int(state.get("learner_state_epoch") or 0),
                "degraded": bool(state.get("learner_state_degraded") or False),
                "reason": state.get("learner_state_reason"),
                "latency_ms": float(state.get("learner_state_latency_ms") or 0.0),
                "concept_count": len(state.get("learner_concept_states") or {}),
            },
        },
        "models_used": ["retrieval_fusion"] + (["minilm"] if vector_hits else []),
        "dependency_events": [
            dependency_record(f"evidence:retrieval:{query_scope}", "evidence", evidence_version, "retrieval-fusion"),
            dependency_record(f"source:retrieval:{query_scope}", "source", source_version, "retrieval-source"),
        ],
    }
