"""
TraceCAG Node Functions - Enhanced with ModelGateway

Each node uses ModelGateway for:
1. Lazy loading: Models load on first use
2. Smart routing: Automatic model selection
3. Memory management: Auto unload idle models
4. Unified interface: Single gateway for all AI operations

Pipeline Flow:
INPUT → KG_EXPAND → DIAGNOSE → RETRIEVE → GENERATE → [VIETNAMESE] → [TTS] → END
"""

import asyncio
import logging
import os
import re
import json
import time
import math
from typing import AsyncGenerator, Dict, Any, List, Optional

from api.services.trace_cag.state import TraceCAGState, DiagnosisError
from api.services.trace_cag.evaluation_agent import EvaluationAgent
from api.services.trace_cag.retrieval_ranker import get_retrieval_ranker
from api.services.document_intelligence import get_doc_intel_service
from api.services.jit_graph_service import get_jit_graph_service
from api.services.llama_kv_service import get_local_llama_kv_service

from api.services.trace_cag.env_helpers import _env_flag, _env_float, _env_int, _clip01
from api.services.trace_cag.provider_state import _provider_is_disabled

# LLM client — httpx pooling and rate-limit throttling
from api.services.trace_cag.llm_client import _get_httpx_client, _throttled_post_json

# KG query cache utilities
from api.services.trace_cag.kg_utils import (
    _KG_QUERY_CACHE, _kg_cache_key, _kg_cache_get, _kg_cache_set,
    _pack_kg_nodes_for_context,
)

# PCC cache R/W helpers used by the generation path
from api.services.trace_cag.cache_utils import _detect_native_request, _write_cache_entry

# Façade re-exports: graph.py imports cache_gate_node from this module, and the
# cache-gate tests reach these helpers through the nodes_v2 namespace.
from api.services.trace_cag.cache_utils import (  # noqa: F401
    cache_gate_node,
    _build_graph_bucket,
    _extract_lightweight_graph_concepts,
    _infer_intent_pre_diagnosis,
    _profile_epoch,
)

from api.services.trace_cag.benchmark.adaptive import (
    _adaptive_mode_enabled, _choose_adaptive_profile,
)
from api.services.trace_cag.benchmark.ranking import (
    _select_diverse_multihop_evidence, _compute_evidence_budget,
    _rank_benchmark_candidates, _ranker_enabled, _rank_with_online_ranker,
    _build_benchmark_candidates, _update_ranker_from_generation,
)
from api.services.trace_cag.benchmark.qa_generation import (
    _generate_extractive_fallback_response,
    _generate_benchmark_qa_response,
)

logger = logging.getLogger(__name__)

_LOCAL_LLAMA_CORE_SYSTEM_PROMPT = (
    "You are Lexi, an expert English tutor. "
    "Provide grounded, concise and actionable feedback. "
    "If evidence is weak, state uncertainty explicitly."
)



# ============================================================
# MODEL GATEWAY INTEGRATION
# ============================================================

_gateway_instance = None
_retrieval_v3_instance = None


async def get_gateway():
    """Get or initialize the ModelGateway singleton"""
    global _gateway_instance

    if _gateway_instance is None:
        from api.services.model_gateway import get_model_gateway
        _gateway_instance = get_model_gateway()

    return _gateway_instance


async def _get_retrieval_v3():
    """Lazy singleton for RetrievalServiceV3 (centrality + community ranking)."""
    global _retrieval_v3_instance
    if _retrieval_v3_instance is None:
        from api.services.kg_service_v3 import get_kg_service
        from api.services.retrieval_service_v3 import RetrievalServiceV3
        _retrieval_v3_instance = RetrievalServiceV3(get_kg_service())
    return _retrieval_v3_instance


# ============================================================
# NODE 1: INPUT NODE
# ============================================================

async def input_node(state: TraceCAGState) -> Dict[str, Any]:
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
            import asyncio as _asyncio
            redis_client = await RedisClient.get_instance()

            user_id = state.get("user_id")
            session_id = state.get("session_id", "")

            # Fetch profile and history concurrently.
            async def _get_profile():
                if user_id:
                    try:
                        profile_cache = LearnerProfileCache(redis_client)
                        return await profile_cache.get_profile(user_id)
                    except Exception:
                        return None
                return None

            async def _get_history():
                if session_id:
                    try:
                        conv_cache = ConversationCache(redis_client)
                        return await conv_cache.get_history(session_id)
                    except Exception:
                        return []
                return []

            cached_profile, fetched_history = await _asyncio.gather(
                _get_profile(), _get_history()
            )
            if cached_profile:
                learner_profile = {**cached_profile, **learner_profile}
            conversation_history = fetched_history or []

        except Exception as e:
            logger.warning(f"Redis unavailable: {e}")
    
        latency_ms = int((time.time() - start_time) * 1000)
        
        return {
            "learner_profile": learner_profile,
            "conversation_history": conversation_history,
            "native_explanation_requested": _detect_native_request(user_input),
            "models_used": ["redis_cache"],
            "latency_ms": latency_ms,
        }
        
    except Exception as e:
        logger.error(f"[input_node] Error: {e}")
        return {"error": str(e)}



# ============================================================
# NODE 2: KNOWLEDGE GRAPH EXPANSION
# ============================================================

