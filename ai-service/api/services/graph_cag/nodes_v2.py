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
from typing import Dict, Any, List, Optional

from api.services.graph_cag.state import GraphCAGState, DiagnosisError

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
        user_text = state.get("user_input", "").lower()
        all_concepts = kg.get_concepts()
        
        seed_concepts = []
        for concept_id, meta in all_concepts.items():
            keywords = meta.get("keywords", "").lower()
            for kw in keywords.split():
                if kw in user_text or user_text in kw:
                    seed_concepts.append(concept_id)
                    break
        
        # Grammar error patterns
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
# NODE 4: RETRIEVAL
# ============================================================

async def retrieve_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Combine vector search + KG context for response generation.
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
    for node in kg_expanded[:3]:
        context_parts.append(f"Related: {node.get('id', '')} ({node.get('relation', '')})")
    
    # Add error context
    for error in state.get("diagnosis_errors", [])[:2]:
        context_parts.append(f"Error: '{error.get('span', '')}' → '{error.get('correction', '')}'")
    
    vector_hits = []
    retrieved_context = "\n".join(context_parts) if context_parts else ""
    
    latency_ms = int((time.time() - start_time) * 1000)
    
    return {
        "vector_hits": vector_hits,
        "retrieved_context": retrieved_context,
        "models_used": ["retrieval"],
    }


# ============================================================
# NODE 5: GENERATE RESPONSE (AI-POWERED via ModelGateway)
# ============================================================

async def generate_node(state: GraphCAGState) -> Dict[str, Any]:
    """
    Generate personalized tutor response using AI.
    
    Uses ModelGateway to:
    - Reuse Qwen (already loaded from diagnose_node)
    - Generate contextual, encouraging responses
    - Adapt to learner level
    """
    logger.info("[generate_node] Generating AI response...")
    start_time = time.time()
    
    errors = state.get("diagnosis_errors", [])
    intent = state.get("diagnosis_intent", "correct")
    level = state.get("learner_profile", {}).get("level", "B1")
    confidence = state.get("diagnosis_confidence", 0.9)
    user_input = state.get("user_input", "")
    context = state.get("retrieved_context", "")
    
    # Determine strategy
    error_count = len(errors)
    if error_count == 0:
        strategy = "praise"
    elif error_count <= 2:
        strategy = "feedback"
    else:
        strategy = "scaffold"
    
    try:
        gateway = await get_gateway()
        
        # Build generation prompt
        errors_text = ""
        if errors:
            errors_text = "\n".join([
                f"- '{e.get('span', '')}' should be '{e.get('correction', '')}' ({e.get('explanation', '')})"
                for e in errors[:3]
            ])
        # Build grammar issues text (avoiding backslash in f-string)
        grammar_section = f"Grammar issues found:\n{errors_text}" if errors_text else "No grammar issues found!"
        correction_instruction = "Gently corrects the errors with clear explanations" if errors else "Praises their good work"
        
        generation_prompt = f"""You are a friendly English tutor helping a {level} level learner.

Student said: "{user_input}"

{grammar_section}

Context: {context if context else "General conversation practice"}

Task: Generate a helpful, encouraging response that:
1. Acknowledges their effort
2. {correction_instruction}
3. Provides a corrected version if needed
4. Suggests what to practice next
5. Uses simple language appropriate for {level} level

Be warm, supportive, and concise (2-3 sentences for correction, more for explanation if asked)."""

        # Call Qwen via ModelGateway (reuses loaded model!)
        result = await gateway.execute_task(
            "chat",
            {
                "message": generation_prompt,
                "system": f"You are an encouraging English tutor for {level} level students. Be warm and supportive.",
                "max_tokens": 300,
            }
        )
        
        if result.get("success") and result.get("data"):
            response = result["data"]
            if isinstance(response, dict):
                response = response.get("text", response.get("response", str(response)))
        else:
            # Fallback to template
            response = _generate_template_response(errors, strategy, user_input)
        
        # Determine next action
        if error_count == 0:
            next_action = "continue"
        elif error_count <= 2:
            next_action = "hint"
        else:
            next_action = "correct"
        
        # Calculate overall score
        grammar_score = state.get("grammar_score", 0.8)
        fluency_score = state.get("fluency_score", 0.8)
        overall_score = (grammar_score * 0.6 + fluency_score * 0.4)
        
        latency_ms = int((time.time() - start_time) * 1000)
        
        return {
            "tutor_response": response,
            "strategy": strategy,
            "next_action": next_action,
            "overall_score": overall_score,
            "models_used": ["qwen_tutor"],
        }
        
    except Exception as e:
        logger.error(f"[generate_node] Error: {e}")
        response = _generate_template_response(errors, strategy, user_input)
        return {
            "tutor_response": response,
            "strategy": strategy,
            "next_action": "hint",
            "overall_score": 0.7,
            "models_used": ["template_fallback"],
        }


def _generate_template_response(errors: list, strategy: str, user_input: str) -> str:
    """Fallback template response when AI is unavailable"""
    if strategy == "praise":
        return "Great job! Your sentence is grammatically correct. Keep up the excellent work! 🎉"
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
        
        # Try LLaMA-VI first, fallback to Qwen
        try:
            result = await gateway.execute_task(
                "explain_vi",  # Routes to LLaMA-VI
                {
                    "message": vi_prompt,
                    "max_tokens": 200,
                }
            )
        except Exception:
            # Fallback to Qwen for Vietnamese
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
            "models_used": ["llama_vi"],
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
