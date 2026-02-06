"""
Ollama Service - Local LLM inference với Qwen 3.0:8B

Sử dụng Ollama để chạy Qwen 3.0:8B model locally.
Thay thế Gemini API với local inference.
"""

from __future__ import annotations

import logging
import json
from typing import Dict, List, Optional, Any, AsyncIterator
import httpx
import asyncio

logger = logging.getLogger(__name__)


class OllamaService:
    """
    Service wrapper cho Ollama API.
    
    Ollama API endpoints:
    - POST /api/generate - Generate completion
    - POST /api/chat - Chat completion
    - GET /api/tags - List models
    """
    
    def __init__(
        self,
        base_url: str = "http://localhost:11434",
        model: str = "qwen2.5:8b",
        timeout: float = 120.0,
    ):
        """
        Initialize Ollama service.
        
        Args:
            base_url: Ollama server URL
            model: Model name (e.g., "qwen2.5:8b", "qwen3:8b")
            timeout: Request timeout in seconds
        """
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout = timeout
        self.client = httpx.AsyncClient(timeout=timeout)
        
        logger.info(f"OllamaService initialized: {base_url}, model={model}")
    
    async def health_check(self) -> bool:
        """Check if Ollama server is running."""
        try:
            response = await self.client.get(f"{self.base_url}/api/tags")
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Ollama health check failed: {e}")
            return False
    
    async def list_models(self) -> List[str]:
        """List available models in Ollama."""
        try:
            response = await self.client.get(f"{self.base_url}/api/tags")
            response.raise_for_status()
            data = response.json()
            return [m["name"] for m in data.get("models", [])]
        except Exception as e:
            logger.error(f"Failed to list models: {e}")
            return []
    
    async def generate(
        self,
        prompt: str,
        system: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: Optional[int] = None,
        stream: bool = False,
    ) -> str | AsyncIterator[str]:
        """
        Generate text completion.
        
        Args:
            prompt: User prompt
            system: System message
            temperature: Sampling temperature (0.0-1.0)
            max_tokens: Maximum tokens to generate
            stream: Stream response if True
            
        Returns:
            Generated text or async iterator for streaming
        """
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": stream,
            "options": {
                "temperature": temperature,
                "num_ctx": 2048,  # Limit context for speed
                "num_thread": 8,  # Multi-threading
            }
        }
        
        if system:
            payload["system"] = system
        
        if max_tokens:
            payload["options"]["num_predict"] = max_tokens
        
        try:
            if stream:
                return self._stream_generate(payload)
            else:
                # Longer timeout for first inference
                timeout = httpx.Timeout(300.0, connect=30.0)
                response = await self.client.post(
                    f"{self.base_url}/api/generate",
                    json=payload,
                    timeout=timeout
                )
                response.raise_for_status()
                data = response.json()
                return data.get("response", "")
                
        except Exception as e:
            logger.error(f"Ollama generate failed: {e}")
            raise
    
    async def _stream_generate(self, payload: Dict) -> AsyncIterator[str]:
        """Stream generated text chunks."""
        async with self.client.stream(
            "POST",
            f"{self.base_url}/api/generate",
            json=payload
        ) as response:
            async for line in response.aiter_lines():
                if line:
                    try:
                        data = json.loads(line)
                        if "response" in data:
                            yield data["response"]
                    except json.JSONDecodeError:
                        continue
    
    async def chat(
        self,
        messages: List[Dict[str, str]],
        temperature: float = 0.7,
        max_tokens: Optional[int] = None,
        stream: bool = False,
    ) -> str | AsyncIterator[str]:
        """
        Chat completion with message history.
        
        Args:
            messages: List of messages [{"role": "user/assistant", "content": "..."}]
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate
            stream: Stream response if True
            
        Returns:
            Generated response or async iterator
        """
        payload = {
            "model": self.model,
            "messages": messages,
            "stream": stream,
            "options": {
                "temperature": temperature,
                "num_ctx": 2048,  # Limit context window for faster inference
                "num_thread": 8,  # Use multiple threads
            }
        }
        
        if max_tokens:
            payload["options"]["num_predict"] = max_tokens
        
        try:
            if stream:
                return self._stream_chat(payload)
            else:
                # Use longer timeout for first inference (model loading)
                timeout = httpx.Timeout(300.0, connect=30.0)
                response = await self.client.post(
                    f"{self.base_url}/api/chat",
                    json=payload,
                    timeout=timeout
                )
                response.raise_for_status()
                data = response.json()
                return data.get("message", {}).get("content", "")
                
        except Exception as e:
            logger.error(f"Ollama chat failed: {e}")
            raise
    
    async def _stream_chat(self, payload: Dict) -> AsyncIterator[str]:
        """Stream chat response chunks."""
        async with self.client.stream(
            "POST",
            f"{self.base_url}/api/chat",
            json=payload
        ) as response:
            async for line in response.aiter_lines():
                if line:
                    try:
                        data = json.loads(line)
                        if "message" in data:
                            content = data["message"].get("content", "")
                            if content:
                                yield content
                    except json.JSONDecodeError:
                        continue
    
    async def analyze_text(
        self,
        text: str,
        task: str = "grammar",
        language: str = "en",
    ) -> Dict[str, Any]:
        """
        Analyze text for ESL learning tasks.
        
        Args:
            text: Input text to analyze
            task: Analysis task (grammar/fluency/vocabulary/dialogue)
            language: Target language
            
        Returns:
            Analysis results as dict
        """
        # Task-specific prompts
        prompts = {
            "grammar": f"""Analyze the following text for grammar errors and provide corrections:

Text: "{text}"

Provide your response in JSON format:
{{
    "has_errors": true/false,
    "errors": [
        {{
            "original": "incorrect text",
            "correction": "corrected text",
            "explanation": "explanation of the error"
        }}
    ],
    "corrected_text": "fully corrected version"
}}""",
            
            "fluency": f"""Score the fluency of this text from 0-100:

Text: "{text}"

Consider: natural flow, coherence, appropriate word choice.
Respond in JSON:
{{
    "fluency_score": 85,
    "feedback": "explanation of the score"
}}""",
            
            "vocabulary": f"""Classify vocabulary level (A2/B1/B2) for this text:

Text: "{text}"

Respond in JSON:
{{
    "level": "B1",
    "difficult_words": ["word1", "word2"],
    "suggestions": ["easier alternatives"]
}}""",
            
            "dialogue": f"""Generate an appropriate AI tutor response to this student input:

Student: "{text}"

Provide an encouraging, educational response."""
        }
        
        prompt = prompts.get(task, prompts["dialogue"])
        
        try:
            response = await self.generate(
                prompt=prompt,
                system="You are an English learning AI tutor. Provide clear, structured responses.",
                temperature=0.3,  # Lower temperature for more consistent analysis
            )
            
            # Try to parse JSON response
            if task in ["grammar", "fluency", "vocabulary"]:
                try:
                    # Extract JSON from response
                    import re
                    json_match = re.search(r'\{.*\}', response, re.DOTALL)
                    if json_match:
                        return json.loads(json_match.group())
                except json.JSONDecodeError:
                    pass
            
            return {"response": response, "task": task}
            
        except Exception as e:
            logger.error(f"Text analysis failed: {e}")
            return {"error": str(e)}
    
    async def close(self):
        """Close HTTP client."""
        await self.client.aclose()


# Singleton instance
_ollama_service: Optional[OllamaService] = None


def get_ollama_service() -> OllamaService:
    """Get singleton Ollama service instance."""
    global _ollama_service
    if _ollama_service is None:
        from api.core.config import settings
        _ollama_service = OllamaService(
            base_url=getattr(settings, 'OLLAMA_BASE_URL', 'http://localhost:11434'),
            model=getattr(settings, 'OLLAMA_MODEL', 'qwen2.5:8b'),
        )
    return _ollama_service