async def kg_expand_node(state: TraceCAGState) -> Dict[str, Any]:
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

        # ── Phase 1: Seed concept matching (fast O(words) lookup) ──────
        user_text = state.get("user_input", "").lower()

        # Phase 1a: Exact keyword lookup via inverted index (O(words_in_text))
        seed_exact = kg.get_seed_concepts_fast(user_text)
        # Phase 1a-semantic: TF-IDF cosine similarity (catches indirect references)
        seed_semantic = kg.semantic_seed_concepts(user_text, top_k=5)
        # Merge: exact first (higher confidence), then semantic fills gaps
        seed_concepts = list(dict.fromkeys(seed_exact + seed_semantic))

        # Grammar error patterns (Phase 1b)
        grammar_patterns = {
            # ── Subject-verb agreement ────────────────────────────────
            r"\bi goes\b": "concept:grammar.subject_verb_agreement",
            r"\b(you|we|they)\s+goes\b": "concept:grammar.subject_verb_agreement",
            r"\bhe go\b|\bshe go\b|\bit go\b": "concept:grammar.third_person_s",
            r"\bhe don't\b|\bshe don't\b|\bit don't\b": "concept:grammar.third_person_s",

            # ── Past tense errors ─────────────────────────────────────
            r"\byesterday\b.*\b(go|want|need|come|eat|buy|see)\b": "concept:grammar.past_time_markers",
            r"\blast (week|night|month|year).*\b(go|have|is|are)\b": "concept:grammar.past_simple",
            r"\bhave went\b|\bhas went\b|\bhave came\b|\bhas came\b": "concept:grammar.present_perfect",
            r"\bdid.*\b(went|came|saw|ate|ran|made|took)\b": "concept:grammar.past_simple",

            # ── Comparatives / superlatives ───────────────────────────
            r"\bmore better\b|\bmore worse\b|\bmore faster\b": "concept:grammar.comparatives",
            r"\bthe most best\b|\bthe most biggest\b|\bmore than more\b": "concept:grammar.superlatives",

            # ── Article errors (Vietnamese learner patterns) ──────────
            r"\ba apple\b|\ba elephant\b|\ba hour\b|\ba umbrella\b": "concept:grammar.articles_a_an",
            r"\bgo to school\b|\bgo to hospital\b|\bgo to market\b": "concept:error.article_omission",

            # ── Preposition errors ────────────────────────────────────
            r"\bgo to home\b|\barrived to\b|\bmarried with\b|\blisten\s+music\b": "concept:error.preposition_confusion",
            r"\bdepend of\b|\binterested of\b|\bat monday\b|\bin the night\b|\bon the morning\b": "concept:error.preposition_confusion",

            # ── Word order errors (Vietnamese SVO influence) ──────────
            r"\bI very (like|love|enjoy|want|hate)\b": "concept:error.word_order_svo",
            r"\balways I\b|\bnever I\b|\busually I\b|\bsometimes I (go|eat|like)\b": "concept:grammar.adverbs_frequency",

            # ── Modal errors ──────────────────────────────────────────
            r"\bcan to\b|\bshould to\b|\bmust to\b|\bwill to\b|\bwould to\b": "concept:grammar.modal_can_could",
            r"\bcan could\b|\bshould must\b": "concept:grammar.modal_must_should",

            # ── Continuous tense errors ───────────────────────────────
            r"\bI am go\b|\bhe is eat\b|\bshe is sleep\b|\bwe are go\b": "concept:grammar.present_continuous",
            r"\b(am|is|are)\s+\w+(?<!ing)\s+(now|currently|at the moment)\b": "concept:grammar.present_continuous",

            # ── Perfect continuous ────────────────────────────────────
            r"\bhave been (working|studying|living|waiting|doing|learning)\b": "concept:grammar.present_perfect_continuous",

            # ── Gerund / infinitive confusion ─────────────────────────
            r"\benjoy to\b|\bfinish to\b|\bavoid to\b|\bkeep to\b|\bconsider to\b": "concept:grammar.gerund_infinitive",
            r"\bwant (going|eating|sleeping|coming)\b|\bneed (going|coming)\b": "concept:grammar.gerund_infinitive",

            # ── Missing auxiliary (questions) ─────────────────────────
            r"\byou like\?\s*$|\bhe like\?\s*$|\bshe like\?\s*$|\byou know\?\s*$": "concept:error.missing_auxiliary",

            # ── Conditional errors ────────────────────────────────────
            r"\bif.*\bwill come\b|\bif.*\bwill be\b|\bif.*\bwill go\b": "concept:grammar.conditionals_first",
            r"\bif (I|he|she) would\b": "concept:grammar.conditionals_second",
            r"\bif (I|he|she) had\b.*\bwould have\b": "concept:grammar.conditionals_third",

            # ── Wish / regret ─────────────────────────────────────────
            r"\bi wish (I|he|she|we|they)\b|\bif only\b|\bi'd rather\b|\bwould rather\b": "concept:grammar.wish_regret",
            r"\bshould have\b|\bcould have\b|\bwould have\b": "concept:grammar.wish_regret",

            # ── Reported speech ───────────────────────────────────────
            r"\bsaid that\b|\btold (me|him|her|us|them) that\b": "concept:grammar.reported_speech",
            r"\btell to me\b|\bsay to me\b|\bhe say\b|\bshe say\b": "concept:error.tell_say_confusion",

            # ── Make vs do confusion ──────────────────────────────────
            r"\bmake homework\b|\bmake exercise\b|\bdo friends\b|\bdo a photo\b": "concept:error.make_do_confusion",

            # ── Demonstratives & question words ──────────────────────
            r"\b(what|where|when|who|why|how)\s+(do|does|is|are|was|were|did|have|has)\b": "concept:grammar.question_words",
            r"\b(this|that|these|those)\s+\w+\b": "concept:grammar.demonstratives",
            r"\bthere\s+(is|are|was|were)\b": "concept:grammar.there_is_are",

            # ── Possessives ───────────────────────────────────────────
            r"\b\w+'s\s+\w+\b": "concept:grammar.possessive_s",

            # ── Phrasal verbs ─────────────────────────────────────────
            r"\b(give up|look up|pick up|put off|run out|figure out|turn on|turn off|break down|come across)\b": "concept:grammar.phrasal_verbs_common",

            # ── Topic detection — vocabulary domains ──────────────────
            r"\b(social media|instagram|tiktok|facebook|twitter|post|hashtag|viral|trending)\b": "concept:vocab.social_media",
            r"\b(bus|train|metro|subway|taxi|flight|commute|station|platform)\b": "concept:vocab.transport",
            r"\b(happy|sad|angry|excited|nervous|scared|worried|proud|embarrassed|lonely)\b": "concept:vocab.emotions_feelings",
            r"\b(job interview|cv|resume|cover letter|salary|hired|applicant)\b": "concept:conversation.job_interview",
            r"\b(culture|tradition|custom|festival|etiquette|ceremony|heritage)\b": "concept:vocab.culture_customs",
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
            "graph_update": {
                "latency_ms": latency_ms,
                "nodes_added": len(seed_concepts) + len(expanded_nodes),
                "edges_added": len(paths),
            },
            "models_used": ["kuzu_kg_bestfirst"],
        }

    except Exception as e:
        logger.error(f"[kg_expand_node] Error: {e}")
        return {
            "kg_seed_concepts": [],
            "kg_expanded_nodes": [],
            "kg_paths": [],
            "graph_update": {
                "latency_ms": int((time.time() - start_time) * 1000),
                "nodes_added": 0,
                "edges_added": 0,
            },
        }


