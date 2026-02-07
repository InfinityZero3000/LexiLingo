"""
Topic LLM Gateway

Unified gateway for Topic-Based Conversation with fallback support.
Primary: Qwen (Ollama local) → Fallback: Gemini (Cloud)

This gateway provides:
- Automatic fallback when primary LLM fails
- Consistent interface for topic chat
- Latency tracking and logging
- Streaming support (future)
"""

from __future__ import annotations

import logging
import time
from typing import Optional, Dict, List, Literal
from dataclasses import dataclass
from enum import Enum

try:
    import google.generativeai as genai
except ImportError:
    genai = None  # type: ignore

from api.core.config import settings
from api.services.ollama_service import OllamaService

logger = logging.getLogger(__name__)


class LLMProvider(str, Enum):
    """Available LLM providers"""
    QWEN = "qwen"       # Local Ollama
    GEMINI = "gemini"   # Cloud


@dataclass
class LLMResponse:
    """Standardized response from LLM"""
    content: str
    provider: LLMProvider
    latency_ms: int
    model_name: str
    fallback_used: bool = False
    error: Optional[str] = None


class TopicLLMGateway:
    """
    LLM Gateway for Topic-Based Conversations.
    
    Features:
    - Primary: Qwen via Ollama (faster, local, privacy)
    - Fallback: Gemini (higher quality, cloud)
    - Automatic failover on errors
    - Latency tracking
    
    Usage:
        gateway = TopicLLMGateway()
        response = await gateway.generate(
            system_prompt="You are a helpful tutor...",
            user_message="Hello!",
            conversation_history=[...]
        )
    """
    
    def __init__(
        self,
        primary: LLMProvider = LLMProvider.QWEN,
        enable_fallback: bool = True,
        qwen_temperature: float = 0.7,
        gemini_temperature: float = 0.7,
    ):
        """
        Initialize the LLM Gateway.
        
        Args:
            primary: Primary LLM provider (default: Qwen)
            enable_fallback: Enable fallback to secondary provider
            qwen_temperature: Temperature for Qwen generation
            gemini_temperature: Temperature for Gemini generation
        """
        self.primary = primary
        self.enable_fallback = enable_fallback
        self.qwen_temperature = qwen_temperature
        self.gemini_temperature = gemini_temperature
        
        # Initialize Ollama service
        self.ollama = OllamaService(
            base_url=settings.OLLAMA_BASE_URL,
            model=settings.OLLAMA_MODEL,
            timeout=settings.OLLAMA_TIMEOUT,
        )
        
        # Initialize Gemini
        self.gemini_model = None
        if genai and settings.GEMINI_API_KEY:
            try:
                genai.configure(api_key=settings.GEMINI_API_KEY)  # type: ignore[attr-defined]
                self.gemini_model = genai.GenerativeModel('gemini-pro')  # type: ignore[attr-defined]
            except Exception as e:
                logger.warning(f"Failed to configure Gemini: {e}")
        
        logger.info(
            f"TopicLLMGateway initialized: "
            f"primary={primary.value}, "
            f"fallback={enable_fallback}, "
            f"ollama_model={settings.OLLAMA_MODEL}"
        )
    
    async def generate(
        self,
        system_prompt: str,
        user_message: str,
        conversation_history: Optional[List[Dict[str, str]]] = None,
        max_tokens: int = 512,
        force_provider: Optional[LLMProvider] = None,
    ) -> LLMResponse:
        """
        Generate a response for topic-based conversation.
        
        Args:
            system_prompt: The master system prompt with story context
            user_message: Current user message
            conversation_history: Previous messages [{"role": "user/assistant", "content": "..."}]
            max_tokens: Maximum tokens to generate
            force_provider: Force specific provider (skip fallback)
            
        Returns:
            LLMResponse with content, provider info, and metrics
        """
        history = conversation_history or []
        provider = force_provider or self.primary
        
        # Try primary provider
        try:
            if provider == LLMProvider.QWEN:
                return await self._generate_qwen(
                    system_prompt, user_message, history, max_tokens
                )
            else:
                return await self._generate_gemini(
                    system_prompt, user_message, history, max_tokens
                )
        except Exception as e:
            logger.warning(f"Primary LLM ({provider.value}) failed: {e}")
            
            # Fallback if enabled
            if self.enable_fallback and not force_provider:
                fallback_provider = (
                    LLMProvider.GEMINI if provider == LLMProvider.QWEN
                    else LLMProvider.QWEN
                )
                logger.info(f"Falling back to {fallback_provider.value}")
                
                try:
                    if fallback_provider == LLMProvider.QWEN:
                        response = await self._generate_qwen(
                            system_prompt, user_message, history, max_tokens
                        )
                    else:
                        response = await self._generate_gemini(
                            system_prompt, user_message, history, max_tokens
                        )
                    
                    response.fallback_used = True
                    return response
                    
                except Exception as fallback_error:
                    logger.error(f"Fallback also failed: {fallback_error}")
                    return LLMResponse(
                        content="I'm sorry, I'm having trouble responding right now. Please try again.",
                        provider=fallback_provider,
                        latency_ms=0,
                        model_name="error",
                        fallback_used=True,
                        error=str(fallback_error)
                    )
            
            # No fallback - return error
            return LLMResponse(
                content="I'm sorry, I'm having trouble responding right now. Please try again.",
                provider=provider,
                latency_ms=0,
                model_name="error",
                error=str(e)
            )
    
    async def _generate_qwen(
        self,
        system_prompt: str,
        user_message: str,
        history: List[Dict[str, str]],
        max_tokens: int,
    ) -> LLMResponse:
        """Generate response using Qwen via Ollama."""
        start_time = time.time()
        
        # Build messages for chat API
        messages = [{"role": "system", "content": system_prompt}]
        
        # Add conversation history
        for msg in history[-10:]:  # Last 10 messages
            messages.append({
                "role": msg.get("role", "user"),
                "content": msg.get("content", "")
            })
        
        # Add current user message
        messages.append({"role": "user", "content": user_message})
        
        # Check Ollama health
        is_healthy = await self.ollama.health_check()
        if not is_healthy:
            raise ConnectionError("Ollama service not available")
        
        # Generate response
        response = await self.ollama.chat(
            messages=messages,
            temperature=self.qwen_temperature,
            max_tokens=max_tokens,
        )
        
        latency_ms = int((time.time() - start_time) * 1000)
        
        return LLMResponse(
            content=response if isinstance(response, str) else str(response),
            provider=LLMProvider.QWEN,
            latency_ms=latency_ms,
            model_name=settings.OLLAMA_MODEL,
        )
    
    async def _generate_gemini(
        self,
        system_prompt: str,
        user_message: str,
        history: List[Dict[str, str]],
        max_tokens: int,
    ) -> LLMResponse:
        """Generate response using Gemini."""
        if not self.gemini_model:
            raise ValueError("Gemini API key not configured")
        
        start_time = time.time()
        
        # Build prompt for Gemini (it doesn't have system message in same way)
        conversation_text = ""
        for msg in history[-10:]:
            role_label = "User" if msg.get("role") == "user" else "Assistant"
            conversation_text += f"{role_label}: {msg.get('content', '')}\n"
        
        conversation_text += f"User: {user_message}\n"
        
        full_prompt = f"""[SYSTEM INSTRUCTIONS]
{system_prompt}

[CONVERSATION SO FAR]
{conversation_text}

[YOUR RESPONSE]
Respond as your character. Include [💡 Tip] or [📘] notes if the user made errors or asked about vocabulary."""
        
        # Generate
        gen_config: dict = {"max_output_tokens": max_tokens, "temperature": self.gemini_temperature}
        
        response = self.gemini_model.generate_content(
            full_prompt,
            generation_config=gen_config  # type: ignore[arg-type]
        )
        
        latency_ms = int((time.time() - start_time) * 1000)
        
        return LLMResponse(
            content=response.text,
            provider=LLMProvider.GEMINI,
            latency_ms=latency_ms,
            model_name="gemini-pro",
        )
    
    async def health_check(self) -> Dict[str, bool]:
        """Check health of all LLM providers."""
        results = {}
        
        # Check Ollama
        try:
            results["qwen"] = await self.ollama.health_check()
        except Exception:
            results["qwen"] = False
        
        # Check Gemini
        results["gemini"] = self.gemini_model is not None
        
        return results
    
    def get_primary_provider(self) -> str:
        """Get the current primary provider name."""
        return self.primary.value
    
    def set_primary_provider(self, provider: LLMProvider):
        """Change the primary provider."""
        self.primary = provider
        logger.info(f"Primary provider changed to: {provider.value}")


# Singleton instance for app-wide use
_gateway_instance: Optional[TopicLLMGateway] = None


def get_topic_llm_gateway() -> TopicLLMGateway:
    """Get or create the singleton TopicLLMGateway instance."""
    global _gateway_instance
    if _gateway_instance is None:
        _gateway_instance = TopicLLMGateway()
    return _gateway_instance
