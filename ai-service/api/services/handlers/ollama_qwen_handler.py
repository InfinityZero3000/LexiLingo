"""
Ollama Qwen Handler - Chat and Grammar Analysis via Ollama

Uses local Ollama server with qwen3-lexi model for:
- Chat/conversation
- Grammar analysis
- Fluency scoring
- Text completion

NO HuggingFace dependency - pure Ollama API.
"""

import logging
import asyncio
import json
import httpx
from typing import Optional, Dict, Any, List
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class OllamaQwenConfig:
    """Configuration for Ollama Qwen model."""
    base_url: str = "http://localhost:11434"
    model: str = "qwen2.5:1.5b"  # Model name in Ollama
    timeout: float = 120.0
    temperature: float = 0.7
    top_p: float = 0.9
    context_length: int = 2048
    num_threads: int = 8
    keep_alive: str = "24h"


class OllamaQwenHandler:
    """
    Handler for Qwen model via Ollama API.
    
    Uses local Ollama server - no model loading required.
    Models are managed by Ollama, providing:
    - Fast inference with pre-loaded models
    - Memory management by Ollama
    - Easy model switching
    """
    
    def __init__(self, config: Optional[OllamaQwenConfig] = None):
        self.config = config or OllamaQwenConfig()
        self.client: Optional[httpx.AsyncClient] = None
        self._loaded = False
        
    @property
    def is_loaded(self) -> bool:
        return self._loaded
    
    @property
    def memory_usage_mb(self) -> float:
        """Memory is managed by Ollama, not by us."""
        return 0.0
    
    async def load(self) -> bool:
        """
        Initialize HTTP client for Ollama.
        
        Since Ollama manages the model, we just need to
        check that the server is reachable.
        """
        if self._loaded:
            return True
        
        try:
            logger.info(f"[OllamaQwenHandler] Connecting to Ollama at {self.config.base_url}...")
            
            self.client = httpx.AsyncClient(
                base_url=self.config.base_url,
                timeout=self.config.timeout,
            )
            
            # Health check
            response = await self.client.get("/api/tags")
            if response.status_code == 200:
                models = response.json().get("models", [])
                model_names = [m["name"] for m in models]
                
                # Check if our model exists
                model_found = any(self.config.model in name for name in model_names)
                if model_found:
                    logger.info(f"[OllamaQwenHandler] ✓ Model '{self.config.model}' available")
                else:
                    logger.warning(
                        f"[OllamaQwenHandler] Model '{self.config.model}' not found. "
                        f"Available: {model_names}"
                    )
                
                self._loaded = True
                logger.info(f"[OllamaQwenHandler] ✓ Connected to Ollama")
                return True
            else:
                logger.error(f"[OllamaQwenHandler] Ollama not responding: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"[OllamaQwenHandler] Failed to connect: {e}")
            return False
    
    async def unload(self) -> None:
        """Close HTTP client."""
        if self.client:
            await self.client.aclose()
            self.client = None
        self._loaded = False
        logger.info("[OllamaQwenHandler] Handler unloaded")
    
    async def chat(
        self,
        messages: Optional[List[Dict[str, str]]] = None,
        temperature: Optional[float] = None,
        max_tokens: int = 512,
        system_prompt: Optional[str] = None,
        message: Optional[str] = None,
        system: Optional[str] = None,
        **kwargs,
    ) -> str:
        """
        Generate chat response via Ollama.
        
        Args:
            messages: List of {"role": "user/assistant", "content": "..."}
            temperature: Override config temperature
            max_tokens: Maximum tokens to generate
            system_prompt: System prompt (alias: system)
            message: Simple message string (will be wrapped)
            
        Returns:
            Generated response text
        """
        if not await self.load():
            raise RuntimeError("Failed to connect to Ollama")
        
        # Handle simple message input
        if message and not messages:
            messages = [{"role": "user", "content": message}]
        
        # Handle system prompt alias
        if system and not system_prompt:
            system_prompt = system
        
        # Build messages with system prompt
        if system_prompt and messages:
            full_messages = [{"role": "system", "content": system_prompt}]
            full_messages.extend(messages)
        else:
            full_messages = messages or []
        
        payload = {
            "model": self.config.model,
            "messages": full_messages,
            "stream": False,
            "options": {
                "temperature": temperature or self.config.temperature,
                "top_p": self.config.top_p,
                "num_ctx": self.config.context_length,
                "num_thread": self.config.num_threads,
                "num_predict": max_tokens,
            },
            "keep_alive": self.config.keep_alive,
        }
        
        try:
            # Use longer timeout for inference
            timeout = httpx.Timeout(300.0, connect=30.0)
            if self.client is None:
                raise RuntimeError("Ollama client not initialized. Call load() first.")
            response = await self.client.post(
                "/api/chat",
                json=payload,
                timeout=timeout,
            )
            response.raise_for_status()
            
            data = response.json()
            return data.get("message", {}).get("content", "")
            
        except httpx.TimeoutException:
            logger.error("[OllamaQwenHandler] Request timeout")
            raise RuntimeError("Ollama request timeout")
        except Exception as e:
            logger.error(f"[OllamaQwenHandler] Chat failed: {e}")
            raise
    
    async def analyze_grammar(
        self,
        text: str,
        target_language: str = "English",
    ) -> Dict[str, Any]:
        """
        Analyze grammar and provide corrections.
        
        Returns:
            {
                "errors": [{"span": "...", "correction": "...", "type": "...", "explanation": "..."}],
                "corrected_text": "...",
                "grammar_score": 0.0-1.0,
                "fluency_score": 0.0-1.0,
            }
        """
        system_prompt = f"""You are an expert {target_language} grammar tutor.
Analyze the following text and identify ALL grammar errors.
For each error, provide:
1. The error span (exact text)
2. The correction
3. Error type (grammar/spelling/punctuation/word_choice)
4. Brief explanation

Output JSON format:
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
            messages=messages,
            system_prompt=system_prompt,
            temperature=0.3,  # Lower temp for analysis
            max_tokens=800,
        )
        
        # Parse JSON response
        try:
            # Extract JSON from response
            if "```json" in response:
                json_str = response.split("```json")[1].split("```")[0]
            elif "```" in response:
                json_str = response.split("```")[1].split("```")[0]
            else:
                # Try to find JSON object
                import re
                json_match = re.search(r'\{[\s\S]*\}', response)
                if json_match:
                    json_str = json_match.group()
                else:
                    json_str = response
                
            result = json.loads(json_str.strip())
            return result
        except json.JSONDecodeError:
            # Fallback parsing
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
        """
        Generate tutor response for the learner.
        """
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
            messages=messages,
            system_prompt=system_prompt,
            temperature=0.7,
            max_tokens=400,
        )
    
    async def invoke(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Unified invoke interface for ModelGateway.
        
        Args:
            params: {
                "task": "chat" | "grammar" | "response",
                "text": "...",
                "messages": [...],
                ...other params
            }
            
        Returns:
            Task-specific result
        """
        task = params.get("task", "chat")
        
        if task == "grammar":
            text = params.get("text", "")
            return await self.analyze_grammar(text)
            
        elif task == "response":
            return {
                "response": await self.generate_response(
                    user_input=params.get("text", ""),
                    context=params.get("context"),
                    learner_level=params.get("level", "B1"),
                    errors=params.get("errors"),
                )
            }
            
        else:  # chat
            messages = params.get("messages", [])
            text = params.get("text") or params.get("message")
            if not messages and text:
                messages = [{"role": "user", "content": text}]
            
            return {
                "response": await self.chat(
                    messages=messages,
                    system_prompt=params.get("system_prompt") or params.get("system"),
                    temperature=params.get("temperature"),
                    max_tokens=params.get("max_tokens", 512),
                )
            }


# Singleton instance
_handler: Optional[OllamaQwenHandler] = None


def get_ollama_qwen_handler(config: Optional[OllamaQwenConfig] = None) -> OllamaQwenHandler:
    """Get or create Ollama Qwen handler singleton."""
    global _handler
    if _handler is None:
        _handler = OllamaQwenHandler(config)
    return _handler