# ============================================================
# NODE 3: DIAGNOSIS (AI-POWERED via ModelGateway)
# ============================================================

async def diagnose_node(state: TraceCAGState) -> Dict[str, Any]:
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
    benchmark_task = state.get("benchmark_task")

    if benchmark_task in {"multihop_qa", "retrieval_qa"}:
        return {
            "diagnosis_intent": "ask",
            "diagnosis_errors": [],
            "diagnosis_root_causes": [],
            "diagnosis_confidence": 1.0,
            "grammar_score": 1.0,
            "fluency_score": 1.0,
            "vocabulary_level": EvaluationAgent.estimate_vocab_level(user_text),
            "models_used": ["benchmark_bypass"],
        }

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
            "vocabulary_level": EvaluationAgent.estimate_vocab_level(user_text),
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

        # Call local Qwen via ModelGateway (lazy loads if needed).
        # If local Qwen is unavailable (e.g., missing local weights), fall back
        # to Groq (Qwen3) before degrading to rules.
        result = await gateway.execute_task(
            "chat",
            {
                "message": diagnosis_prompt,
                "system": "You are an English grammar analyzer. Return only valid JSON.",
                "max_tokens": 150,
            },
        )
        
        # Parse AI response
        errors: List[DiagnosisError] = []
        root_causes: List[str] = []
        intent = "correct"
        confidence = 0.9
        grammar_score = 0.8
        fluency_score = 0.8
        
        used_model = "qwen_grammar"

        if not (result.get("success") and result.get("data")):
            from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage
            groq_key = await get_available_groq_key(estimated_tokens=150)
            groq_model = os.getenv("GROQ_MODEL_DIAGNOSE", os.getenv("GROQ_MODEL", "qwen/qwen3-32b"))
            if groq_key:
                try:
                    import httpx

                    messages = [
                        {"role": "system", "content": "You are an English grammar analyzer. Return only valid JSON."},
                        {"role": "user", "content": diagnosis_prompt},
                    ]
                    resp = await _throttled_post_json(
                        provider="groq",
                        url="https://api.groq.com/openai/v1/chat/completions",
                        headers={"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"},
                        payload={"model": groq_model, "messages": messages, "max_tokens": 150, "temperature": 0.0},
                        httpx_module=httpx,
                        timeout=20.0,
                    )
                    if resp is not None and resp.status_code == 200:
                        data = resp.json()
                        tokens = data.get("usage", {}).get("total_tokens", 150)
                        await record_groq_key_usage(groq_key, tokens)
                        content = data["choices"][0]["message"]["content"]
                        result = {"success": True, "data": content}
                        used_model = f"groq/{groq_model}"
                    else:
                        logger.warning(
                            f"[diagnose_node] Groq returned {getattr(resp, 'status_code', 'n/a')}: "
                            f"{getattr(resp, 'text', '')[:200]}"
                        )
                except Exception as e:
                    logger.warning(f"[diagnose_node] Groq fallback failed: {e}")

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
            "vocabulary_level": EvaluationAgent.estimate_vocab_level(user_text),
            "models_used": [used_model],
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
            "vocabulary_level": EvaluationAgent.estimate_vocab_level(user_text),
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
# PARALLEL NODE: KG_EXPAND + DIAGNOSE concurrent (paper Alg. 3+4)
# ============================================================

async def kg_diagnose_node(state: TraceCAGState) -> Dict[str, Any]:
    """
    Run kg_expand_node and diagnose_node concurrently via asyncio.gather.

    Both nodes are I/O-bound (KuzuDB and ModelGateway respectively) and read
    from the same state snapshot without conflicting writes.

    Latency improvement: max(t_kg, t_diag) instead of t_kg + t_diag.
    """
    kg_result, diag_result, jit_result = await asyncio.gather(
        kg_expand_node(state),
        diagnose_node(state),
        _jit_graph_extract_node(state),
    )
    merged: Dict[str, Any] = {}
    merged.update(kg_result or {})
    merged.update(diag_result or {})
    merged.update(jit_result or {})
    # Merge the accumulator list explicitly (avoid overwrite by dict.update)
    merged["models_used"] = (
        list((kg_result or {}).get("models_used", []))
        + list((diag_result or {}).get("models_used", []))
        + list((jit_result or {}).get("models_used", []))
    )
    return merged


