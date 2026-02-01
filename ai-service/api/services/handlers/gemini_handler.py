"""
Gemini Handler - Cloud AI Fallback

Manages Google Gemini API for cloud-based AI features.
Used as fallback when local models are unavailable.
"""

import logging
import asyncio
from typing import Optional, Dict, Any, List
from dataclasses import dataclass
import os

logger = logging.getLogger(__name__)


@dataclass
class GeminiConfig:
    """Configuration for Gemini API."""
    api_key: Optional[str] = None
    model: str = "gemini-1.5-flash"  # Fast and efficient
    temperature: float = 0.7
    max_output_tokens: int = 1024
    top_p: float = 0.95
    top_k: int = 40


class GeminiHandler:
    """
    Handler for Google Gemini API.
    
    This is a cloud-based fallback for when local models
    are unavailable or for tasks requiring more capability.
    """
    
    def __init__(self, config: Optional[GeminiConfig] = None):
        self.config = config or GeminiConfig()
        self._client = None
        self._loaded = False
        self._loading = False
        self._lock = asyncio.Lock()
        
    @property
    def is_loaded(self) -> bool:
        return self._loaded
    
    @property
    def memory_usage_mb(self) -> float:
        """Cloud API uses minimal local memory."""
        return 10.0 if self._loaded else 0.0
    
    async def load(self) -> bool:
        """Initialize Gemini client."""
        if self._loaded:
            return True
            
        async with self._lock:
            if self._loaded:
                return True
                
            if self._loading:
                while self._loading:
                    await asyncio.sleep(0.1)
                return self._loaded
            
            self._loading = True
            try:
                logger.info("[GeminiHandler] Initializing Gemini client...")
                
                # Get API key
                api_key = self.config.api_key or os.environ.get("GEMINI_API_KEY")
                
                if not api_key:
                    logger.error("[GeminiHandler] No API key found")
                    return False
                
                import google.generativeai as genai
                
                genai.configure(api_key=api_key)
                self._client = genai.GenerativeModel(self.config.model)
                
                self._loaded = True
                logger.info("[GeminiHandler] ✓ Gemini client initialized")
                return True
                
            except Exception as e:
                logger.error(f"[GeminiHandler] Failed to initialize: {e}")
                self._loaded = False
                return False
            finally:
                self._loading = False
    
    async def unload(self) -> None:
        """Cleanup resources."""
        self._client = None
        self._loaded = False
        logger.info("[GeminiHandler] Client unloaded")
    
    async def chat(
        self,
        messages: List[Dict[str, str]],
        system_prompt: Optional[str] = None,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
    ) -> str:
        """
        Generate chat response.
        
        Args:
            messages: List of {"role": "user/model", "content": "..."}
            system_prompt: System instructions
            temperature: Override config temperature
            max_tokens: Override max output tokens
            
        Returns:
            Generated response text
        """
        if not await self.load():
            raise RuntimeError("Failed to initialize Gemini")
        
        # Build prompt
        parts = []
        
        if system_prompt:
            parts.append(f"System: {system_prompt}\n\n")
        
        for msg in messages:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            if role == "user":
                parts.append(f"User: {content}\n")
            elif role in ("assistant", "model"):
                parts.append(f"Assistant: {content}\n")
        
        prompt = "".join(parts)
        
        # Generate
        generation_config = {
            "temperature": temperature or self.config.temperature,
            "max_output_tokens": max_tokens or self.config.max_output_tokens,
            "top_p": self.config.top_p,
            "top_k": self.config.top_k,
        }
        
        try:
            response = await asyncio.to_thread(
                self._client.generate_content,
                prompt,
                generation_config=generation_config,
            )
            return response.text.strip()
        except Exception as e:
            logger.error(f"[GeminiHandler] Generation failed: {e}")
            raise
    
    async def analyze_grammar(
        self,
        text: str,
        target_language: str = "English",
    ) -> Dict[str, Any]:
        """
        Analyze grammar and provide corrections.
        
        Returns similar structure to QwenHandler for compatibility.
        """
        system_prompt = f"""You are an expert {target_language} grammar tutor.
Analyze the following text and identify ALL grammar errors.
For each error, provide:
1. The error span (exact text)
2. The correction
3. Error type (grammar/spelling/punctuation/word_choice)
4. Brief explanation

Output ONLY valid JSON format (no markdown, no code blocks):
{{
    "errors": [
        {{"span": "error text", "correction": "fixed text", "type": "grammar", "explanation": "reason"}}
    ],
    "corrected_text": "full corrected sentence",
    "grammar_score": 0.85,
    "fluency_score": 0.80
}}

Be thorough but fair. Score 1.0 means perfect."""

        messages = [{"role": "user", "content": f"Analyze this text:\n\n{text}"}]
        
        response = await self.chat(
            messages,
            system_prompt=system_prompt,
            temperature=0.3,
        )
        
        # Parse JSON response
        try:
            import json
            # Clean response
            response = response.strip()
            if response.startswith("```"):
                if "```json" in response:
                    response = response.split("```json")[1]
                else:
                    response = response.split("```")[1]
                response = response.split("```")[0]
            
            result = json.loads(response.strip())
            return result
        except json.JSONDecodeError:
            return {
                "errors": [],
                "corrected_text": text,
                "grammar_score": 0.8,
                "fluency_score": 0.8,
                "raw_response": response,
            }
    
    async def generate_response(
        self,
        user_input: str,
        context: Optional[str] = None,
        learner_level: str = "B1",
        errors: Optional[List[Dict]] = None,
    ) -> str:
        """Generate tutor response for the learner."""
        system_prompt = f"""You are LexiLingo, a friendly English tutor.
Learner level: {learner_level}

Guidelines:
- Be encouraging and supportive
- If there are errors, gently correct them with explanations
- Adjust vocabulary complexity to the learner's level
- Keep responses concise but helpful
- Use simple language for lower levels, more complex for higher
- Ask follow-up questions to keep the conversation going"""

        context_str = f"\n\nContext: {context}" if context else ""
        errors_str = ""
        if errors:
            errors_str = "\n\nErrors found in user's text:\n" + "\n".join(
                f"- '{e.get('span')}' → '{e.get('correction')}' ({e.get('type')})"
                for e in errors
            )
        
        messages = [{
            "role": "user",
            "content": f"{user_input}{context_str}{errors_str}"
        }]
        
        return await self.chat(
            messages,
            system_prompt=system_prompt,
            temperature=0.7,
            max_tokens=400,
        )
    
    async def explain_vietnamese(
        self,
        english_text: str,
        errors: Optional[List[Dict]] = None,
        learner_level: str = "B1",
    ) -> str:
        """Provide Vietnamese explanation for English text."""
        system_prompt = """Bạn là một gia sư tiếng Anh thân thiện.
Giải thích bằng tiếng Việt đơn giản và dễ hiểu.
Nếu có lỗi, hãy giải thích tại sao sai và cách sửa.
Giữ giải thích ngắn gọn (2-3 câu)."""

        content = f"Explain in Vietnamese:\n\n{english_text}"
        if errors:
            content += "\n\nErrors to explain:\n" + "\n".join(
                f"- '{e.get('span')}' → '{e.get('correction')}'"
                for e in errors
            )
        
        messages = [{"role": "user", "content": content}]
        
        return await self.chat(
            messages,
            system_prompt=system_prompt,
            temperature=0.7,
            max_tokens=300,
        )
    
    async def invoke(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Unified invoke interface for ModelGateway.
        
        Args:
            params: {
                "task": "chat" | "grammar" | "response" | "vietnamese",
                "text": "...",
                "messages": [...],
                ...other params
            }
            
        Returns:
            Task-specific result
        """
        task = params.get("task", "chat")
        
        if task == "grammar":
            return await self.analyze_grammar(
                text=params.get("text", ""),
            )
            
        elif task == "response":
            return {
                "response": await self.generate_response(
                    user_input=params.get("text", ""),
                    context=params.get("context"),
                    learner_level=params.get("level", "B1"),
                    errors=params.get("errors"),
                )
            }
            
        elif task == "vietnamese":
            return {
                "explanation": await self.explain_vietnamese(
                    english_text=params.get("text", ""),
                    errors=params.get("errors"),
                    learner_level=params.get("level", "B1"),
                )
            }
            
        else:  # chat
            messages = params.get("messages", [])
            if not messages and params.get("text"):
                messages = [{"role": "user", "content": params["text"]}]
            
            return {
                "response": await self.chat(
                    messages=messages,
                    system_prompt=params.get("system_prompt"),
                    temperature=params.get("temperature"),
                    max_tokens=params.get("max_tokens"),
                )
            }


# Singleton instance
_handler: Optional[GeminiHandler] = None


def get_gemini_handler(config: Optional[GeminiConfig] = None) -> GeminiHandler:
    """Get or create Gemini handler singleton."""
    global _handler
    if _handler is None:
        _handler = GeminiHandler(config)
    return _handler
