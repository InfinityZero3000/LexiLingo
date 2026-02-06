"""
Smart Model Router - Automatically route requests to optimal model

Route based on:
- Text complexity
- Query type
- Latency requirements
"""

import os
import logging
from typing import Literal, Optional
from dataclasses import dataclass

logger = logging.getLogger(__name__)

ModelType = Literal["local_fast", "local_quality", "cloud"]


@dataclass
class RoutingDecision:
    """Decision about which model to use."""
    model: ModelType
    reason: str
    estimated_latency: float  # seconds


class SmartRouter:
    """Route requests to optimal model based on complexity."""
    
    def __init__(self):
        # Load config from env
        self.hybrid_mode = os.getenv("HYBRID_MODE", "false").lower() == "true"
        self.complexity_threshold = int(os.getenv("COMPLEXITY_THRESHOLD", "50"))
        
        # Model latency estimates (seconds)
        self.latency_estimates = {
            "local_fast": 3.0,      # gemma2:2b, phi-3:mini
            "local_quality": 20.0,  # qwen3:4b-thinking
            "cloud": 2.0,           # Gemini
        }
        
    def analyze_complexity(self, text: str) -> dict:
        """Analyze text complexity."""
        words = text.split()
        word_count = len(words)
        
        # Check for complex patterns
        has_long_sentences = any(len(word) > 15 for word in words)
        has_technical_terms = any(
            keyword in text.lower() 
            for keyword in ["grammar", "tense", "clause", "syntax"]
        )
        
        # Simple heuristics
        is_greeting = word_count <= 5 and any(
            word in text.lower() 
            for word in ["hi", "hello", "hey", "thanks", "bye"]
        )
        
        is_grammar_query = any(
            keyword in text.lower()
            for keyword in ["correct", "mistake", "wrong", "error", "grammar"]
        )
        
        return {
            "word_count": word_count,
            "is_simple": word_count < 10,
            "is_greeting": is_greeting,
            "is_grammar": is_grammar_query,
            "has_technical": has_technical_terms,
            "has_long_words": has_long_sentences,
        }
    
    def route(self, text: str, task_type: Optional[str] = None) -> RoutingDecision:
        """
        Determine optimal model for request.
        
        Args:
            text: Input text
            task_type: Optional task type hint (chat, grammar, etc.)
            
        Returns:
            RoutingDecision with model choice and reason
        """
        # If hybrid mode disabled, use cloud (Gemini)
        if not self.hybrid_mode:
            return RoutingDecision(
                model="cloud",
                reason="Hybrid mode disabled",
                estimated_latency=self.latency_estimates["cloud"],
            )
        
        complexity = self.analyze_complexity(text)
        
        # Rule 1: Simple greetings → local fast
        if complexity["is_greeting"]:
            return RoutingDecision(
                model="local_fast",
                reason="Simple greeting - local model sufficient",
                estimated_latency=self.latency_estimates["local_fast"],
            )
        
        # Rule 2: Grammar tasks → cloud (need high quality)
        if complexity["is_grammar"] or task_type == "grammar":
            return RoutingDecision(
                model="cloud",
                reason="Grammar analysis requires high quality",
                estimated_latency=self.latency_estimates["cloud"],
            )
        
        # Rule 3: Long/complex text → cloud
        if complexity["word_count"] > self.complexity_threshold:
            return RoutingDecision(
                model="cloud",
                reason=f"Long text ({complexity['word_count']} words) - use cloud",
                estimated_latency=self.latency_estimates["cloud"],
            )
        
        # Rule 4: Technical terms → cloud
        if complexity["has_technical"]:
            return RoutingDecision(
                model="cloud",
                reason="Technical content - use high-quality model",
                estimated_latency=self.latency_estimates["cloud"],
            )
        
        # Rule 5: Simple chat → local fast
        if complexity["is_simple"]:
            return RoutingDecision(
                model="local_fast",
                reason="Simple query - local model OK",
                estimated_latency=self.latency_estimates["local_fast"],
            )
        
        # Default: Use cloud for best quality
        return RoutingDecision(
            model="cloud",
            reason="Default to cloud for quality",
            estimated_latency=self.latency_estimates["cloud"],
        )
    
    def get_model_name(self, model_type: ModelType) -> str:
        """Get actual model name for model type."""
        mapping = {
            "local_fast": os.getenv("OLLAMA_MODEL_SIMPLE", "gemma2:2b"),
            "local_quality": os.getenv("OLLAMA_MODEL", "qwen3:4b"),
            "cloud": "gemini",
        }
        return mapping[model_type]
    
    def log_routing_decision(self, text: str, decision: RoutingDecision):
        """Log routing decision for debugging."""
        logger.info(
            f"[SmartRouter] '{text[:50]}...' → {decision.model} "
            f"({decision.reason}, ~{decision.estimated_latency}s)"
        )


# Global router instance
_router: Optional[SmartRouter] = None


def get_router() -> SmartRouter:
    """Get or create global router instance."""
    global _router
    if _router is None:
        _router = SmartRouter()
    return _router


# Example usage
if __name__ == "__main__":
    router = SmartRouter()
    
    # Test cases
    test_cases = [
        ("Hi", None),
        ("Hello, how are you?", None),
        ("Can you check my grammar: I goes to school", "grammar"),
        ("Explain the difference between present perfect and past simple tense in detail", "chat"),
        ("Thanks!", None),
        ("What is the correct way to use the subjunctive mood in English? I'm confused about when to use it.", "chat"),
    ]
    
    print("Smart Routing Test")
    print("=" * 60)
    for text, task in test_cases:
        decision = router.route(text, task)
        print(f"\nInput: {text}")
        print(f"  → Model: {decision.model}")
        print(f"  → Reason: {decision.reason}")
        print(f"  → Est. latency: {decision.estimated_latency}s")