async def _jit_graph_extract_node(state: TraceCAGState) -> Dict[str, Any]:
    """Extract compact JIT graph payload for downstream retrieval/generation."""
    user_input = str(state.get("user_input") or "").strip()
    if not user_input:
        return {"jit_soft_graph": None, "jit_graph_meta": {}}

    try:
        service = get_jit_graph_service()
        result = await service.extract_soft_graph(user_input)
        payload = {
            "jit_soft_graph": result.get("soft_graph") or None,
            "jit_graph_meta": {
                "enabled": bool(result.get("enabled", False)),
                "model": str(result.get("model") or "jit_graph"),
                "latency_ms": float(result.get("latency_ms") or 0.0),
                "node_count": int(result.get("node_count") or 0),
                "edge_count": int(result.get("edge_count") or 0),
                "cache_hit": bool(result.get("cache_hit", False)),
            },
        }
        if result.get("enabled"):
            payload["models_used"] = [str(result.get("model") or "jit_graph")]
        return payload
    except Exception as exc:
        logger.warning("[_jit_graph_extract_node] JIT extraction skipped: %s", exc)
        return {
            "jit_soft_graph": None,
            "jit_graph_meta": {"enabled": False, "error": str(exc)},
        }

_FUSION_ALPHA = 0.5   # KG structural relevance weight
_FUSION_BETA = 0.3    # Vector similarity weight
_FUSION_GAMMA = 0.2   # Recency bonus weight
_RECENCY_LAMBDA = 0.01  # Decay rate for recency bonus


# ============================================================
# PCC: PROGRESSIVE COMPLEXITY CONTROL
# ============================================================

def _compute_difficulty_ramp(session_turn: int, overall_score: float) -> str:
    """
    PCC difficulty signal based on session progress + learner performance.

    Returns: 'gentle' | 'standard' | 'challenging'
      - gentle:     first 3 turns or score < 0.50
      - standard:   turns 3-8 or score 0.50-0.70
      - challenging: turns 8+ with score >= 0.70
    """
    if session_turn < 3 or overall_score < 0.50:
        return "gentle"
    if session_turn < 8 or overall_score < 0.70:
        return "standard"
    return "challenging"


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



# ============================================================
# NODE 4: BUDGETED HYBRID RETRIEVAL (paper Alg. 5)
# ============================================================

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

    # Query KG with top-K node retrieval and bounded context packing to control prompt size.
    if not benchmark_candidates and not benchmark_context:
        try:
            from api.services.kg_service_v3 import get_kg_service

            learner_level = state.get("learner_profile", {}).get("level", "B1")
            top_k = max(1, _env_int("TRACECAG_KG_TOPK", 8))
            token_budget = max(32, _env_int("TRACECAG_KG_CONTEXT_TOKEN_BUDGET", 160))

            cache_key = _kg_cache_key(user_input, learner_level, top_k)
            queried_nodes = _kg_cache_get(cache_key)
            if queried_nodes is None:
                kg = get_kg_service()
                queried_nodes = kg.query_concepts(user_input, learner_level=learner_level, top_k=top_k)
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
            evidence_items.append({
                "item_id": candidate["item_id"],
                "title": candidate["title"],
                "text": candidate["text"],
                "kg_depth": candidate["kg_depth"],
                "vec_sim": final_score,
                "turns_ago": candidate["turns_ago"],
                "graph_score": float(candidate.get("graph_score") or 0.0),
                "memory_score": float(candidate.get("memory_score") or 0.0),
                "precomputed_score": final_score,
                "is_relevant": candidate["item_id"] in relevant_ids,
            })
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

    # ── Stage 2: RetrievalServiceV3 (centrality + community ranking) ─────
    vector_hits = []
    if not benchmark_candidates and _elapsed_ms() <= (kg_budget_ms + vector_budget_ms):
        errors = state.get("diagnosis_errors", [])
        confidence = float(state.get("diagnosis_confidence", 0.0) or 0.0)
        is_multihop_task = benchmark_task == "multihop_qa"

        do_vector_search = True
        max_hits = 5

        if retrieval_policy == "rapid":
            if len(errors) == 0 and confidence >= 0.85 and not is_multihop_task:
                do_vector_search = False
            elif len(errors) <= 2 and confidence >= 0.72:
                max_hits = 3

        if do_vector_search and _elapsed_ms() <= (kg_budget_ms + vector_budget_ms):
            # ── Primary: RetrievalServiceV3 (centrality + community diversity) ──
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
                    vector_hits.append({"text": snippet, "score": hit.score})
                    evidence_items.append({
                        "item_id": hit.id,
                        "title": snippet,
                        "text": f"Concept ({hit.id}): {snippet}",
                        "kg_depth": 2,
                        "vec_sim": hit.score,
                        "turns_ago": session_turn,
                    })

                logger.info(
                    f"[retrieve_node] RetrievalServiceV3: {len(vector_hits)} hits "
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
                                        "kg_depth": 2,
                                        "vec_sim": r["score"],
                                        "turns_ago": session_turn,
                                    })

                            vector_hits = vector_hits[:max_hits]
                            logger.info(f"[retrieve_node] MiniLM fallback: {len(vector_hits)} hits")
                except Exception as e2:
                    logger.warning(f"[retrieve_node] Vector search fully skipped: {e2}")
    elif not benchmark_candidates:
        budget_exhausted = True

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
    evidence_budget = _compute_evidence_budget(
        question=user_input,
        retrieval_policy=retrieval_policy,
        benchmark_mode=benchmark_mode,
        benchmark_candidates=bool(benchmark_candidates),
        adaptive_profile=adaptive_profile,
    )
    if benchmark_candidates and benchmark_task in {"multihop_qa", "retrieval_qa"}:
        top_evidence = _select_diverse_multihop_evidence(
            items=evidence_items,
            question=user_input,
            budget=evidence_budget,
        )
    else:
        top_evidence = evidence_items[:evidence_budget]
    retrieval_trace = [
        {
            "item_id": str(item.get("item_id") or item.get("title") or f"item_{idx}"),
            "title": str(item.get("title") or item.get("item_id") or ""),
            "text": str(item.get("text") or ""),
            "rank": idx + 1,
            "score": float(item.get("fusion_score") or 0.0),
            "is_relevant": bool(item.get("is_relevant") or False),
        }
        for idx, item in enumerate(top_evidence)
    ]

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
        },
        "models_used": ["retrieval_fusion"] + (["minilm"] if vector_hits else []),
    }


