"""
DL Model Service

Service to interact with DL-Model-Support API
Following architecture.md:
- Qwen2.5-1.5B + Unified LoRA Adapter
- HuBERT for pronunciation
- LLaMA3-8B-VI for Vietnamese explanations (lazy load)
"""

import httpx
from typing import Dict, Any, Optional, List
from datetime import datetime
import asyncio

from api.core.config import settings


class DLModelService:
    """
    Service to call DL-Model-Support API
    
    Handles:
    - Grammar analysis (Qwen + Unified Adapter)
    - Pronunciation analysis (HuBERT)
    - Vietnamese explanations (LLaMA3-VI, lazy load)
    """
    
    def __init__(self):
        self.base_url = settings.DL_MODEL_API_URL
        self.api_key = settings.DL_MODEL_API_KEY
        self.timeout = settings.AI_MODEL_TIMEOUT
        self.client: Optional[httpx.AsyncClient] = None
    
    async def _get_client(self) -> httpx.AsyncClient:
        """Get or create async HTTP client."""
        if self.client is None:
            headers = {}
            if self.api_key:
                headers["Authorization"] = f"Bearer {self.api_key}"
            
            self.client = httpx.AsyncClient(
                base_url=self.base_url,
                headers=headers,
                timeout=self.timeout
            )
        return self.client
    
    async def close(self):
        """Close HTTP client."""
        if self.client:
            await self.client.aclose()
            self.client = None
    
    async def analyze_text(
        self,
        text: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Analyze text with Qwen (default base model unless configured)
        
        Primary analysis covering:
        - Fluency score (0-1)
        - Grammar errors with corrections
        - Vocabulary level (A1-C2)
        - Tutor response
        
        Args:
            text: User input text
            context: Context from ContextManager (learner level, history, etc.)
        
        Returns:
            {
                "fluency_score": 0.87,
                "vocabulary_level": "B1",
                "grammar_errors": [...],
                "tutor_response": "...",
                "processing_time_ms": 120
            }
        """
        try:
            client = await self._get_client()
            
            start_time = asyncio.get_event_loop().time()
            
            payload = {
                "text": text,
                "context": context or {},
                "tasks": ["fluency", "grammar", "vocabulary", "tutor"],
            }
            if settings.QWEN_MODEL_NAME:
                payload["model"] = settings.QWEN_MODEL_NAME

            response = await client.post(
                "/api/v1/analyze",
                json=payload
            )
            
            end_time = asyncio.get_event_loop().time()
            processing_time = int((end_time - start_time) * 1000)
            
            if response.status_code == 200:
                result = response.json()
                result["processing_time_ms"] = processing_time
                return result
            else:
                # Fallback to rule-based analysis
                return self._fallback_analysis(text, processing_time)
        
        except Exception as e:
            print(f"DL Model API error: {e}")
            # Graceful degradation
            return self._fallback_analysis(text, 0)
    
    async def analyze_pronunciation(
        self,
        audio_data: bytes,
        transcript: str
    ) -> Dict[str, Any]:
        """
        Analyze pronunciation with HuBERT
        
        Analyzes:
        - Phoneme accuracy
        - Pronunciation errors
        - Prosody score
        
        Args:
            audio_data: Audio file bytes (WAV format)
            transcript: Expected transcript for forced alignment
        
        Returns:
            {
                "phoneme_accuracy": 0.85,
                "errors": [{"phoneme": "/θ/", "actual": "/s/", "word": "think"}],
                "prosody_score": 0.78,
                "processing_time_ms": 150
            }
        """
        try:
            client = await self._get_client()
            
            start_time = asyncio.get_event_loop().time()
            
            # Upload audio file
            files = {"audio": ("audio.wav", audio_data, "audio/wav")}
            data = {"transcript": transcript}
            
            response = await client.post(
                "/api/v1/pronunciation",
                files=files,
                data=data
            )
            
            end_time = asyncio.get_event_loop().time()
            processing_time = int((end_time - start_time) * 1000)
            
            if response.status_code == 200:
                result = response.json()
                result["processing_time_ms"] = processing_time
                return result
            else:
                return {"error": "Pronunciation analysis failed", "processing_time_ms": processing_time}
        
        except Exception as e:
            print(f"Pronunciation API error: {e}")
            return {"error": str(e), "processing_time_ms": 0}
    
    async def explain_in_vietnamese(
        self,
        english_analysis: Dict[str, Any],
        user_text: str
    ) -> str:
        """
        Get Vietnamese explanation with LLaMA3-VI (lazy load)
        
        Triggered when:
        - Learner level is A2
        - Confidence < 0.8
        - Explicit Vietnamese request
        
        Args:
            english_analysis: Analysis from Qwen
            user_text: Original user text
        
        Returns:
            Vietnamese explanation string
        """
        try:
            client = await self._get_client()
            
            payload = {
                "text": user_text,
                "analysis": english_analysis,
            }
            response = await client.post(
                "/api/v1/explain-vi",
                json=payload,
                timeout=10.0  # Vietnamese explanation may take longer
            )
            
            if response.status_code == 200:
                result = response.json()
                return result.get("explanation", "")
            else:
                return ""
        
        except Exception as e:
            print(f"Vietnamese explanation error: {e}")
            return ""  # Graceful degradation - skip Vietnamese
    
    def _fallback_analysis(self, text: str, processing_time: int) -> Dict[str, Any]:
        """
        Rule-based fallback when DL Model API is unavailable
        
        Simple analysis using:
        - Word count for fluency
        - Basic grammar patterns
        - Generic tutor response
        """
        word_count = len(text.split())
        
        # Simple fluency heuristic
        fluency_score = min(1.0, word_count / 20)
        
        # Basic grammar checks (very simple)
        grammar_errors = []
        
        # Check for common errors (simplified)
        text_lower = text.lower()
        if " i goes " in text_lower or " he go " in text_lower:
            grammar_errors.append({
                "type": "subject_verb_agreement",
                "error": "verb form",
                "correction": "use correct verb form",
                "explanation": "Subject and verb must agree"
            })
        
        # Vocabulary level heuristic (word length)
        avg_word_length = sum(len(w) for w in text.split()) / max(word_count, 1)
        if avg_word_length < 4:
            vocab_level = "A2"
        elif avg_word_length < 6:
            vocab_level = "B1"
        else:
            vocab_level = "B2"
        
        return {
            "fluency_score": fluency_score,
            "vocabulary_level": vocab_level,
            "grammar_errors": grammar_errors,
            "tutor_response": "I'm analyzing your text. Please note that detailed AI analysis is currently unavailable, but I can still help you!",
            "processing_time_ms": processing_time,
            "fallback": True
        }
    
    async def health_check(self) -> bool:
        """Check if DL Model API is available."""
        try:
            client = await self._get_client()
            response = await client.get("/health", timeout=5.0)
            return response.status_code == 200
        except Exception:
            return False


# Singleton instance
_dl_model_service: Optional[DLModelService] = None


def get_dl_model_service() -> DLModelService:
    """Get DL Model Service singleton."""
    global _dl_model_service
    if _dl_model_service is None:
        _dl_model_service = DLModelService()
    return _dl_model_service
