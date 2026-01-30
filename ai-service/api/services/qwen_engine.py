"""
Qwen3-1.7B Engine with Unified LoRA Adapter

This engine handles comprehensive English analysis tasks:
1. Fluency scoring
2. Vocabulary classification (A2/B1/B2)
3. Grammar correction
4. Dialogue response (AI tutor)
5. Comprehensive analysis (all tasks combined)

Architecture:
- Base Model: Qwen/Qwen3-1.7B (1.7GB)
- LoRA Adapter: Unified adapter for all tasks (80MB)
- Inference: CPU/GPU with quantization support
- Output: Structured JSON responses
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class QwenEngine:
    """
    Qwen3-1.7B inference engine with LoRA adapter support.
    
    Supports two modes:
    1. Base model only (without fine-tuning)
    2. Base model + LoRA adapter (trained for ESL tasks)
    
    Performance targets:
    - Latency: 100-150ms per request
    - Memory: ~3.5GB (base) + 80MB (adapter)
    - Quality: 95-97% of specialized adapters
    """
    
    def __init__(
        self,
        model_name: str = "Qwen/Qwen3-1.7B",
        adapter_path: Optional[str] = None,
        device: str = "auto",
        load_in_8bit: bool = False,
        load_in_4bit: bool = False,
    ):
        """
        Initialize Qwen engine.
        
        Args:
            model_name: Hugging Face model name or local path
            adapter_path: Path to LoRA adapter (optional)
            device: "auto", "cpu", "cuda", or specific GPU id
            load_in_8bit: Use 8-bit quantization (saves memory)
            load_in_4bit: Use 4-bit quantization (saves more memory)
        """
        self.model_name = model_name
        self.adapter_path = adapter_path
        self.device = device
        self.load_in_8bit = load_in_8bit
        self.load_in_4bit = load_in_4bit
        
        # Model components (loaded lazily)
        self.model = None
        self.tokenizer = None
        self.is_loaded = False
        
        logger.info(
            f"QwenEngine initialized: model={model_name}, "
            f"adapter={adapter_path}, device={device}"
        )
    
    async def initialize(self) -> None:
        """
        Load model and tokenizer asynchronously.
        
        This should be called before first inference to avoid
        blocking the main thread during model loading.
        """
        if self.is_loaded:
            logger.info("Qwen model already loaded")
            return
        
        start_time = time.time()
        logger.info(f"Loading Qwen model: {self.model_name}...")
        
        try:
            from transformers import AutoTokenizer, AutoModelForCausalLM
            import torch
            
            # Load tokenizer
            logger.info("  Loading tokenizer...")
            self.tokenizer = AutoTokenizer.from_pretrained(
                self.model_name,
                trust_remote_code=True
            )
            
            # Prepare loading arguments
            kwargs = {
                "trust_remote_code": True,
                "device_map": self.device,
            }
            
            # Add quantization if requested
            if self.load_in_8bit:
                kwargs["load_in_8bit"] = True
                logger.info("  Using 8-bit quantization")
            elif self.load_in_4bit:
                kwargs["load_in_4bit"] = True
                logger.info("  Using 4-bit quantization")
            
            # Load base model
            logger.info("  Loading base model...")
            self.model = AutoModelForCausalLM.from_pretrained(
                self.model_name,
                **kwargs
            )
            
            # Load LoRA adapter if provided
            if self.adapter_path:
                logger.info(f"  Loading LoRA adapter from {self.adapter_path}...")
                from peft import PeftModel
                
                self.model = PeftModel.from_pretrained(
                    self.model,
                    self.adapter_path
                )
                logger.info("  LoRA adapter loaded successfully")
            
            # Set to eval mode
            self.model.eval()
            
            self.is_loaded = True
            load_time = time.time() - start_time
            logger.info(f"✅ Qwen model loaded successfully in {load_time:.2f}s")
            
        except Exception as e:
            logger.error(f"Failed to load Qwen model: {e}", exc_info=True)
            raise
    
    def _build_prompt(
        self,
        task: str,
        text: str,
        context: Optional[Dict[str, Any]] = None,
        strategy: Optional[str] = None
    ) -> str:
        """
        Build task-specific prompt for Qwen model.
        
        Args:
            task: Task type (fluency_scoring, vocabulary_classification, 
                  grammar_correction, dialogue_response, comprehensive_analysis)
            text: User input text to analyze
            context: Optional context (conversation history, learner profile)
            strategy: Optional tutoring strategy (socratic, scaffolding, feedback)
        
        Returns:
            Formatted prompt string
        """
        
        # Extract context info
        level = "B1"  # Default
        history = ""
        history_str = ""  # Precomputed for f-string
        
        if context:
            level = context.get("learner_level", "B1")
            hist_list = context.get("conversation_history", [])
            if hist_list:
                history = "\n".join([
                    f"- {turn.get('role', 'user')}: {turn.get('text', '')}"
                    for turn in hist_list[-3:]  # Last 3 turns
                ])
                history_str = "Conversation History:\n" + history
        
        # Task-specific prompts
        if task == "fluency_scoring":
            prompt = f"""Task: fluency_scoring
