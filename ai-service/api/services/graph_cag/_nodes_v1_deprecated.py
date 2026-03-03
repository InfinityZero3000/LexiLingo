"""
GraphCAG Node Functions

Each node is a Python function that:
1. Receives current state
2. Performs an action (LLM call, KG query, etc.)
3. Returns state updates

Nodes are connected via edges in graph.py
"""

import logging
import time
import asyncio
import re
from typing import Dict, Any, List, Optional

from api.services.graph_cag.state import GraphCAGState, DiagnosisError

logger = logging.getLogger(__name__)


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
    logger.info(f"[input_node] Processing: {state['user_input'][:50]}...")
    start_time = time.time()
    
    try:
        # Load learner profile from Redis
        from api.core.redis_client import LearnerProfileCache, ConversationCache, RedisClient
        
        learner_profile = state.get("learner_profile", {"level": "B1"})
        conversation_history = []
        
        try:
            redis_client = await RedisClient.get_instance()
            
            # Get learner profile
            if state.get("user_id"):
                profile_cache = LearnerProfileCache(redis_client)
                cached_profile = await profile_cache.get_profile(state["user_id"])
                if cached_profile:
                    learner_profile = {**cached_profile, **learner_profile}
            
            # Get conversation history
            conv_cache = ConversationCache(redis_client)
            conversation_history = await conv_cache.get_history(state["session_id"])
            
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
# NODE 2: KNOWLEDGE GRAPH EXPANSION
# ============================================================

async def kg_expand_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Query Knowledge Graph for relevant concepts.
    
    Responsibilities:
    - Extract keywords from user input
    - Match to KG concepts
    - Expand via graph hops
    - Return linked concepts for context
    """
    logger.info("[kg_expand_node] Expanding knowledge graph...")
    start_time = time.time()
    
    try:
        from api.services.kg_service_v3 import KnowledgeGraphServiceV3
        
        kg = KnowledgeGraphServiceV3()
        
        # Simple keyword matching to find seed concepts
        user_text = state["user_input"].lower()
        all_concepts = kg.get_concepts()
        
        seed_concepts = []
        for concept_id, meta in all_concepts.items():
            keywords = meta.get("keywords", "").lower()
            # Check if any keyword matches
            for kw in keywords.split():
                if kw in user_text or user_text in kw:
                    seed_concepts.append(concept_id)
                    break
        
        # Also check for grammar error patterns
        grammar_patterns = {
            r"\bi goes\b": "concept:grammar.subject_verb_agreement",
            r"\bhe go\b": "concept:grammar.third_person_s",
            r"\byesterday\b.*\b(go|want|need)\b": "concept:grammar.past_time_markers",
        }
        
        for pattern, concept in grammar_patterns.items():
            if re.search(pattern, user_text, re.IGNORECASE):
                if concept not in seed_concepts:
                    seed_concepts.append(concept)
        
        # Expand via graph hops
        expanded_nodes = []
        paths = []
        
        if seed_concepts:
            kg_result = await kg.expand(seed_concepts, hops=1)
            expanded_nodes = [
                {"id": n.id, "relation": n.relation, "title": "", "keywords": ""}
                for n in kg_result.expanded_nodes
            ]
            paths = [
                {"from_id": p.from_id, "to_id": p.to_id, "hops": p.hops}
                for p in kg_result.paths
            ]
        
        latency_ms = int((time.time() - start_time) * 1000)
        logger.info(f"[kg_expand_node] Found {len(seed_concepts)} seed, {len(expanded_nodes)} expanded")
        
        return {
            "kg_seed_concepts": seed_concepts,
            "kg_expanded_nodes": expanded_nodes,
            "kg_paths": paths,
            "models_used": ["kuzu_kg"],
        }
        
    except Exception as e:
        logger.error(f"[kg_expand_node] Error: {e}")
        return {
            "kg_seed_concepts": [],
            "kg_expanded_nodes": [],
            "kg_paths": [],
        }


# ============================================================
# NODE 3: DIAGNOSIS
# ============================================================

async def diagnose_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Analyze user input for grammar, fluency, intent.
    
    Responsibilities:
    - Detect grammar errors
    - Classify intent (correct, explain, practice)
    - Calculate confidence score
    - Map errors to KG concepts (root causes)
    """
    logger.info("[diagnose_node] Diagnosing input...")
    start_time = time.time()
    
    user_text = state["user_input"]
    errors: List[DiagnosisError] = []
    root_causes: List[str] = []
    intent = "correct"  # Default: user wants correction
    confidence = 0.9
    
    # Rule-based grammar checking (will be replaced by Qwen)
    grammar_rules = [
        {
            "pattern": r"\bI goes\b",
            "type": "subject_verb_agreement",
            "correction": "I go",
            "explanation": "With 'I', use base form of verb, not third person -s",
            "concept": "concept:grammar.subject_verb_agreement",
        },
        {
            "pattern": r"\bhe go\b",
            "type": "third_person_s",
            "correction": "he goes",
            "explanation": "With 'he/she/it', add -s to verb",
            "concept": "concept:grammar.third_person_s",
        },
        {
            "pattern": r"\byesterday I go\b",
            "type": "past_tense",
            "correction": "yesterday I went",
            "explanation": "Use past tense with 'yesterday'",
            "concept": "concept:grammar.past_time_markers",
        },
        {
            "pattern": r"\bshe go\b",
            "type": "third_person_s",
            "correction": "she goes",
            "explanation": "With 'he/she/it', add -s to verb",
            "concept": "concept:grammar.third_person_s",
        },
    ]
    
    for rule in grammar_rules:
        match = re.search(rule["pattern"], user_text, re.IGNORECASE)
        if match:
            errors.append(DiagnosisError(
                span=match.group(),
                type=rule["type"],
                correction=rule["correction"],
                explanation=rule["explanation"],
            ))
            if rule["concept"] not in root_causes:
                root_causes.append(rule["concept"])
            confidence = 0.7  # Lower confidence when errors found
    
    # Detect intent from phrasing
    if re.search(r"\bhow (do|can|should)\b", user_text, re.IGNORECASE):
        intent = "explain"
    elif re.search(r"\bpractice\b|\bexercise\b", user_text, re.IGNORECASE):
        intent = "practice"
    elif re.search(r"\bcorrect\b|\bfix\b|\bwrong\b", user_text, re.IGNORECASE):
        intent = "correct"
    
    # Calculate scores
    error_count = len(errors)
    grammar_score = max(0.0, 1.0 - error_count * 0.2)
    fluency_score = 0.8 if error_count == 0 else 0.6
    
    latency_ms = int((time.time() - start_time) * 1000)
    logger.info(f"[diagnose_node] Found {error_count} errors, intent={intent}")
    
    return {
        "diagnosis_intent": intent,
        "diagnosis_errors": errors,
        "diagnosis_root_causes": root_causes,
        "diagnosis_confidence": confidence,
        "grammar_score": grammar_score,
        "fluency_score": fluency_score,
        "models_used": ["rule_based_checker"],
    }


