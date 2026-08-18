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
from typing import Dict, Any, List, Optional

from api.core.config import settings
from api.services.trace_cag.state import TraceCAGState, DiagnosisError
from api.services.trace_cag.evaluation_agent import EvaluationAgent
from api.services.trace_cag.dependencies import (
    dependency_record,
    stable_version_token,
)
from api.services.jit_graph_service import get_jit_graph_service

# LLM client — httpx pooling and rate-limit throttling
from api.services.trace_cag.llm_client import _throttled_post_json

# PCC cache R/W helpers used by the generation path
from api.services.trace_cag.cache_utils import _detect_native_request

# Façade re-exports: graph.py imports cache_gate_node from this module, and the
# cache-gate tests reach these helpers through the nodes_v2 namespace.
from api.services.trace_cag.cache_utils import (  # noqa: F401
    cache_gate_node,
    _build_graph_bucket,
    _extract_lightweight_graph_concepts,
    _infer_intent_pre_diagnosis,
    _profile_epoch,
)

# retrieve_node / generate_node live in their own modules (Phase 4 split) —
# re-exported here so existing `from nodes_v2 import ...` call sites keep working.
from api.services.trace_cag.retrieve import retrieve_node  # noqa: F401
from api.services.trace_cag.generate import (  # noqa: F401
    build_generation_prompt,
    stream_llm_tokens,
    generate_node,
)