# ============================================================
# STREAMING HELPERS: Build prompt + stream tokens from LLM
# ============================================================

def build_generation_prompt(
    state: Dict[str, Any],
) -> tuple[str, List[Dict[str, Any]]]:
    """Extract (system_prompt, messages) from raw pipeline state.

    Used by the streaming endpoint so it can call the LLM with streaming
    enabled after the rest of the pipeline (KG, diagnosis, retrieval) has
    prepared the context.
    """
    errors = state.get("diagnosis_errors", [])
    intent = state.get("diagnosis_intent", "correct")
    level = (state.get("learner_profile") or {}).get("level", "B1")
    user_input = str(state.get("user_input") or "")
    context = str(state.get("retrieved_context") or "")
    vietnamese_hint = state.get("vietnamese_hint")
    session_turn = len(state.get("conversation_history") or [])
    prev_overall = state.get("overall_score", 0.5)
    fluency_score = state.get("fluency_score", 0.8)
    error_count = len(errors)

    difficulty = _compute_difficulty_ramp(session_turn, prev_overall)

    if intent == "explain" and fluency_score > 0.7:
        strategy = "socratic"
    elif error_count == 0:
        strategy = "praise"
    elif error_count <= 2:
        strategy = "feedback"
    else:
        strategy = "scaffold"

    system_prompt = (
        "You are Lexi 🦜, a cheerful, witty parrot who is an expert English tutor.\n"
        "You speak in a warm, encouraging tone — like a fun game character guiding an adventure.\n"
        "Keep responses concise (2-4 sentences). Use the knowledge context provided.\n"
        "Gently correct mistakes with encouraging context.\n"
        f"The learner's current CEFR level is: {level}\n"
        f"Difficulty setting for this turn: {difficulty}\n"
    )
    if context:
        system_prompt += f"\n--- Knowledge Graph Context ---\n{context}\n"

    if strategy == "socratic":
        system_prompt += (
            "\nStrategy: SOCRATIC. Guide through short questions, don't reveal answer.\n"
        )
        if errors:
            hints = "\n".join(
                f"- '{e.get('span','')}' → '{e.get('correction','')}'"
                for e in errors[:3]
            )
            system_prompt += f"\n--- Errors (hints only) ---\n{hints}\n"
    elif errors:
        errs_text = "\n".join(
            f"- '{e.get('span','')}' → '{e.get('correction','')}' ({e.get('explanation','')})"
            for e in errors[:3]
        )
        system_prompt += f"\n--- Errors Found ---\n{errs_text}\n"
        system_prompt += f"Strategy: {strategy}. Weave corrections naturally.\n"
    else:
        system_prompt += "\nNo errors found — praise the learner's effort!\n"

    if vietnamese_hint:
        system_prompt += f"\n--- Vietnamese Hint ---\n{vietnamese_hint}\n"

    messages: List[Dict[str, Any]] = [{"role": "system", "content": system_prompt}]
    for msg in (state.get("conversation_history") or [])[-12:]:
        role = msg.get("role")
        content = msg.get("content", "")
        if role and content:
            messages.append({"role": role, "content": content})
        elif msg.get("user"):
            messages.append({"role": "user", "content": msg["user"]})
            if msg.get("ai"):
                messages.append({"role": "assistant", "content": msg["ai"]})
    messages.append({"role": "user", "content": user_input})

    return system_prompt, messages


async def stream_llm_tokens(
    *,
    system_prompt: str,
    messages: List[Dict[str, Any]],
    user_input: str,
) -> "AsyncGenerator[str, None]":
    """Stream tokens from Groq (preferred) then Gemini as fallback.

    Yields raw text deltas as they arrive from the provider.
    Falls back silently to Gemini if Groq is unavailable or rate-limited.
    """

    async def _try_groq() -> "AsyncGenerator[str, None]":
        from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage

        groq_key = await get_available_groq_key(estimated_tokens=512)
        groq_model = os.getenv("GROQ_MODEL", "qwen/qwen3-32b")
        if not groq_key or _provider_is_disabled("groq"):
            return

        client = _get_httpx_client("groq")
        tokens_yielded = 0
        try:
            async with client.stream(
                "POST",
                "https://api.groq.com/openai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {groq_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": groq_model,
                    "messages": messages,
                    "max_tokens": 512,
                    "temperature": 0.7,
                    "stream": True,
                },
                timeout=25.0,
            ) as resp:
                if resp.status_code != 200:
                    logger.warning("[stream_llm_tokens] Groq status %d", resp.status_code)
                    return
                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    data = line[6:]
                    if data.strip() == "[DONE]":
                        break
                    try:
                        obj = json.loads(data)
                        delta = obj["choices"][0]["delta"].get("content") or ""
                        if delta:
                            tokens_yielded += len(delta.split())
                            yield delta
                    except Exception as _exc:
                        logger.debug("[nodes_v2] ignored: %s", _exc)
                        pass
            await record_groq_key_usage(groq_key, max(50, tokens_yielded + 50))
        except Exception as exc:
            logger.warning("[stream_llm_tokens] Groq stream error: %s", exc)

    async def _try_gemini() -> "AsyncGenerator[str, None]":
        gemini_key = os.getenv("GEMINI_API_KEY", "")
        if not gemini_key or _provider_is_disabled("gemini"):
            return

        url = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"gemini-2.0-flash:streamGenerateContent?key={gemini_key}&alt=sse"
        )
        request_body = {
            "contents": [{"role": "user", "parts": [{"text": user_input}]}],
            "systemInstruction": {"parts": [{"text": system_prompt}]},
        }
        client = _get_httpx_client("gemini")
        try:
            async with client.stream(
                "POST", url, json=request_body, timeout=25.0
            ) as resp:
                if resp.status_code != 200:
                    logger.warning("[stream_llm_tokens] Gemini status %d", resp.status_code)
                    return
                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    data = line[6:]
                    try:
                        obj = json.loads(data)
                        text = (
                            obj.get("candidates", [{}])[0]
                            .get("content", {})
                            .get("parts", [{}])[0]
                            .get("text", "")
                        )
                        if text:
                            yield text
                    except Exception as _exc:
                        logger.debug("[nodes_v2] ignored: %s", _exc)
                        pass
        except Exception as exc:
            logger.warning("[stream_llm_tokens] Gemini stream error: %s", exc)

    # Try Groq first; if it yields nothing, fall back to Gemini
    got_tokens = False
    async for token in _try_groq():
        got_tokens = True
        yield token

    if not got_tokens:
        async for token in _try_gemini():
            yield token


