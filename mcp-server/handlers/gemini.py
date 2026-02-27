"""
Gemini Handler - Google's Gemini API

Lightweight handler that calls Gemini API directly.
This is the primary AI backend for the MCP server since it only
requires an API key (no local GPU/model loading).
"""

import json
import logging
import os
from typing import Any, Dict

logger = logging.getLogger(__name__)


class GeminiHandler:
    """Handler for Google Gemini API"""

    def __init__(self):
        self.model = None
        self.api_key = os.getenv("GEMINI_API_KEY", "")
        self._initialized = False

    def _ensure_initialized(self):
        """Lazy-init the Gemini client"""
        if self._initialized:
            return

        if not self.api_key:
            raise ValueError(
                "GEMINI_API_KEY not set. "
                "Export it before starting the MCP server."
            )

        try:
            import google.generativeai as genai

            genai.configure(api_key=self.api_key)
            self.model = genai.GenerativeModel("gemini-2.0-flash")
            self._initialized = True
            logger.info("Gemini handler initialized")
        except ImportError:
            raise ImportError(
                "google-generativeai not installed. "
                "Run: pip install google-generativeai"
            )

    # ------------------------------------------------------------------
    # Chat
    # ------------------------------------------------------------------
    async def chat(self, message: str, context: Dict[str, Any]) -> Dict[str, str]:
        """Generate chat response using Gemini"""
        self._ensure_initialized()

        prompt = self._build_prompt(message, context)

        try:
            response = self.model.generate_content(prompt)
            return {
                "text": response.text,
                "confidence": 0.95,
                "suggestions": [],
            }
        except Exception as e:
            logger.error(f"Gemini chat error: {e}")
            raise

    # ------------------------------------------------------------------
    # Grammar analysis
    # ------------------------------------------------------------------
    async def analyze_grammar(
        self, sentence: str, user_level: str = "B1"
    ) -> Dict[str, Any]:
        """Use Gemini for deep grammar analysis"""
        self._ensure_initialized()

        prompt = f"""You are an English grammar expert. Analyze this sentence for grammar errors.
Sentence: "{sentence}"
Student level: {user_level}

Return a JSON object with:
{{
    "errors": [
        {{"error": "...", "correction": "...", "explanation": "...", "type": "grammar|spelling|punctuation"}}
    ],
    "corrected_sentence": "...",
    "is_correct": true/false,
    "suggestions": ["..."]
}}

Only return valid JSON, no markdown."""

        try:
            response = self.model.generate_content(prompt)
            try:
                return json.loads(response.text)
            except json.JSONDecodeError:
                return {"llm_response": response.text, "method": "gemini"}
        except Exception as e:
            logger.error(f"Gemini grammar analysis error: {e}")
            raise

    # ------------------------------------------------------------------
    # Exercise generation
    # ------------------------------------------------------------------
    async def generate_exercise(
        self,
        concept: str,
        difficulty: str,
        exercise_type: str,
        count: int = 1,
    ) -> Dict[str, Any]:
        """Use Gemini to generate learning exercises"""
        self._ensure_initialized()

        prompt = f"""Generate {count} English learning exercise(s).
Concept: {concept}
Difficulty: {difficulty}
Type: {exercise_type}

Return JSON:
{{
    "exercises": [
        {{
            "question": "...",
            "options": ["A", "B", "C", "D"],
            "correct_answer": "...",
            "explanation": "...",
            "hint": "..."
        }}
    ],
    "concept": "{concept}",
    "difficulty": "{difficulty}"
}}

Make exercises appropriate for the difficulty level. Only return valid JSON."""

        try:
            response = self.model.generate_content(prompt)
            try:
                return json.loads(response.text)
            except json.JSONDecodeError:
                return {"raw_response": response.text, "method": "gemini"}
        except Exception as e:
            logger.error(f"Gemini exercise generation error: {e}")
            raise

    # ------------------------------------------------------------------
    # Pronunciation analysis (text-based comparison)
    # ------------------------------------------------------------------
    async def analyze_pronunciation(
        self, reference_text: str, transcription: str
    ) -> Dict[str, Any]:
        """Compare expected vs actual pronunciation via text analysis"""
        self._ensure_initialized()

        prompt = f"""Compare the expected text with what was actually spoken/transcribed.
Expected: "{reference_text}"
Transcribed: "{transcription}"

Analyze pronunciation issues. Return JSON:
{{
    "accuracy_score": 0.0-1.0,
    "word_scores": [
        {{"word": "...", "expected": "...", "actual": "...", "score": 0.0-1.0, "issue": "..."}}
    ],
    "overall_feedback": "...",
    "suggestions": ["..."]
}}

Only return valid JSON."""

        try:
            response = self.model.generate_content(prompt)
            try:
                return json.loads(response.text)
            except json.JSONDecodeError:
                return {"raw_response": response.text, "method": "gemini"}
        except Exception as e:
            logger.error(f"Gemini pronunciation analysis error: {e}")
            raise

    # ------------------------------------------------------------------
    # Knowledge-graph concept expansion
    # ------------------------------------------------------------------
    async def expand_concepts(
        self,
        concept: str,
        relation_type: str = "all",
        depth: int = 2,
    ) -> Dict[str, Any]:
        """Use Gemini to explore concept relationships"""
        self._ensure_initialized()

        rel_filter = (
            f"Focus on {relation_type} relationships."
            if relation_type != "all"
            else ""
        )

        prompt = f"""You are an English language teaching expert.
Map the concept relationships for: "{concept}"
{rel_filter}
Depth level: {depth} (how many levels of related concepts to include)

Return JSON:
{{
    "concept": "{concept}",
    "type": "grammar|vocabulary|phonetics",
    "prerequisites": ["concepts needed before learning this"],
    "related_concepts": ["directly related concepts"],
    "advanced_from": ["what this concept leads to"],
    "examples": ["example sentences"],
    "common_errors": ["typical mistakes learners make"]
}}

Only return valid JSON."""

        try:
            response = self.model.generate_content(prompt)
            try:
                return json.loads(response.text)
            except json.JSONDecodeError:
                return {"raw_response": response.text, "method": "gemini"}
        except Exception as e:
            logger.error(f"Gemini concept expansion error: {e}")
            raise

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _build_prompt(self, message: str, context: Dict) -> str:
        """Build chat prompt with context"""
        user_level = context.get("user_level", "B1")

        return f"""You are an English tutor for a student at {user_level} level.

Student's question: {message}

Provide:
1. Clear explanation appropriate for their level
2. Examples
3. Practice suggestions

Keep your response concise and encouraging."""
