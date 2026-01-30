"""
LLaMA3 Vietnamese Explanation Service

Provides Vietnamese language explanations for English grammar concepts.
Uses LLaMA3-3B quantized model for memory-efficient inference.

Features:
- Lazy loading (only loads when Vietnamese explanation needed)
- GGUF quantized format for CPU inference
- Context-aware grammar explanations
- Optimized for Vietnamese ESL learners
"""

from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class VietnameseExplanation:
    """Represents a Vietnamese explanation result."""
    
    def __init__(
        self,
        concept: str,
        explanation: str,
        examples: List[str],
        tips: List[str],
        duration_ms: float,
    ):
        self.concept = concept
        self.explanation = explanation
        self.examples = examples
        self.tips = tips
        self.duration_ms = duration_ms
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "concept": self.concept,
            "explanation": self.explanation,
            "examples": self.examples,
            "tips": self.tips,
            "duration_ms": self.duration_ms,
        }


# Pre-defined Vietnamese explanations for common grammar concepts
GRAMMAR_EXPLANATIONS_VI = {
    "subject_verb_agreement": {
        "title": "Sự hòa hợp chủ ngữ - động từ",
        "explanation": "Trong tiếng Anh, động từ phải chia theo chủ ngữ. Nếu chủ ngữ là ngôi thứ 3 số ít (he/she/it), động từ thêm 's' hoặc 'es'.",
        "examples": [
            "I go → He goes",
            "We play → She plays",
            "They have → It has",
        ],
        "tips": [
            "Nhớ: 'I' và 'You' không thêm 's'",
            "Động từ bất quy tắc: have → has, do → does",
        ],
    },
    "present_simple": {
        "title": "Thì Hiện tại đơn",
        "explanation": "Dùng để diễn tả thói quen, sự thật hiển nhiên, hoặc lịch trình cố định.",
        "examples": [
            "I wake up at 7 AM every day. (Thói quen)",
            "The sun rises in the east. (Sự thật)",
            "The train leaves at 9 PM. (Lịch trình)",
        ],
        "tips": [
            "Từ khóa: always, usually, often, sometimes, never, every day",
            "Phủ định: do not/don't, does not/doesn't",
        ],
    },
    "past_simple": {
        "title": "Thì Quá khứ đơn",
        "explanation": "Dùng để diễn tả hành động đã xảy ra và kết thúc trong quá khứ.",
        "examples": [
            "I visited Hanoi last week.",
            "She studied English yesterday.",
            "They went to the beach last summer.",
        ],
        "tips": [
            "Từ khóa: yesterday, last (week/month/year), ago, in 2020",
            "Động từ có quy tắc: thêm -ed (visit → visited)",
            "Động từ bất quy tắc: go → went, have → had",
        ],
    },
    "present_perfect": {
        "title": "Thì Hiện tại hoàn thành",
        "explanation": "Dùng để diễn tả hành động đã xảy ra trong quá khứ nhưng có liên quan đến hiện tại hoặc không xác định thời điểm.",
        "examples": [
            "I have visited Paris twice. (Kinh nghiệm)",
            "She has just finished her homework. (Vừa mới)",
            "They have lived here since 2010. (Kéo dài đến nay)",
        ],
        "tips": [
            "Cấu trúc: have/has + V3 (past participle)",
            "Từ khóa: already, just, yet, ever, never, since, for",
        ],
    },
    "articles": {
        "title": "Mạo từ a/an/the",
        "explanation": "Tiếng Việt không có mạo từ, nên đây là điểm khó với người Việt. 'A/an' dùng cho danh từ chưa xác định, 'the' dùng cho danh từ đã xác định.",
        "examples": [
            "I saw a cat. The cat was black. (cat không xác định → a, cat đã nói → the)",
            "She is an engineer. (bắt đầu bằng nguyên âm → an)",
            "The sun is bright. (chỉ có một → the)",
        ],
        "tips": [
            "a + phụ âm (a book, a car)",
            "an + nguyên âm (an apple, an hour)",
            "the + đã biết hoặc duy nhất",
        ],
    },
    "conditionals_first": {
        "title": "Câu điều kiện loại 1",
        "explanation": "Dùng để diễn tả điều kiện có thể xảy ra ở hiện tại hoặc tương lai.",
        "examples": [
            "If it rains, I will stay home.",
            "If you study hard, you will pass the exam.",
            "If she calls, tell her I'm busy.",
        ],
        "tips": [
            "Cấu trúc: If + hiện tại đơn, will + V",
            "Có thể đảo: Will + V if + hiện tại đơn",
        ],
    },
}