# ============================================================
# NODE 5: GROUNDED GENERATION (LLM call with context)
# ============================================================

async def generate_node(state: TraceCAGState) -> Dict[str, Any]:
    """
    Generate the tutor response using LLM grounded in KG evidence.
    
    This node calls the LLM fallback chain (Groq → Gemini → Ollama)
    with the Lexi persona, KG context, and diagnosis data injected
    into the system prompt. This is the SINGLE place where LLM
    generation happens — callers should NOT make a separate LLM call.
    """
    # When the streaming endpoint handles generation externally, skip this node.
    if state.get("generation_policy") == "skip":
        return {}

    logger.info("[generate_node] Generating grounded tutor response...")
    start_time = time.time()

    errors = state.get("diagnosis_errors", [])
    intent = state.get("diagnosis_intent", "correct")
    level = state.get("learner_profile", {}).get("level", "B1")
    user_input = state.get("user_input", "")
    context = state.get("retrieved_context", "")
    jit_soft_graph = str(state.get("jit_soft_graph") or "").strip()
    vietnamese_hint = state.get("vietnamese_hint")
    benchmark_task = state.get("benchmark_task")

    if benchmark_task in {"multihop_qa", "retrieval_qa"}:
        return await _generate_benchmark_qa_response(state, start_time)
    
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
        logger.warning("[generate_node] generation_policy='template' is deprecated; using extractive policy")
        generation_policy = "extractive"

    if generation_policy == "extractive":
        response = _generate_extractive_fallback_response(errors, strategy, user_input, context)
        model_used = "extractive_policy"

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
        vocab_level = state.get("vocabulary_level", "B1")
        overall_score = EvaluationAgent.compute_overall_score(grammar_score, fluency_score, vocab_level)

        _update_ranker_from_generation(
            question=user_input,
            response=response,
            retrieval_trace=list(state.get("retrieval_trace") or []),
        )

        if state.get("cache_policy", "on") == "on":
            try:
                await _write_cache_entry(state, response, strategy, errors, overall_score, context, model_used=model_used)
            except Exception as e:
                logger.debug(f"[generate_node] Cache write failed: {e}")

        latency_ms = int((time.time() - start_time) * 1000)

        return {
            "tutor_response": response,
            "strategy": strategy,
            "next_action": next_action,
            "overall_score": overall_score,
            "ttft_ms": latency_ms,
            "models_used": [model_used],
        }
    
    # Build system prompt with Lexi persona + grounded context
    session_turn = len(state.get("conversation_history", []))
    prev_overall = state.get("overall_score", 0.5)
    difficulty = _compute_difficulty_ramp(session_turn, prev_overall)

    system_prompt = (
        "You are Lexi 🦜, a cheerful, witty parrot who is an expert English tutor.\n"
        "You speak in a warm, encouraging tone — like a fun game character guiding an adventure.\n"
        "Keep responses concise (2-4 sentences). Use the knowledge context provided.\n"
        "Gently correct mistakes with encouraging context.\n"
        f"The learner's current CEFR level is: {level}\n"
        f"Difficulty setting for this turn: {difficulty}\n"
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

    response = ""
    model_used = "llm_unavailable"

    local_llama_enabled = _env_flag("TRACECAG_ENABLE_LOCAL_LLAMA_KV", False)
    if local_llama_enabled and not response:
        try:
            local_llama = get_local_llama_kv_service()
            local_result = await local_llama.generate(
                session_id=str(state.get("session_id") or "default"),
                core_system_prompt=_LOCAL_LLAMA_CORE_SYSTEM_PROMPT,
                dynamic_system_prompt=system_prompt,
                user_query=user_input,
                soft_graph="" if "[JIT_SOFT_GRAPH]" in context else jit_soft_graph,
            )
            if local_result and str(local_result.get("text") or "").strip():
                response = str(local_result.get("text") or "").strip()
                model_used = str(local_result.get("model") or "llama_cpp_kv")
        except Exception as e:
            logger.warning(f"[generate_node] Local llama KV path failed, fallback to provider chain: {e}")
    
    # Call LLM via fallback chain (Groq → Gemini → Ollama)
    if not response:
        response = ""
        model_used = "llm_unavailable"
    
    try:
        import httpx

        messages = [{"role": "system", "content": system_prompt}]

        # Inject conversation history (last 6 turns = up to 12 messages)
        history = state.get("conversation_history", [])
        for msg in history[-12:]:
            role = msg.get("role")
            content = msg.get("content", "")
            if role and content:
                # Standard {"role": "user"/"assistant", "content": "..."} format
                messages.append({"role": role, "content": content})
            elif msg.get("user"):
                # ConversationCache {"user": "...", "ai": "..."} format
                messages.append({"role": "user", "content": msg["user"]})
                if msg.get("ai"):
                    messages.append({"role": "assistant", "content": msg["ai"]})

        messages.append({"role": "user", "content": user_input})
        
        if not response:
            # Race Groq and Gemini concurrently; first successful response wins.
            # Ollama is kept as last-resort with a tighter 15s timeout.
            import asyncio as _asyncio
            from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage

            groq_key = await get_available_groq_key(estimated_tokens=512)
            groq_model = os.getenv("GROQ_MODEL", "qwen/qwen3-32b")
            gemini_key = os.getenv("GEMINI_API_KEY", "")

            async def _try_groq():
                if not groq_key:
                    return None, None
                try:
                    resp = await _throttled_post_json(
                        provider="groq",
                        url="https://api.groq.com/openai/v1/chat/completions",
                        headers={"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"},
                        payload={"model": groq_model, "messages": messages, "max_tokens": 512, "temperature": 0.7},
                        httpx_module=httpx,
                        timeout=20.0,
                    )
                    if resp is not None and resp.status_code == 200:
                        data = resp.json()
                        tokens = data.get("usage", {}).get("total_tokens", 500)
                        await record_groq_key_usage(groq_key, tokens)
                        return data["choices"][0]["message"]["content"], f"groq/{groq_model}"
                except Exception as e:
                    logger.warning(f"[generate_node] Groq failed: {e}")
                return None, None

            async def _try_gemini():
                if not gemini_key:
                    return None, None
                try:
                    gemini_contents = [{"role": "user", "parts": [{"text": user_input}]}]
                    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={gemini_key}"
                    request_body = {
                        "contents": gemini_contents,
                        "systemInstruction": {"parts": [{"text": system_prompt}]},
                    }
                    resp = await _throttled_post_json(
                        provider="gemini",
                        url=url,
                        payload=request_body,
                        httpx_module=httpx,
                        timeout=20.0,
                    )
                    if resp is not None and resp.status_code == 200:
                        candidates = resp.json().get("candidates", [])
                        if candidates:
                            return candidates[0]["content"]["parts"][0]["text"], "gemini-2.0-flash"
                except Exception as e:
                    logger.warning(f"[generate_node] Gemini failed: {e}")
                return None, None

            # Launch both concurrently; pick first non-None result.
            tasks = [_asyncio.ensure_future(_try_groq()), _asyncio.ensure_future(_try_gemini())]
            done, pending = await _asyncio.wait(tasks, return_when=_asyncio.FIRST_COMPLETED)
            for task in done:
                try:
                    _text, _model = task.result()
                    if _text:
                        response = _text
                        model_used = _model
                        break
                except Exception as _exc:
                    logger.debug("[nodes_v2] ignored: %s", _exc)
                    pass
            # If winner found, cancel the loser immediately.
            if response:
                for p in pending:
                    p.cancel()
            else:
                # Wait for the second one too before falling back to Ollama.
                if pending:
                    done2, _ = await _asyncio.wait(pending, timeout=15.0)
                    for task in done2:
                        try:
                            _text, _model = task.result()
                            if _text:
                                response = _text
                                model_used = _model
                                break
                        except Exception as _exc:
                            logger.debug("[nodes_v2] ignored: %s", _exc)
                            pass

            # Ollama — last resort, tight 15s timeout.
            if not response:
                from api.core.config import settings
                ollama_url = settings.OLLAMA_BASE_URL
                ollama_model = os.getenv("OLLAMA_MODEL", "lexilingo-qwen3-1.7b")
                try:
                    resp = await _throttled_post_json(
                        provider="ollama",
                        url=f"{ollama_url}/api/chat",
                        payload={
                            "model": ollama_model,
                            "messages": messages,
                            "stream": False,
                            "options": {"num_predict": 256, "temperature": 0.7},
                        },
                        httpx_module=httpx,
                        timeout=15.0,
                        max_retries=1,
                    )
                    if resp is not None and resp.status_code == 200:
                        response = resp.json().get("message", {}).get("content", "")
                        model_used = f"ollama/{ollama_model}"
                except Exception as e:
                    logger.warning(f"[generate_node] Ollama failed: {e}")
    
    except Exception as e:
        logger.error(f"[generate_node] LLM chain error: {e}")
    
    # 4. Deterministic extractive fallback
    if not response:
        response = _generate_extractive_fallback_response(errors, strategy, user_input, context)
        model_used = "extractive_fallback"
    
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
    vocab_level = state.get("vocabulary_level", "B1")
    overall_score = EvaluationAgent.compute_overall_score(grammar_score, fluency_score, vocab_level)

    _update_ranker_from_generation(
        question=user_input,
        response=response,
        retrieval_trace=list(state.get("retrieval_trace") or []),
    )

    # Generate personalized practice exercises via ContentAutoGenerator (cag_service)
    action_plan = []
    if errors or intent == "practice":
        try:
            from api.services.cag_service import ContentAutoGenerator
            cag_gen = ContentAutoGenerator()
            err_types = [err.get("type", "grammar") for err in errors if isinstance(err, dict)]
            if not err_types:
                err_types = ["grammar"]
            
            first_err_type = err_types[0] if errors else "vocabulary"
            if "vocab" in first_err_type.lower() or intent == "practice":
                vocab_ex = cag_gen.generate_vocabulary_exercise(
                    level=level,
                    error_patterns=err_types if errors else None,
                    count=3
                )
                action_plan.append({
                    "action": "practice",
                    "type": "vocabulary",
                    "concept": vocab_ex.get("topic", ""),
                    "count": len(vocab_ex.get("words", [])),
                    "exercise": vocab_ex
                })
            else:
                grammar_drill = cag_gen.generate_grammar_drill(
                    level=level,
                    error_patterns=err_types,
                    count=3
                )
                action_plan.append({
                    "action": "practice",
                    "type": "grammar",
                    "concept": grammar_drill.get("grammar_point", ""),
                    "count": len(grammar_drill.get("exercises", [])),
                    "exercise": grammar_drill
                })
        except Exception as cag_err:
            logger.warning(f"[generate_node] Failed to generate CAG practice: {cag_err}")

    state["action_plan"] = action_plan

    # Store response in Redis cache for future hits
    if state.get("cache_policy", "on") == "on":
        try:
            # ── Tiered Cache Management (L0/L1 Promotion) ─────────────
            # Nếu thông tin từ L2 được sử dụng, kiểm tra thăng hạng
            doc_service = get_doc_intel_service()
            trace = state.get("retrieval_trace", [])
            is_l2_used = any(t.get("item_id", "").startswith("ext_") for t in trace[:3])
            
            if is_l2_used:
                for t in trace[:3]:
                    if t.get("item_id", "").startswith("ext_"):
                        chunk_id = str(t.get("item_id") or "").replace("ext_", "")
                        if doc_service.should_promote_to_cache(chunk_id):
                            logger.info(f"[cache_promotion] Chunk {chunk_id[:8]} promoted to L1 cache")
                            await _write_cache_entry(state, response, strategy, errors, overall_score, context)
                            break
            else:
                # Mặc định cache cho các luồng KG/Rules để tối ưu tốc độ
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
        "action_plan": action_plan,
        "ttft_ms": latency_ms,
        "models_used": [model_used],
    }