Text: {text}
Learner Level: {level}

Analyze the fluency of this English text. Consider:
- Natural flow and coherence
- Appropriate word choice
- Sentence structure variety
- Overall readability

Respond in JSON format:
{{
  "fluency_score": <float 0.0-1.0>,
  "reasoning": "<brief explanation>"
}}"""
        
        elif task == "vocabulary_classification":
            prompt = f"""Task: vocabulary_classification
Text: {text}

Classify the vocabulary level used in this text according to CEFR levels (A2, B1, B2).
Identify key words that determine the level.

Respond in JSON format:
{{
  "level": "<A2|B1|B2>",
  "key_words": ["word1", "word2", ...],
  "reasoning": "<brief explanation>"
}}"""
        
        elif task == "grammar_correction":
            prompt = f"""Task: grammar_correction
Text: {text}
Learner Level: {level}

Identify and correct grammar errors in this text.

Respond in JSON format:
{{
  "corrected": "<corrected text>",
  "errors": [
    {{
      "error": "<incorrect phrase>",
      "correction": "<correct phrase>",
      "type": "<error type>",
      "explanation": "<brief explanation>"
    }}
  ]
}}"""
        
        elif task == "dialogue_response":
            strategy_desc = strategy or "positive_feedback"
            prompt = f"""Task: dialogue_response
User Message: {text}
Learner Level: {level}
Strategy: {strategy_desc}

{history_str}

You are an AI English tutor. Respond to the learner's message using the {strategy_desc} strategy.

Strategies:
- socratic_questioning: Guide with questions ("What tense should we use?")
- scaffolding: Break into smaller steps ("Let's first check the verb...")
- positive_feedback: Encourage and correct gently ("Good try! ...")
- praise: Celebrate success ("Excellent work!")

Respond in JSON format:
{{
  "response": "<your tutor response>",
  "strategy": "{strategy_desc}",
  "pedagogical_goal": "<what you're trying to teach>"
}}"""
        
        elif task == "comprehensive_analysis":
            prompt = f"""Task: comprehensive_analysis
Text: {text}
Learner Level: {level}

{history_str}

Perform comprehensive analysis of this English text, including:
1. Fluency scoring (0.0-1.0)
2. Vocabulary level classification (A2/B1/B2)
3. Grammar error detection and correction
4. Supportive tutor response

