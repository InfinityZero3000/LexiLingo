"""
Qwen Handler - Chat and Grammar Analysis

Manages Qwen3-1.7B model for:
- Chat/conversation
- Grammar analysis
- Fluency scoring
- Text completion
"""

import logging
import asyncio
from typing import Optional, Dict, Any, List
from dataclasses import dataclass
import os

logger = logging.getLogger(__name__)


@dataclass
class QwenConfig:
    """Configuration for Qwen model."""
    model_path: str = "models/qwen3-1.7b"
    model_id: str = "Qwen/Qwen2.5-1.5B-Instruct"  # Fallback to HF
    device: str = "cpu"  # cpu, cuda, mps
    max_memory_gb: float = 4.0
    context_length: int = 8192
    temperature: float = 0.7
    top_p: float = 0.9
    use_flash_attention: bool = False


class QwenHandler:
    """
    Handler for Qwen model operations.
    
    Implements lazy loading - model is only loaded when first needed.
    """
    
    def __init__(self, config: Optional[QwenConfig] = None):
        self.config = config or QwenConfig()
        self.model = None
        self.tokenizer = None
        self._loaded = False
        self._loading = False
        self._lock = asyncio.Lock()
        
    @property
    def is_loaded(self) -> bool:
        return self._loaded
    
    @property
    def memory_usage_mb(self) -> float:
        """Estimate memory usage."""
        if not self._loaded:
            return 0.0
        # Qwen 1.7B ≈ 3.5GB in float16
        return 3500.0
    
    async def load(self) -> bool:
        """
        Lazy load the Qwen model.
        
        Returns:
            True if loaded successfully
        """
        if self._loaded:
            return True
            
        async with self._lock:
            if self._loaded:  # Double-check
                return True
                
            if self._loading:
                # Wait for another load to complete
                while self._loading:
                    await asyncio.sleep(0.1)
                return self._loaded
            
            self._loading = True
            try:
                logger.info("[QwenHandler] Loading Qwen model...")
                
                # Import here to avoid loading at startup
                from transformers import AutoModelForCausalLM, AutoTokenizer
                import torch
                
                # Detect device
                device = self._detect_device()
                
                # Check local model first
                model_path = self.config.model_path
                if not os.path.exists(model_path):
                    model_path = self.config.model_id
                    logger.info(f"[QwenHandler] Local model not found, using HuggingFace: {model_path}")
                
                # Load tokenizer
                self.tokenizer = AutoTokenizer.from_pretrained(
                    model_path,
                    trust_remote_code=True,
                )
                
                # Load model with appropriate dtype
                dtype = torch.float16 if device != "cpu" else torch.float32
                
                self.model = AutoModelForCausalLM.from_pretrained(
                    model_path,
                    torch_dtype=dtype,
                    device_map=device if device != "mps" else "auto",
                    trust_remote_code=True,
                    low_cpu_mem_usage=True,
                )
                
                if device == "mps":
                    self.model = self.model.to("mps")
                
                self.model.eval()
                
                self._loaded = True
                logger.info(f"[QwenHandler] ✓ Qwen model loaded on {device}")
                return True
                
            except Exception as e:
                logger.error(f"[QwenHandler] Failed to load model: {e}")
                self._loaded = False
                return False
            finally:
                self._loading = False
    
    def _detect_device(self) -> str:
        """Detect best available device."""
        import torch
        
        if self.config.device != "auto":
            return self.config.device
            
        if torch.cuda.is_available():
            return "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
        return "cpu"
    
    async def unload(self) -> None:
        """Unload model to free memory."""
        if self.model is not None:
            del self.model
            self.model = None
        if self.tokenizer is not None:
            del self.tokenizer
            self.tokenizer = None
            
        self._loaded = False
        
        # Force garbage collection
        import gc
        gc.collect()
        
        try:
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except:
            pass
            
        logger.info("[QwenHandler] Model unloaded")
    
    async def chat(
        self,
        messages: List[Dict[str, str]],
        temperature: Optional[float] = None,
        max_tokens: int = 512,
        system_prompt: Optional[str] = None,
    ) -> str:
        """
        Generate chat response.
        
        Args:
            messages: List of {"role": "user/assistant", "content": "..."}
            temperature: Override config temperature
            max_tokens: Maximum tokens to generate
            system_prompt: Optional system prompt
            
        Returns:
            Generated response text
        """
        if not await self.load():
            raise RuntimeError("Failed to load Qwen model")
        
        # Build conversation
        if system_prompt:
            full_messages = [{"role": "system", "content": system_prompt}]
            full_messages.extend(messages)
        else:
            full_messages = messages
        
        # Apply chat template
        text = self.tokenizer.apply_chat_template(
            full_messages,
            tokenize=False,
            add_generation_prompt=True,
        )
        
        # Tokenize
        inputs = self.tokenizer(text, return_tensors="pt")
        inputs = {k: v.to(self.model.device) for k, v in inputs.items()}
        
        # Generate
        import torch
        with torch.no_grad():
            outputs = self.model.generate(
                **inputs,
                max_new_tokens=max_tokens,
                temperature=temperature or self.config.temperature,
                top_p=self.config.top_p,
                do_sample=True,
                pad_token_id=self.tokenizer.eos_token_id,
            )
        
        # Decode only the new tokens
        new_tokens = outputs[0][inputs["input_ids"].shape[1]:]
        response = self.tokenizer.decode(new_tokens, skip_special_tokens=True)
        
        return response.strip()
    
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
            messages,
            system_prompt=system_prompt,
            temperature=0.3,  # Lower temp for analysis
            max_tokens=800,
        )
        
        # Parse JSON response
        try:
            import json
            # Extract JSON from response
            if "```json" in response:
                json_str = response.split("```json")[1].split("```")[0]
            elif "```" in response:
                json_str = response.split("```")[1].split("```")[0]
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
        
        Args:
            user_input: What the user said
            context: Additional context from knowledge graph
            learner_level: CEFR level (A1-C2)
            errors: Grammar errors found
            
        Returns:
            Tutor response text
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
            messages,
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
            if not messages and params.get("text"):
                messages = [{"role": "user", "content": params["text"]}]
            
            return {
                "response": await self.chat(
                    messages=messages,
                    system_prompt=params.get("system_prompt"),
                    temperature=params.get("temperature"),
                    max_tokens=params.get("max_tokens", 512),
                )
            }


# Singleton instance
_handler: Optional[QwenHandler] = None


def get_qwen_handler(config: Optional[QwenConfig] = None) -> QwenHandler:
    """Get or create Qwen handler singleton."""
    global _handler
    if _handler is None:
        _handler = QwenHandler(config)
    return _handler