# ============================================================
# NODE 6: NATIVE LANGUAGE HINT (AI-POWERED, Lazy Load)
# ============================================================

async def vietnamese_node(state: TraceCAGState) -> Dict[str, Any]:
    """
    Generate a short native-language hint for the learner.

    Triggered when:
    - Learner is A1/A2 and errors are present
    - Learner explicitly requests a native-language explanation

    Strategy (in order):
    1. Qwen via ModelGateway  (local, fast)
    2. Gemini via ModelGateway (cloud fallback)
    3. Hardcoded Vietnamese strings (last resort)

    The hint is a supplement — the main tutor_response remains in English.
    """
    logger.info("[vietnamese_node] Generating native-language hint...")
    start_time = time.time()

    errors = state.get("diagnosis_errors", [])
    learner_profile = state.get("learner_profile", {})
    level = learner_profile.get("level", "B1")
    native_language = learner_profile.get("native_language", "Vietnamese")

    try:
        gateway = await get_gateway()

        # Build prompt in the learner's native language
        if errors:
            error = errors[0]
            hint_prompt = (
                f"Briefly explain this English grammar error to a {level}-level learner "
                f"in {native_language} (2-3 sentences max):\n\n"
                f"Error: \"{error.get('span', '')}\" → \"{error.get('correction', '')}\"\n"
                f"Type: {error.get('type', 'unknown')}\n"
                f"English explanation: {error.get('explanation', '')}\n\n"
                f"Include a simple example. Do NOT switch to English."
            )
        else:
            hint_prompt = (
                f"In {native_language}, briefly praise the learner for writing correct English. "
                f"1-2 sentences only."
            )

        system_prompt = (
            f"You are a friendly English tutor. "
            f"Respond ONLY in {native_language}. Keep it short and encouraging."
        )

        # --- Attempt 1: Qwen ---
        native_hint: Optional[str] = None
        models_used: list[str] = []

        qwen_result = await gateway.execute_task(
            "chat",
            {
                "message": hint_prompt,
                "system": system_prompt,
                "max_tokens": 200,
            },
        )
        if qwen_result.get("success") and qwen_result.get("data"):
            raw = qwen_result["data"]
            native_hint = raw if isinstance(raw, str) else raw.get("text") or raw.get("response", "")
            models_used.append("qwen_native")

        # --- Attempt 2: Gemini fallback ---
        if not native_hint and "gemini" in gateway._models:
            try:
                gemini_result = await gateway.invoke(
                    "gemini",
                    "chat",
                    {
                        "messages": [{"role": "user", "content": hint_prompt}],
                        "system_prompt": system_prompt,
                        "max_tokens": 200,
                    },
                )
                if gemini_result.get("success") and gemini_result.get("data"):
                    raw = gemini_result["data"]
                    native_hint = raw if isinstance(raw, str) else raw.get("response", "")
                    models_used.append("gemini_native")
            except Exception as gemini_err:
                logger.warning(f"[vietnamese_node] Gemini fallback failed: {gemini_err}")

        # --- Attempt 3: Hardcoded strings ---
        if not native_hint:
            native_hint = _get_predefined_vietnamese(errors)
            models_used.append("native_fallback")

        latency_ms = int((time.time() - start_time) * 1000)
        logger.info(f"[vietnamese_node] Hint via {models_used} in {latency_ms}ms")
        return {
            "vietnamese_hint": native_hint,
            "models_used": models_used,
        }

    except Exception as e:
        logger.error(f"[vietnamese_node] Error: {e}")
        return {
            "vietnamese_hint": _get_predefined_vietnamese(errors),
            "models_used": ["native_fallback"],
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

async def tts_node(state: TraceCAGState) -> Dict[str, Any]:
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
            logger.info(f"[tts_node] Audio generated in {latency_ms}ms")

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

async def ask_clarify_node(state: TraceCAGState) -> Dict[str, Any]:
    """
    Generate clarification question when confidence is low.
    
    Uses AI for more natural clarification questions.
    """
    logger.info("[ask_clarify_node] Generating clarification question...")

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
            "models_used": ["rule_fallback"],
        }
