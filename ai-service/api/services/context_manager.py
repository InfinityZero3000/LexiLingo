"""
Context Manager Service

Following architecture.md Section 2.1:
- Context Encoder (sentence embeddings)
- Conversation History Buffer (last 5 turns)
- Learner Profile Cache (Redis)
- Semantic Memory (Knowledge Graph)
"""

from typing import List, Dict, Any
import hashlib
from datetime import datetime, timezone

from api.core.redis_client import LearnerProfileCache, ConversationCache


class ContextManager:
    """
    Central context management for AI interactions
    
    Manages:
    - Conversation history (sliding window of 5 turns)
    - Learner profiles (level, errors, sessions)
    - Context embeddings for retrieval
    """
    
    def __init__(
        self,
        learner_cache: LearnerProfileCache,
        conversation_cache: ConversationCache
    ):
        self.learner_cache = learner_cache
        self.conversation_cache = conversation_cache
    
    async def get_conversation_context(
        self,
        session_id: str,
        user_id: str,
        current_message: str
    ) -> Dict[str, Any]:
        """
        Build comprehensive context for AI processing
        
        Returns:
        {
            "session_id": "...",
            "user_id": "...",
            "current_message": "...",
            "history": [...],  # Last 5 turns
            "learner_profile": {...},  # Level, errors, sessions
            "context_summary": "..."  # Aggregated context
        }
        """
        # Get conversation history
        history = await self.conversation_cache.get_history(session_id)
        
        # Get learner profile
        learner_profile = await self.learner_cache.get_profile(user_id)
        
        # Build context summary
        context_summary = self._build_context_summary(
            history=history,
            learner_profile=learner_profile,
            current_message=current_message
        )
        
        return {
            "session_id": session_id,
            "user_id": user_id,
            "current_message": current_message,
            "history": history,
            "learner_profile": learner_profile,
            "context_summary": context_summary,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    
    def _build_context_summary(
        self,
        history: List[Dict[str, Any]],
        learner_profile: Dict[str, Any],
        current_message: str
    ) -> str:
        """
        Build text summary of context for prompt injection
        """
        summary_parts = []
        
        # Learner level
        level = learner_profile.get("level", "B1")
        summary_parts.append(f"Learner Level: {level}")
        
        # Common errors
        errors = learner_profile.get("common_errors", [])
        if errors:
            error_str = ", ".join(errors[:5])  # Top 5
            summary_parts.append(f"Common Errors: {error_str}")
        
        # Recent conversation topics
        if history:
            topics = self._extract_topics(history)
            if topics:
                summary_parts.append(f"Recent Topics: {', '.join(topics)}")
        
        # History context (last 2 turns)
        if len(history) >= 2:
            recent = history[-2:]
            history_str = " | ".join([
                f"U: {turn['user'][:50]}... A: {turn['ai'][:50]}..."
                for turn in recent
            ])
            summary_parts.append(f"Recent Context: {history_str}")
        
        return "\n".join(summary_parts)
    
    def _extract_topics(self, history: List[Dict[str, Any]]) -> List[str]:
        """
        Extract main topics from conversation history
        Simple keyword-based extraction
        """
        topic_keywords = {
            "travel": ["travel", "trip", "flight", "hotel", "vacation", "journey", "country", "visit"],
            "food": ["food", "eat", "restaurant", "recipe", "cook", "meal", "dinner", "breakfast", "lunch", "drink"],
            "work & career": ["job", "work", "office", "career", "interview", "business", "company", "boss", "colleague"],
            "hobbies": ["hobby", "music", "movie", "book", "read", "game", "play", "hike", "paint", "art"],
            "family & friends": ["family", "friend", "parent", "mother", "father", "sister", "brother", "child", "son", "daughter"],
            "education": ["school", "university", "college", "study", "learn", "class", "teacher", "student", "exam"],
            "technology": ["computer", "phone", "internet", "software", "ai", "tech", "app", "website", "online"],
            "sports": ["sport", "football", "soccer", "basketball", "tennis", "gym", "exercise", "run", "swim"],
            "health": ["health", "doctor", "hospital", "medicine", "sick", "pain", "fit", "diet"]
        }
        
        extracted = set()
        for turn in history:
            user_msg = turn.get("user", "").lower()
            ai_msg = turn.get("ai", "").lower()
            combined = f"{user_msg} {ai_msg}"
            
            for topic, keywords in topic_keywords.items():
                for kw in keywords:
                    if f" {kw}" in f" {combined}":
                        extracted.add(topic)
                        break
        return list(extracted)[:3]
    
    async def update_after_interaction(
        self,
        session_id: str,
        user_id: str,
        user_message: str,
        ai_response: str,
        analysis: Dict[str, Any]
    ):
        """
        Update context after AI interaction
        
        Updates:
        - Conversation history
        - Learner error patterns
        - Session summaries
        """
        # Add turn to conversation history
        await self.conversation_cache.add_turn(
            session_id=session_id,
            user_message=user_message,
            ai_response=ai_response,
            metadata={
                "fluency_score": analysis.get("fluency_score"),
                "error_count": len(analysis.get("grammar_errors", []))
            }
        )
        
        # Update learner error patterns
        grammar_errors = analysis.get("grammar_errors", [])
        for error in grammar_errors:
            error_type = error.get("type", "unknown")
            await self.learner_cache.add_error(user_id, error_type)
        
        # Update learner level if needed
        try:
            sessions = await self.learner_cache.get_sessions(user_id)
            if len(sessions) > 0 and len(sessions) % 5 == 0:
                from api.services.assessment_service import get_assessment_service
                assess_service = get_assessment_service()
                assessment = await assess_service.assess_user(user_id, force=True)
                if assessment and assessment.current_level:
                    await self.learner_cache.set_level(user_id, assessment.current_level.value)
        except Exception:
            pass
        
    def generate_cache_key(self, text: str, context: Dict[str, Any]) -> str:
        """
        Generate cache key for response caching
        
        Hash based on:
        - User input text
        - Learner level
        - Recent errors (for context-aware caching)
        """
        key_parts = [
            text,
            context.get("learner_profile", {}).get("level", "B1"),
            str(sorted(context.get("learner_profile", {}).get("common_errors", [])[:3]))
        ]
        
        key_string = "|".join(key_parts)
        return hashlib.md5(key_string.encode()).hexdigest()


class PromptBuilder:
    """
    Build prompts for AI models based on context
    
    Following architecture.md principles:
    - Adaptive prompts based on learner level
    - Context-aware instructions
    - Socratic questioning for engagement
    """
    
    def build_tutor_prompt(
        self,
        user_message: str,
        context: Dict[str, Any],
        task_type: str = "general"
    ) -> str:
        """
        Build prompt for AI tutor
        
        Args:
            user_message: User's input text
            context: Context from ContextManager
            task_type: Type of task (grammar, fluency, vocab, dialogue)
        """
        learner_profile = context.get("learner_profile", {})
        level = learner_profile.get("level", "B1")
        context_summary = context.get("context_summary", "")
        
        base_prompt = f"""You are an expert English tutor helping a learner at level {level}.

Context:
{context_summary}

Task: {task_type}
User Input: "{user_message}"

Analyze the user's English and provide:
1. Fluency assessment (score 0-1)
2. Grammar corrections (if any errors)
3. Vocabulary level assessment
4. Tutor response (encouraging, clear explanation)

Important:
- Use Socratic questioning to guide learning
- Adapt your language to {level} level
- Be encouraging and supportive
- Focus on the most important errors first

Respond in JSON format with this structure:
{{
    "fluency_score": 0.85,
    "vocabulary_level": "B1",
    "grammar_errors": [
        {{
            "type": "verb_tense",
            "error": "I goes",
            "correction": "I go",
            "explanation": "Use 'go' with 'I' (subject-verb agreement)"
        }}
    ],
    "tutor_response": "Good attempt! Let's work on..."
}}"""
        
        return base_prompt
    
    def build_vietnamese_explanation_prompt(
        self,
        english_analysis: Dict[str, Any],
        user_message: str
    ) -> str:
        """
        Build prompt for Vietnamese explanation (LLaMA3-VI)
        
        Used when:
        - Learner level is A2
        - Confidence < 0.8
        - Explicit Vietnamese request
        """
        errors = english_analysis.get("grammar_errors", [])
        error_str = "\n".join([
            f"- {e['error']} → {e['correction']}: {e['explanation']}"
            for e in errors
        ])
        
        prompt = f"""Bạn là gia sư tiếng Anh, đang giải thích cho học viên người Việt.

Câu của học viên: "{user_message}"

Phân tích (bằng tiếng Anh):
{error_str}

Hãy giải thích lỗi sai này bằng tiếng Việt một cách:
- Dễ hiểu, đơn giản
- Khuyến khích học viên
- Đưa ra ví dụ cụ thể

Trả lời bằng tiếng Việt."""
        
        return prompt