# ============================================================
# NODE 4: RETRIEVAL
# ============================================================

async def retrieve_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Combine vector search + KG context for response generation.
    
    Responsibilities:
    - Vector similarity search
    - Combine with KG concepts
    - Build retrieval context string
    """
    logger.info("[retrieve_node] Retrieving context...")
    start_time = time.time()
    
    # Get relevant concepts from KG expansion
    kg_concepts = state.get("kg_seed_concepts", [])
    kg_expanded = state.get("kg_expanded_nodes", [])
    
    # Build context from KG
    context_parts = []
    
    # Add root cause concepts
    for concept_id in state.get("diagnosis_root_causes", []):
        context_parts.append(f"Grammar concept: {concept_id}")
    
    # Add expanded concepts
    for node in kg_expanded[:3]:  # Limit to top 3
        context_parts.append(f"Related: {node.get('id', '')} ({node.get('relation', '')})")
    
    # TODO: Add vector search when embedding service is ready
    vector_hits = []
    
    retrieved_context = "\n".join(context_parts) if context_parts else ""
    
    latency_ms = int((time.time() - start_time) * 1000)
    
    return {
        "vector_hits": vector_hits,
        "retrieved_context": retrieved_context,
        "models_used": ["retrieval"],
    }


# ============================================================
# NODE 5: GENERATE RESPONSE
# ============================================================

async def generate_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Generate tutor response using context + diagnosis.
    
    Responsibilities:
    - Select tutoring strategy
    - Generate response text
    - Include corrections if needed
    """
    logger.info("[generate_node] Generating response...")
    start_time = time.time()
    
    errors = state.get("diagnosis_errors", [])
    intent = state.get("diagnosis_intent", "correct")
    level = state.get("learner_profile", {}).get("level", "B1")
    confidence = state.get("diagnosis_confidence", 0.9)
    
    # Select strategy based on error count
    error_count = len(errors)
    if error_count == 0:
        strategy = "praise"
    elif error_count <= 2:
        strategy = "feedback"
    else:
        strategy = "scaffold"
    
    # Generate response based on strategy
    if strategy == "praise":
        response = "Great job! Your sentence is grammatically correct. Keep up the excellent work!"
        next_action = "continue"
    elif strategy == "feedback" and errors:
        error = errors[0]
        response = (
            f"Good effort! I noticed a small issue: '{error['span']}' should be "
            f"'{error['correction']}'. {error['explanation']}. "
            f"Try saying: \"{state['user_input'].replace(error['span'], error['correction'])}\""
        )
        next_action = "hint"
    else:
        # Scaffold with more detail
        corrections = []
        for err in errors[:2]:  # Limit to 2 corrections
            corrections.append(f"• '{err['span']}' → '{err['correction']}': {err['explanation']}")
        
        response = f"Let me help you with this. Here are some corrections:\n" + "\n".join(corrections)
        next_action = "correct"
    
    # Add Vietnamese hint for beginners or low confidence
    vietnamese_hint = None
    if level in ["A1", "A2"] or confidence < 0.6:
        if errors:
            vietnamese_hint = f"Gợi ý: Với '{errors[0]['type']}', hãy nhớ quy tắc ngữ pháp này."
    
    # Calculate overall score
    grammar_score = state.get("grammar_score", 0.8)
    fluency_score = state.get("fluency_score", 0.8)
    overall_score = (grammar_score * 0.6 + fluency_score * 0.4)
    
    latency_ms = int((time.time() - start_time) * 1000)
    
    return {
        "tutor_response": response,
        "vietnamese_hint": vietnamese_hint,
        "strategy": strategy,
        "next_action": next_action,
        "overall_score": overall_score,
        "models_used": ["response_generator"],
    }