logger = logging.getLogger(__name__)


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
        # Learner-state versioning is independent from Redis. A Redis outage
        # must not silently permit reuse of a stale personalized response.
        from api.core.redis_client import LearnerProfileCache, ConversationCache, RedisClient
        import asyncio as _asyncio
        
        learner_profile = state.get("learner_profile", {"level": "B1"})
        conversation_history = []
        user_id = state.get("user_id")
        session_id = state.get("session_id", "")
        epoch_result = None

        async def _get_learner_epoch():
            if not user_id or settings.LEARNER_STATE_MODE == "off":
                return None
            from api.clients.learner_state_client import get_learner_state_client

            deadline = time.monotonic() + (settings.LEARNER_STATE_DEADLINE_MS / 1000.0)
            return await get_learner_state_client().batch_get(
                str(user_id), [], deadline=deadline
            )

        epoch_task = _asyncio.create_task(_get_learner_epoch())
        
        try:
            if RedisClient._benchmark_redis_disabled():
                raise RuntimeError("Redis disabled for benchmark")

            redis_client = await RedisClient.get_instance()

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
            if RedisClient._benchmark_redis_disabled():
                logger.debug(f"Redis unavailable: {e}")
            else:
                logger.warning(f"Redis unavailable: {e}")

        learner_state_update: Dict[str, Any] = {}
        try:
            epoch_result = await epoch_task
            if epoch_result is not None:
                learner_profile["_learner_state_available"] = not epoch_result.degraded
                if not epoch_result.degraded:
                    learner_profile["_learner_state_epoch"] = epoch_result.state_epoch
                    if epoch_result.goal:
                        learner_profile["goal"] = epoch_result.goal
                    if epoch_result.interest:
                        learner_profile["interest"] = epoch_result.interest
                learner_state_update = {
                    "learner_state_epoch": epoch_result.state_epoch,
                    "learner_state_degraded": epoch_result.degraded,
                    "learner_state_reason": epoch_result.reason,
                }
        except Exception as e:
            logger.warning("Learner-state epoch unavailable: %s", e)
            if user_id and settings.LEARNER_STATE_MODE != "off":
                learner_profile["_learner_state_available"] = False
                learner_state_update = {
                    "learner_state_degraded": True,
                    "learner_state_reason": "unexpected_error",
                }
    
        latency_ms = int((time.time() - start_time) * 1000)
        profile_version = str(learner_profile.get("_learner_state_epoch") or "")
        if not profile_version:
            profile_version = stable_version_token(learner_profile, prefix="profile")
        
        return {
            "learner_profile": learner_profile,
            "conversation_history": conversation_history,
            "native_explanation_requested": _detect_native_request(user_input),
            "models_used": ["redis_cache"],
            "latency_ms": latency_ms,
            "dependency_events": [dependency_record(
                f"learner:{user_id or 'anonymous'}:profile",
                "learner",
                profile_version,
                "learner-state" if epoch_result is not None else "request-profile",
            )],
            **learner_state_update,
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
            "dependency_events": [dependency_record(
                "kg:tracecag:main", "kg", kg.get_kg_content_version(), "kuzu"
            )],
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
        # execute_task can *raise* (e.g. "Model 'qwen' not registered") instead
        # of returning {"success": False} for a genuinely unregistered/unavailable
        # model — normalize that into the same shape so the Groq-fallback branch
        # below actually runs instead of being skipped straight to rules.
        try:
            result = await gateway.execute_task(
                "chat",
                {
                    "message": diagnosis_prompt,
                    "system": "You are an English grammar analyzer. Return only valid JSON.",
                    # 150 was too tight for the requested schema (errors array
                    # with span/type/correction/explanation per item plus
                    # scores) — a live run against real Groq truncated mid-
                    # object ("Expecting ',' delimiter") for a single-error
                    # sentence, silently degrading to the weaker rule-based
                    # fallback.
                    "max_tokens": 400,
                },
            )
        except Exception as gateway_exc:
            logger.warning(f"[diagnose_node] Local gateway unavailable, trying Groq: {gateway_exc}")
            result = {"success": False, "error": str(gateway_exc)}
        
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
            groq_key = await get_available_groq_key(estimated_tokens=400)
            groq_model = os.getenv("GROQ_MODEL_DIAGNOSE", os.getenv("GROQ_MODEL", "groq/compound-mini"))
            if groq_key:
                try:
                    _no_think = "/no_think\n" if "qwen" in groq_model.lower() else ""
                    messages = [
                        {"role": "system", "content": "You are an English grammar analyzer. Return only valid JSON."},
                        {"role": "user", "content": f"{_no_think}{diagnosis_prompt}"},
                    ]
                    resp = await _throttled_post_json(
                        provider="groq",
                        url="https://api.groq.com/openai/v1/chat/completions",
                        headers={"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"},
                        payload={"model": groq_model, "messages": messages, "max_tokens": 400, "temperature": 0.0},
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
                
                # Extract errors — small fallback models sometimes hallucinate a
                # generic span (e.g. "the sentence") instead of quoting the
                # actual offending text, so drop anything that isn't really
                # part of what the user typed.
                for err in ai_data.get("errors", []):
                    span = err.get("span", "")
                    if not span or span.lower() not in user_text.lower():
                        continue
                    errors.append(DiagnosisError(
                        span=span,
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
    learner_update = await _load_learner_concept_overlay(state, merged)
    merged.update(learner_update)
    # Merge the accumulator list explicitly (avoid overwrite by dict.update)
    merged["models_used"] = (
        list((kg_result or {}).get("models_used", []))
        + list((diag_result or {}).get("models_used", []))
        + list((jit_result or {}).get("models_used", []))
    )
    return merged


async def _load_learner_concept_overlay(
    state: TraceCAGState,
    merged: Dict[str, Any],
) -> Dict[str, Any]:
    """Batch-load only concepts selected by this request's bounded KG work."""
    if settings.LEARNER_STATE_MODE == "off" or not state.get("user_id"):
        return {}
    from api.clients.learner_state_client import get_learner_state_client

    concept_ids: list[str] = []
    concept_ids.extend(str(item) for item in merged.get("kg_seed_concepts", []) if item)
    concept_ids.extend(str(item) for item in merged.get("diagnosis_root_causes", []) if item)
    concept_ids.extend(
        str(item.get("id"))
        for item in merged.get("kg_expanded_nodes", [])
        if isinstance(item, dict) and item.get("id")
    )
    concept_ids = list(dict.fromkeys(concept_ids))[:60]
    started = time.monotonic()
    deadline = started + (settings.LEARNER_STATE_DEADLINE_MS / 1000.0)
    try:
        result = await get_learner_state_client().batch_get(
            str(state["user_id"]), concept_ids, deadline=deadline
        )
    except Exception as exc:
        logger.warning("Learner-state overlay unavailable: %s", exc)
        return {
            "learner_concept_states": {},
            "learner_state_epoch": state.get("learner_profile", {}).get(
                "_learner_state_epoch", 0
            ),
            "learner_state_degraded": True,
            "learner_state_reason": "unexpected_error",
            "learner_state_latency_ms": (time.monotonic() - started) * 1000.0,
        }
    return {
        "learner_concept_states": result.states,
        "learner_state_epoch": result.state_epoch,
        "learner_state_degraded": result.degraded,
        "learner_state_reason": result.reason,
        "learner_state_latency_ms": (time.monotonic() - started) * 1000.0,
    }


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
            native_hint = _get_predefined_native_hint(errors, native_language)
            models_used.append("native_fallback")

        latency_ms = int((time.time() - start_time) * 1000)
        logger.info(f"[vietnamese_node] Hint via {models_used} in {latency_ms}ms")
        return {
            "native_hint": native_hint,
            "models_used": models_used,
        }

    except Exception as e:
        logger.error(f"[vietnamese_node] Error: {e}")
        return {
            "native_hint": _get_predefined_native_hint(errors, native_language),
            "models_used": ["native_fallback"],
        }


# Last-resort hardcoded explanations, keyed by language name (matches the
# `native_language` values produced by api.utils.languages.iso_to_language_name).
# Only the most common onboarding languages get a translated dict — anything
# else falls back to a short English line rather than translating every string.
_PREDEFINED_NATIVE_EXPLANATIONS: Dict[str, Dict[str, str]] = {
    "Vietnamese": {
        "_no_errors": "Câu của bạn rất tốt! Tiếp tục cố gắng nhé! ",
        "_default": "Hãy chú ý quy tắc ngữ pháp này nhé!",
        "subject_verb_agreement": "Trong tiếng Anh, động từ phải hòa hợp với chủ ngữ. Với 'I/you/we/they' dùng động từ nguyên mẫu, với 'he/she/it' thêm -s hoặc -es.",
        "third_person_s": "Với chủ ngữ ngôi thứ 3 số ít (he, she, it), động từ cần thêm -s hoặc -es. Ví dụ: He goes, She works.",
        "past_tense": "Khi nói về quá khứ (yesterday, last week...), cần dùng thì quá khứ đơn. Động từ bất quy tắc cần học thuộc!",
        "present_perfect": "Thì hiện tại hoàn thành dùng: have/has + past participle. Ví dụ: have gone, has eaten.",
        "article": "Dùng 'a' trước phụ âm, 'an' trước nguyên âm (a, e, i, o, u). Ví dụ: a book, an apple.",
    },
    "Japanese": {
        "_no_errors": "あなたの文章はとても良いです!頑張り続けてください!",
        "_default": "この文法のルールに気をつけてください!",
        "subject_verb_agreement": "英語では動詞は主語と一致させる必要があります。'I/you/we/they'には原形、'he/she/it'には-sか-esを付けます。",
        "third_person_s": "三人称単数の主語(he, she, it)には、動詞に-sか-esを付けます。例:He goes, She works.",
        "past_tense": "過去のことを話すとき(yesterday, last weekなど)は過去形を使います。不規則動詞は覚える必要があります!",
        "present_perfect": "現在完了形は have/has + 過去分詞 を使います。例:have gone, has eaten.",
        "article": "子音の前には'a'、母音(a, e, i, o, u)の前には'an'を使います。例:a book, an apple.",
    },
    "Korean": {
        "_no_errors": "문장이 정말 좋아요! 계속 노력하세요!",
        "_default": "이 문법 규칙에 주의하세요!",
        "subject_verb_agreement": "영어에서는 동사가 주어와 일치해야 합니다. 'I/you/we/they'는 원형을, 'he/she/it'는 -s나 -es를 붙입니다.",
        "third_person_s": "3인칭 단수 주어(he, she, it)는 동사에 -s나 -es를 붙입니다. 예: He goes, She works.",
        "past_tense": "과거(yesterday, last week 등)를 말할 때는 과거 시제를 사용합니다. 불규칙 동사는 외워야 해요!",
        "present_perfect": "현재완료는 have/has + 과거분사를 사용합니다. 예: have gone, has eaten.",
        "article": "자음 앞에는 'a', 모음(a, e, i, o, u) 앞에는 'an'을 사용합니다. 예: a book, an apple.",
    },
    "Chinese": {
        "_no_errors": "你的句子很好!继续努力!",
        "_default": "请注意这个语法规则!",
        "subject_verb_agreement": "在英语中,动词必须与主语一致。'I/you/we/they'用原形动词,'he/she/it'要加-s或-es。",
        "third_person_s": "第三人称单数主语(he, she, it)的动词要加-s或-es。例如:He goes, She works.",
        "past_tense": "说过去的事情(yesterday, last week等)要用过去时。不规则动词需要记住!",
        "present_perfect": "现在完成时用:have/has + 过去分词。例如:have gone, has eaten.",
        "article": "辅音前用'a',元音(a, e, i, o, u)前用'an'。例如:a book, an apple.",
    },
}

_FALLBACK_NATIVE_NO_ERRORS = "Nice work, your sentence is correct! Keep practicing!"
_FALLBACK_NATIVE_DEFAULT = "Pay attention to this grammar rule!"


def _get_predefined_native_hint(errors: list, native_language: str) -> str:
    """Last-resort fallback explanation in the learner's native language."""
    explanations = _PREDEFINED_NATIVE_EXPLANATIONS.get(native_language)
    if not explanations:
        return _FALLBACK_NATIVE_NO_ERRORS if not errors else _FALLBACK_NATIVE_DEFAULT

    if not errors:
        return explanations["_no_errors"]

    error_type = errors[0].get("type", "").lower()
    return explanations.get(error_type, explanations["_default"])


_ASK_CLARIFY_HINTS: Dict[str, str] = {
    "Vietnamese": "Mình cần thêm thông tin: bạn muốn sửa câu, giải thích ngữ pháp, hay tạo bài tập?",
    "Japanese": "もう少し情報が必要です。文の訂正、文法の説明、練習問題の作成のどれがいいですか?",
    "Korean": "조금 더 알려주세요: 문장 교정, 문법 설명, 연습 문제 중 무엇을 원하시나요?",
    "Chinese": "我需要更多信息:你想要句子修正、语法讲解,还是练习题?",
}
_ASK_CLARIFY_HINT_DEFAULT = (
    "I need a bit more info: would you like a sentence correction, "
    "a grammar explanation, or a practice exercise?"
)


def _get_ask_clarify_hint(native_language: str) -> str:
    """Clarification hint in the learner's configured language (falls back to English)."""
    return _ASK_CLARIFY_HINTS.get(native_language, _ASK_CLARIFY_HINT_DEFAULT)


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
    learner_profile = state.get("learner_profile", {})
    level = learner_profile.get("level", "B1")
    native_language = learner_profile.get("native_language", "Vietnamese")

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
        
        native_hint = _get_ask_clarify_hint(native_language)

        return {
            "tutor_response": response,
            "native_hint": native_hint,
            "strategy": "ask",
            "next_action": "ask",
            "path": "fast",
            "models_used": ["qwen_clarify"],
        }
        
    except Exception as e:
        logger.error(f"[ask_clarify_node] Error: {e}")
        return {
            "tutor_response": "Could you please clarify what you'd like help with?",
            "native_hint": _get_ask_clarify_hint(native_language),
            "strategy": "ask",
            "next_action": "ask",
            "path": "fast",
            "models_used": ["rule_fallback"],
        }