Respond in JSON format:
{{
  "fluency_score": <float>,
  "vocabulary_level": "<A2|B1|B2>",
  "grammar": {{
    "corrected": "<corrected text>",
    "errors": [
      {{"error": "...", "correction": "...", "type": "...", "explanation": "..."}}
    ]
  }},
  "response": "<supportive tutor message>",
  "confidence": <float 0.0-1.0>
}}"""
        
        else:
            raise ValueError(f"Unknown task type: {task}")
        
        return prompt
    
    async def generate(
        self,
        prompt: str,
        max_new_tokens: int = 512,
        temperature: float = 0.7,
        top_p: float = 0.9,
    ) -> Dict[str, Any]:
        """
        Generate response from Qwen model.
        
        Args:
            prompt: Input prompt
            max_new_tokens: Maximum tokens to generate
            temperature: Sampling temperature (0.0 = deterministic)
            top_p: Nucleus sampling threshold
        
        Returns:
            Parsed JSON response
        """
        if not self.is_loaded:
            await self.initialize()
        
        start_time = time.time()
        
        try:
            import torch
            
            # Tokenize input
            inputs = self.tokenizer(
                prompt,
                return_tensors="pt",
                truncation=True,
                max_length=2048
            ).to(self.model.device)
            
            # Generate
            with torch.no_grad():
                outputs = self.model.generate(
                    **inputs,
                    max_new_tokens=max_new_tokens,
                    temperature=temperature,
                    top_p=top_p,
                    do_sample=temperature > 0,
                    pad_token_id=self.tokenizer.eos_token_id,
                )
            
            # Decode output
            generated_text = self.tokenizer.decode(
                outputs[0][inputs.input_ids.shape[1]:],
                skip_special_tokens=True
            )
            
            # Parse JSON response
            try:
                result = json.loads(generated_text.strip())
            except json.JSONDecodeError:
                # Fallback: try to extract JSON from text
                import re
                json_match = re.search(r'\{.*\}', generated_text, re.DOTALL)
                if json_match:
                    result = json.loads(json_match.group(0))
                else:
                    logger.warning(f"Failed to parse JSON from output: {generated_text}")
                    result = {"raw_output": generated_text, "parse_error": True}
            
            inference_time = time.time() - start_time
            logger.info(f"Generated response in {inference_time*1000:.1f}ms")
            
            return result
            
        except Exception as e:
            logger.error(f"Generation failed: {e}", exc_info=True)
            raise
    
    async def analyze(
        self,
        text: str,
        task: str = "comprehensive_analysis",
        context: Optional[Dict[str, Any]] = None,
        strategy: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        High-level analysis method.
        
        Args:
            text: Input text to analyze
            task: Analysis task type
            context: Optional context information
            strategy: Optional tutoring strategy
        
        Returns:
            Analysis results as dictionary
        """
        # Build prompt
        prompt = self._build_prompt(task, text, context, strategy)
        
        # Generate response
        result = await self.generate(prompt)
        
        return result
    
    def unload(self) -> None:
        """Unload model to free memory."""
        if self.model is not None:
            del self.model
            self.model = None
        
        if self.tokenizer is not None:
            del self.tokenizer
            self.tokenizer = None
        
        self.is_loaded = False
        
        # Force garbage collection
        import gc
        gc.collect()
        
        # Clear CUDA cache if available
        try:
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except ImportError:
            pass
        
        logger.info("Qwen model unloaded")


# Singleton instance
_qwen_engine: Optional[QwenEngine] = None


async def get_qwen_engine() -> QwenEngine:
    """Get or create singleton Qwen engine instance."""
    global _qwen_engine
    
    if _qwen_engine is None:
        # TODO: Load config from settings
        from api.core.config import settings
        
        model_name = getattr(settings, "QWEN_MODEL_NAME", "Qwen/Qwen3-1.7B")
        adapter_path = getattr(settings, "QWEN_ADAPTER_PATH", None)
        device = getattr(settings, "QWEN_DEVICE", "auto")
        load_in_8bit = getattr(settings, "QWEN_LOAD_IN_8BIT", False)
        
        _qwen_engine = QwenEngine(
            model_name=model_name,
            adapter_path=adapter_path,
            device=device,
            load_in_8bit=load_in_8bit
        )
        
        await _qwen_engine.initialize()
    
    return _qwen_engine