# ============================================================
# NODE 6: VIETNAMESE EXPLANATION (Conditional)
# ============================================================

async def vietnamese_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Generate Vietnamese explanation for beginners.
    
    Only called when:
    - Level is A1/A2
    - Confidence is low
    - Complex grammar detected
    """
    logger.info("[vietnamese_node] Generating Vietnamese explanation...")
    start_time = time.time()
    
    errors = state.get("diagnosis_errors", [])
    
    # Generate Vietnamese explanation
    if errors:
        error_type = errors[0].get("type", "unknown")
        explanations = {
            "subject_verb_agreement": "Trong tiếng Anh, động từ phải hòa hợp với chủ ngữ. Với 'I/you/we/they' dùng động từ nguyên mẫu, với 'he/she/it' thêm -s.",
            "third_person_s": "Với chủ ngữ ngôi thứ 3 số ít (he, she, it), động từ cần thêm -s hoặc -es.",
            "past_tense": "Khi nói về quá khứ (yesterday, last week...), cần dùng thì quá khứ đơn.",
        }
        vietnamese_hint = explanations.get(error_type, "Hãy chú ý quy tắc ngữ pháp này nhé!")
    else:
        vietnamese_hint = "Câu của bạn rất tốt! Tiếp tục cố gắng nhé!"
    
    latency_ms = int((time.time() - start_time) * 1000)
    
    return {
        "vietnamese_hint": vietnamese_hint,
        "models_used": ["vietnamese_generator"],
    }


# ============================================================
# NODE 7: TEXT-TO-SPEECH
# ============================================================

async def tts_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Convert tutor response to speech.
    
    Uses Piper TTS for offline, fast synthesis.
    """
    logger.info("[tts_node] Generating speech...")
    start_time = time.time()
    
    # TTS is optional - skip if response is empty
    tutor_response = state.get("tutor_response", "")
    if not tutor_response:
        return {"tts_audio_bytes": None, "tts_audio_url": None}
    
    try:
        from api.services.tts_service import synthesize_speech
        
        # Generate audio
        audio_bytes = await synthesize_speech(tutor_response)
        
        latency_ms = int((time.time() - start_time) * 1000)
        
        return {
            "tts_audio_bytes": audio_bytes,
            "models_used": ["piper_tts"],
        }
        
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
    """
    logger.info("[ask_clarify_node] Generating clarification question...")
    
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
    }