class LLaMAVietnameseService:
    """
    LLaMA3-3B based Vietnamese explanation service.
    
    Uses quantized GGUF model for efficient CPU inference.
    Falls back to pre-defined explanations when model unavailable.
    
    Memory: ~4GB when loaded (Q4 quantized)
    Latency: 200-500ms per explanation
    """
    
    def __init__(
        self,
        model_path: Optional[str] = None,
        use_predefined: bool = True,
    ):
        self.model_path = model_path
        self.use_predefined = use_predefined
        
        # Model components (lazy loaded)
        self.model = None
        self.is_loaded = False
        
        logger.info(
            f"LLaMAVietnameseService initialized "
            f"(model_path={model_path}, use_predefined={use_predefined})"
        )
    
    async def initialize(self) -> None:
        """Load LLaMA model if available."""
        if self.is_loaded:
            logger.info("LLaMA Vietnamese model already loaded")
            return
        
        if not self.model_path:
            logger.info("No model path provided, using predefined explanations only")
            self.is_loaded = True
            return
        
        model_file = Path(self.model_path)
        if not model_file.exists():
            logger.warning(
                f"Model file not found: {self.model_path}, "
                "using predefined explanations"
            )
            self.is_loaded = True
            return
        
        start_time = time.time()
        logger.info(f"Loading LLaMA Vietnamese model: {self.model_path}...")
        
        try:
            # Try to load with llama-cpp-python
            from llama_cpp import Llama
            
            self.model = Llama(
                model_path=str(model_file),
                n_ctx=2048,
                n_threads=4,
                n_gpu_layers=0,  # CPU only
                verbose=False,
            )
            
            self.is_loaded = True
            load_time = time.time() - start_time
            logger.info(f"✅ LLaMA model loaded in {load_time:.2f}s")
            
        except ImportError:
            logger.warning(
                "llama-cpp-python not installed, "
                "using predefined explanations only"
            )
            self.is_loaded = True
        except Exception as e:
            logger.error(f"Failed to load LLaMA model: {e}")
            self.is_loaded = True
    
    async def explain_in_vietnamese(
        self,
        concept: str,
        user_level: str = "A2",
        context: Optional[str] = None,
    ) -> VietnameseExplanation:
        """
        Generate Vietnamese explanation for an English grammar concept.
        
        Args:
            concept: Grammar concept to explain (e.g., "present_simple")
            user_level: CEFR level of learner (A1, A2, B1, B2)
            context: Optional context (e.g., user's error)
            
        Returns:
            VietnameseExplanation with explanation, examples, and tips
        """
        if not self.is_loaded:
            await self.initialize()
        
        start_time = time.time()
        
        # Normalize concept name
        concept_key = concept.lower().replace("-", "_").replace(" ", "_")
        
        # Check predefined explanations first
        if self.use_predefined and concept_key in GRAMMAR_EXPLANATIONS_VI:
            predefined = GRAMMAR_EXPLANATIONS_VI[concept_key]
            duration_ms = (time.time() - start_time) * 1000
            
            return VietnameseExplanation(
                concept=predefined["title"],
                explanation=predefined["explanation"],
                examples=predefined["examples"],
                tips=predefined["tips"],
                duration_ms=duration_ms,
            )
        
        # Try to generate with model if available
        if self.model is not None:
            return await self._generate_explanation(
                concept, user_level, context, start_time
            )
        
        # Fallback: generic explanation
        duration_ms = (time.time() - start_time) * 1000
        return VietnameseExplanation(
            concept=concept,
            explanation=f"Đây là điểm ngữ pháp quan trọng trong tiếng Anh: {concept}",
            examples=[],
            tips=["Hãy luyện tập thêm với các bài tập bên dưới."],
            duration_ms=duration_ms,
        )
    
    async def _generate_explanation(
        self,
        concept: str,
        user_level: str,
        context: Optional[str],
        start_time: float,
    ) -> VietnameseExplanation:
        """Generate explanation using LLaMA model."""
        prompt = f"""Bạn là một giáo viên tiếng Anh cho người Việt.
Giải thích ngữ pháp "{concept}" cho học viên trình độ {user_level}.

{"Ngữ cảnh: " + context if context else ""}

Trả lời bằng tiếng Việt, đơn giản và dễ hiểu.
Bao gồm:
1. Giải thích ngắn gọn
2. 2-3 ví dụ có nghĩa tiếng Việt
3. 1-2 mẹo nhớ

Trả lời:"""

        try:
            output = self.model(
                prompt,
                max_tokens=512,
                temperature=0.7,
                stop=["---", "\n\n\n"],
            )
            
            response_text = output["choices"][0]["text"].strip()
            
            # Parse response (simplified)
            duration_ms = (time.time() - start_time) * 1000
            
            return VietnameseExplanation(
                concept=concept,
                explanation=response_text,
                examples=[],
                tips=[],
                duration_ms=duration_ms,
            )
            
        except Exception as e:
            logger.error(f"LLaMA generation failed: {e}")
            duration_ms = (time.time() - start_time) * 1000
            
            return VietnameseExplanation(
                concept=concept,
                explanation=f"Xin lỗi, không thể tạo giải thích lúc này: {concept}",
                examples=[],
                tips=[],
                duration_ms=duration_ms,
            )
    
    async def translate_with_context(
        self,
        text: str,
        grammar_point: Optional[str] = None,
    ) -> Dict[str, str]:
        """
        Translate English text to Vietnamese with grammar context.
        
        Args:
            text: English text to translate
            grammar_point: Related grammar point for context
            
        Returns:
            Dictionary with translation and notes
        """
        if not self.is_loaded:
            await self.initialize()
        
        # Simple translation using model if available
        if self.model is not None:
            prompt = f"""Dịch câu sau sang tiếng Việt:
"{text}"

{"Điểm ngữ pháp liên quan: " + grammar_point if grammar_point else ""}

Dịch nghĩa:"""

            try:
                output = self.model(
                    prompt,
                    max_tokens=256,
                    temperature=0.3,
                )
                
                translation = output["choices"][0]["text"].strip()
                
                return {
                    "original": text,
                    "translation": translation,
                    "grammar_point": grammar_point or "",
                }
                
            except Exception as e:
                logger.error(f"Translation failed: {e}")
        
        # Fallback
        return {
            "original": text,
            "translation": "[Không thể dịch lúc này]",
            "grammar_point": grammar_point or "",
        }
    
    def unload(self) -> None:
        """Unload model to free memory."""
        if self.model is not None:
            del self.model
            self.model = None
        
        self.is_loaded = False
        
        import gc
        gc.collect()
        
        logger.info("LLaMA Vietnamese model unloaded")


# Singleton instance
_llama_vi_service: Optional[LLaMAVietnameseService] = None


async def get_llama_vietnamese_service() -> LLaMAVietnameseService:
    """Get or create singleton LLaMA Vietnamese service instance."""
    global _llama_vi_service
    
    if _llama_vi_service is None:
        from api.core.config import settings
        
        model_path = getattr(
            settings,
            "LLAMA_VI_MODEL_PATH",
            None
        )
        use_predefined = getattr(
            settings,
            "LLAMA_VI_USE_PREDEFINED",
            True
        )
        
        _llama_vi_service = LLaMAVietnameseService(
            model_path=model_path,
            use_predefined=use_predefined,
        )
    
    return _llama_vi_service
