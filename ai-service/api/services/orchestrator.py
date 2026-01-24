"""
AI Orchestrator - Central Coordination Engine

Orchestrates the entire AI pipeline for LexiLingo:
- Task analysis and execution planning
- Resource allocation and lazy loading
- Parallel and sequential task execution
- Error handling with graceful degradation
- State management and caching

Following architecture.md principles for optimal performance.
"""

import logging
import time
import asyncio
from typing import Dict, List, Any, Optional, Set
from datetime import datetime
from collections import defaultdict

from api.services.resource_manager import get_resource_manager
from api.services.metrics import get_metrics
from api.services.context_manager import ContextManager
from api.core.redis_client import RedisClient

logger = logging.getLogger(__name__)


class AIOrchestrator:
    """
    Central coordinator cho toàn bộ AI pipeline.
    
    Responsibilities:
    1. Task Analysis: Phân tích input → execution plan
    2. Resource Allocation: Lazy loading models theo nhu cầu
    3. Execution Coordination: Parallel/sequential task execution
    4. Result Aggregation: Combine outputs từ nhiều models
    5. Error Handling: Fallback strategies khi component fails
    6. State Management: Track conversation & cache results
    
    Performance targets:
    - Latency: <350ms
    - Memory: <5GB
    - Cache hit rate: >40%
    """
    
    def __init__(self):
        """Initialize AI Orchestrator with all components."""
        
        # Core components (always available)
        self.context_manager = ContextManager()
        self.resource_manager = get_resource_manager(max_memory_gb=8.0)
        self.metrics = get_metrics()
        self.cache: Optional[RedisClient] = None  # Initialize async
        
        # AI engines (lazy loaded)
        self.qwen_engine = None  # Primary: Qwen2.5-1.5B + LoRA
        self.llama_engine = None  # Secondary: LLaMA3-8B-VI (Vietnamese)
        self.hubert_engine = None  # Pronunciation: HuBERT-large
        self.whisper_engine = None  # STT: Faster-Whisper
        self.piper_engine = None  # TTS: Piper VITS
        
        # Track loaded models
        self.loaded_models: Set[str] = set()
        
        # Session state tracking
        self.session_states: Dict[str, Dict[str, Any]] = {}
        
        # Orchestrator state
        self.is_initialized = False
        
        logger.info("AIOrchestrator initialized")
    
    async def initialize(self):
        """
        Async initialization of orchestrator.
        
        Call this before first use to setup async resources.
        """
        if self.is_initialized:
            return
        
        # Initialize Redis cache
        try:
            self.cache = await RedisClient.get_instance()
            logger.info("✓ Redis cache connected")
        except Exception as e:
            logger.warning(f"Redis cache unavailable: {e}. Continuing without cache.")
            self.cache = None
        
        self.is_initialized = True
        logger.info("✓ Orchestrator initialized and ready")
    
    async def process_input(
        self,
        user_input: str,
        session_id: str,
        user_id: Optional[str] = None,
        input_type: str = "text",
        learner_profile: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Main entry point - xử lý toàn bộ AI pipeline.
        
        Args:
            user_input: Text từ user (hoặc transcript nếu voice)
            session_id: Unique conversation session ID
            user_id: Optional user ID for tracking
            input_type: "text" or "voice"
            learner_profile: User's learning profile (level, errors, etc.)
        
        Returns:
            Complete response with analysis, feedback, and metadata
            
        Flow:
        1. Task Analysis → Create execution plan
        2. Resource Allocation → Load required models
        3. Execute Pipeline → Run tasks (parallel + sequential)
        4. Aggregate Results → Combine all outputs
        5. Update State → Cache + metrics + conversation history
        """
        
        start_time = time.time()
        
        # Ensure initialized
        if not self.is_initialized:
            await self.initialize()
        
        logger.info(
            f"Processing input: session={session_id}, "
            f"type={input_type}, length={len(user_input)}"
        )
        
        try:
            # ========== PHASE 1: TASK ANALYSIS ==========
            execution_plan = await self._analyze_task(
                user_input, session_id, input_type, learner_profile
            )
            
            logger.debug(f"Execution plan: {execution_plan}")
            
            # ========== PHASE 2: RESOURCE ALLOCATION ==========
            await self._allocate_resources(execution_plan)
            
            # ========== PHASE 3: EXECUTE PIPELINE ==========
            results = await self._execute_pipeline(
                user_input, session_id, execution_plan
            )
            
            # ========== PHASE 4: AGGREGATE RESULTS ==========
            response = await self._aggregate_results(
                results, execution_plan, user_input
            )
            
            # ========== PHASE 5: UPDATE STATE ==========
            await self._update_state(session_id, user_id, response)
            
            # Add processing metadata
            processing_time_ms = int((time.time() - start_time) * 1000)
            response["metadata"] = {
                "processing_time_ms": processing_time_ms,
                "models_used": list(self.loaded_models),
                "cached": False,
                "timestamp": datetime.utcnow().isoformat()
            }
            
            # Record metrics
            self.metrics.record_request(
                latency_ms=processing_time_ms,
                models_used=list(self.loaded_models),
                success=True,
                cached=False
            )
            
            logger.info(
                f"✓ Request completed in {processing_time_ms}ms "
                f"(models: {self.loaded_models})"
            )
            
            return response
            
        except Exception as e:
            # Error handling with fallback
            processing_time_ms = int((time.time() - start_time) * 1000)
            
            logger.error(f"Orchestrator error: {e}", exc_info=True)
            self.metrics.record_error(error_type=type(e).__name__)
            
            return await self._handle_error(
                e, user_input, session_id, processing_time_ms
            )
    
    # =================================================================
    # PHASE 1: TASK ANALYSIS
    # =================================================================
    
    async def _analyze_task(
        self,
        text: str,
        session_id: str,
        input_type: str,
        learner_profile: Optional[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """
        Phân tích input để tạo execution plan.
        
        Quyết định:
        - Tasks nào cần chạy (fluency, grammar, vocab, dialogue)
        - Models nào cần load (Qwen, HuBERT, LLaMA3)
        - Strategy nào sử dụng (praise, scaffolding, socratic)
        - Priority level (normal, high, critical)
        
        Returns:
            Execution plan dict
        """
        
        # Get learner level
        level = "B1"  # Default
        if learner_profile:
            level = learner_profile.get("level", "B1")
        
        # Get conversation context
        context = await self.context_manager.get_context(session_id)
        
        # Initialize execution plan
        plan = {
            "primary_tasks": ["comprehensive_analysis"],  # Always run Qwen
            "parallel_tasks": [],
            "conditional_tasks": [],
            "strategy": "scaffolding",  # Default tutoring strategy
            "priority": "normal",
            "input_type": input_type,
            "learner_level": level
        }
        
        # Add pronunciation analysis if voice input
        if input_type == "voice":
            plan["parallel_tasks"].append("pronunciation")
            logger.debug("Added pronunciation task (voice input)")
        
        # Add Vietnamese explanation if beginner or complex text
        if level in ["A1", "A2"] or self._is_complex_text(text):
            plan["conditional_tasks"].append("vietnamese_explanation")
            logger.debug(f"Added Vietnamese task (level={level}, complex={self._is_complex_text(text)})")
        
        # Select tutoring strategy based on error history
        error_count = self._count_recent_errors(context.get("history", []))
        plan["strategy"] = self._select_strategy(error_count)
        
        logger.info(
            f"Task analysis: strategy={plan['strategy']}, "
            f"primary={len(plan['primary_tasks'])}, "
            f"parallel={len(plan['parallel_tasks'])}, "
            f"conditional={len(plan['conditional_tasks'])}"
        )
        
        return plan
    
    def _is_complex_text(self, text: str) -> bool:
        """
        Check if text is complex (triggers Vietnamese explanation).
        
        Complex if:
        - >20 words
        - Contains complex grammar patterns
        """
        import re
        
        word_count = len(text.split())
        if word_count > 20:
            return True
        
        # Complex grammar patterns
        complex_patterns = [
            r"\bhad been\b",  # Past perfect continuous
            r"\bwould have\b",  # Third conditional
            r"\bshould have\b",  # Modal perfect
            r"\b(which|whom|whose)\b",  # Relative clauses
            r"\balthough\b|\bwhereas\b",  # Complex conjunctions
        ]
        
        for pattern in complex_patterns:
            if re.search(pattern, text, re.IGNORECASE):
                return True
        
        return False
    
    def _count_recent_errors(self, history: List[Dict[str, Any]]) -> int:
        """Count grammar errors in recent conversation turns."""
        error_count = 0
        
        # Check last 5 turns
        for turn in history[-5:]:
            if turn.get("role") == "assistant":
                analysis = turn.get("analysis", {})
                grammar = analysis.get("grammar", {})
                errors = grammar.get("errors", [])
                error_count += len(errors)
        
        return error_count
    
    def _select_strategy(self, error_count: int) -> str:
        """
        Select tutoring strategy based on recent errors.
        
        Strategy hierarchy:
        - 0 errors: praise
        - 1-2 errors: positive_feedback
        - 3-4 errors: socratic_questioning
        - 5+ errors: scaffolding
        """
        if error_count == 0:
            return "praise"
        elif error_count <= 2:
            return "positive_feedback"
        elif error_count <= 4:
            return "socratic_questioning"
        else:
            return "scaffolding"
    
    # =================================================================
    # PHASE 2: RESOURCE ALLOCATION
    # =================================================================
    
    async def _allocate_resources(self, plan: Dict[str, Any]):
        """
        Load required models based on execution plan.
        
        Lazy loading strategy:
        - Qwen: Always load (primary model)
        - HuBERT: Load if pronunciation task
        - LLaMA3-VI: Load if Vietnamese task
        - Auto-manage memory if needed
        """
        
        # ALWAYS LOAD: Qwen (primary model)
        if "qwen" not in self.loaded_models:
            await self._load_qwen()
        
        # LOAD IF NEEDED: HuBERT (pronunciation)
        if "pronunciation" in plan["parallel_tasks"]:
            if "hubert" not in self.loaded_models:
                can_load = self.resource_manager.can_load_model("hubert")
                
                if can_load:
                    await self._load_hubert()
                else:
                    # Try to auto-manage memory
                    logger.info("Attempting auto memory management for HuBERT...")
                    freed = await self.resource_manager.auto_manage_memory("hubert")
                    
                    if freed:
                        await self._load_hubert()
                    else:
                        logger.warning("Cannot load HuBERT - insufficient memory, skipping pronunciation")
                        plan["parallel_tasks"].remove("pronunciation")
        
        # LOAD IF NEEDED: LLaMA3-VI (Vietnamese)
        if "vietnamese_explanation" in plan["conditional_tasks"]:
            if "llama" not in self.loaded_models:
                can_load = self.resource_manager.can_load_model("llama")
                
                if can_load:
                    # Note: Will lazy load later if actually needed (low confidence check)
                    logger.debug("LLaMA3-VI ready to load if needed")
                else:
                    logger.warning("Cannot load LLaMA3 - insufficient memory, skipping Vietnamese")
                    plan["conditional_tasks"].remove("vietnamese_explanation")
    
    async def _load_qwen(self):
        """Lazy load Qwen engine."""
        logger.info("Loading Qwen2.5-1.5B + Unified LoRA...")
        
        try:
            # TODO: Import actual Qwen engine when implemented
            # from api.services.qwen_engine import QwenUnifiedEngine
            # self.qwen_engine = QwenUnifiedEngine()
            # await self.qwen_engine.initialize()
            
            # Placeholder for now
            self.qwen_engine = "qwen_placeholder"
            
            self.resource_manager.allocate_memory("qwen")
            self.loaded_models.add("qwen")
            
            logger.info("✓ Qwen engine loaded")
            
        except Exception as e:
            logger.error(f"Failed to load Qwen: {e}")
            raise
    
    async def _load_hubert(self):
        """Lazy load HuBERT engine."""
        logger.info("Loading HuBERT-large...")
        
        try:
            # TODO: Import actual HuBERT engine when implemented
            # from api.services.pronunciation_service import HuBERTEngine
            # self.hubert_engine = HuBERTEngine()
            # await self.hubert_engine.initialize()
            
            # Placeholder for now
            self.hubert_engine = "hubert_placeholder"
            
            self.resource_manager.allocate_memory("hubert")
            self.loaded_models.add("hubert")
            
            logger.info("✓ HuBERT engine loaded")
            
        except Exception as e:
            logger.error(f"Failed to load HuBERT: {e}")
            # Non-critical, can continue without
            return
    
    async def _load_llama(self):
        """Lazy load LLaMA3-VI engine."""
        logger.info("Loading LLaMA3-8B-VI...")
        
        try:
            # TODO: Import actual LLaMA engine when implemented
            # from api.services.llama_engine import LLaMA3VietnameseEngine
            # self.llama_engine = LLaMA3VietnameseEngine()
            # await self.llama_engine.initialize()
            
            # Placeholder for now
            self.llama_engine = "llama_placeholder"
            
            self.resource_manager.allocate_memory("llama")
            self.loaded_models.add("llama")
            
            logger.info("✓ LLaMA3-VI engine loaded")
            
        except Exception as e:
            logger.error(f"Failed to load LLaMA3: {e}")
            # Non-critical, can continue without
            return
    
    # =================================================================
    # PHASE 3: EXECUTION COORDINATION
    # =================================================================
    
    async def _execute_pipeline(
        self,
        text: str,
        session_id: str,
        plan: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Execute all tasks according to plan.
        
        Flow:
        1. Check cache first
        2. Run primary + parallel tasks concurrently
        3. Run conditional tasks if needed
        4. Return all results
        """
        
        results = {}
        
        # Check cache
        if self.cache:
            cache_key = self._generate_cache_key(text)
            cached = await self.cache.get(f"response:{cache_key}")
            
            if cached:
                logger.info(f"✓ Cache hit for: {text[:50]}...")
                self.metrics.record_cache_hit()
                return {"cached": True, "data": cached}
        
        # Prepare parallel tasks
        tasks = []
        task_names = []
        
        # PRIMARY TASK: Qwen comprehensive analysis
        context = await self.context_manager.get_context(session_id)
        tasks.append(self._run_qwen_analysis(text, context, plan["strategy"]))
        task_names.append("qwen")
        
        # PARALLEL TASK: Pronunciation (if voice)
        if "pronunciation" in plan["parallel_tasks"]:
            # TODO: Get audio data from session
            # audio_data = await self._get_audio_data(session_id)
            # tasks.append(self._run_pronunciation_analysis(audio_data, text))
            # task_names.append("pronunciation")
            logger.debug("Pronunciation task skipped (audio not implemented)")
        
        # Execute all parallel tasks
        logger.info(f"Executing {len(tasks)} parallel tasks: {task_names}")
        completed = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Process results
        for i, task_name in enumerate(task_names):
            result = completed[i]
            if isinstance(result, Exception):
                logger.error(f"Task {task_name} failed: {result}")
                self.metrics.record_error(error_type=type(result).__name__, component=task_name)
                results[task_name] = None
            else:
                results[task_name] = result
        
        # CONDITIONAL TASK: Vietnamese explanation
        if "vietnamese_explanation" in plan["conditional_tasks"]:
            qwen_result = results.get("qwen")
            
            # Only run if Qwen confidence < 0.8
            if qwen_result and qwen_result.get("confidence", 1.0) < 0.8:
                logger.info("Running Vietnamese explanation (low confidence)...")
                
                # Load LLaMA3 if not loaded
                if "llama" not in self.loaded_models:
                    await self._load_llama()
                
                if "llama" in self.loaded_models:
                    results["vietnamese"] = await self._run_vietnamese_explanation(
                        text, qwen_result
                    )
        
        return results
    
    async def _run_qwen_analysis(
        self,
        text: str,
        context: Dict[str, Any],
        strategy: str
    ) -> Dict[str, Any]:
        """
        Run Qwen comprehensive analysis.
        
        Timeout: 500ms
        """
        start_time = time.time()
        
        try:
            # TODO: Call actual Qwen engine
            # prompt = self._build_qwen_prompt(text, context, strategy)
            # result = await asyncio.wait_for(
            #     self.qwen_engine.analyze(prompt),
            #     timeout=0.5  # 500ms timeout
            # )
            
            # Placeholder response
            await asyncio.sleep(0.1)  # Simulate processing
            result = {
                "fluency_score": 0.85,
                "vocabulary_level": "B1",
                "grammar": {
                    "errors": [],
                    "corrected": text
                },
                "tutor_response": f"Good job! Your sentence looks great.",
                "confidence": 0.9,
                "strategy_used": strategy
            }
            
            # Record component latency
            latency_ms = (time.time() - start_time) * 1000
            self.metrics.record_component_latency("qwen", latency_ms)
            
            return result
            
        except asyncio.TimeoutError:
            self.metrics.record_error("timeout", "qwen")
            raise TimeoutError("Qwen analysis exceeded 500ms")
    
    async def _run_vietnamese_explanation(
        self,
        text: str,
        qwen_result: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Run LLaMA3-VI for Vietnamese explanation.
        
        Timeout: 500ms
        """
        start_time = time.time()
        
        try:
            # TODO: Call actual LLaMA engine
            # result = await asyncio.wait_for(
            #     self.llama_engine.explain(text, qwen_result),
            #     timeout=0.5
            # )
            
            # Placeholder
            await asyncio.sleep(0.1)
            result = {
                "explanation": "Câu của bạn rất tốt! Tiếp tục cố gắng nhé."
            }
            
            latency_ms = (time.time() - start_time) * 1000
            self.metrics.record_component_latency("llama", latency_ms)
            
            return result
            
        except asyncio.TimeoutError:
            self.metrics.record_error("timeout", "llama")
            logger.warning("Vietnamese explanation timeout")
            return None
    
    # =================================================================
    # PHASE 4: RESULT AGGREGATION
    # =================================================================
    
    async def _aggregate_results(
        self,
        results: Dict[str, Any],
        plan: Dict[str, Any],
        user_input: str
    ) -> Dict[str, Any]:
        """
        Combine all results into final response.
        
        Output format matches API contract.
        """
        
        # Handle cached response
        if results.get("cached"):
            return results["data"]
        
        qwen_result = results.get("qwen", {})
        pronunciation = results.get("pronunciation")
        vietnamese = results.get("vietnamese")
        
        # Base response from Qwen
        response = {
            "text": qwen_result.get("tutor_response", ""),
            "analysis": {
                "fluency": qwen_result.get("fluency_score", 0.0),
                "grammar": qwen_result.get("grammar", {}),
                "vocabulary": qwen_result.get("vocabulary_level", "B1")
            },
            "strategy": plan["strategy"],
            "confidence": qwen_result.get("confidence", 1.0)
        }
        
        # Add pronunciation if available
        if pronunciation:
            response["analysis"]["pronunciation"] = pronunciation
            response["pronunciation_tip"] = self._generate_pronunciation_tip(pronunciation)
        
        # Add Vietnamese hint if available
        if vietnamese:
            response["vietnamese_hint"] = vietnamese.get("explanation", "")
        
        # Calculate overall score
        response["score"] = self._calculate_overall_score(response["analysis"])
        
        # Determine next action
        response["next_action"] = self._determine_next_action(response)
        
        return response
    
    def _calculate_overall_score(self, analysis: Dict[str, Any]) -> Dict[str, float]:
        """Calculate weighted overall score."""
        scores = {}
        
        # Fluency score
        scores["fluency"] = analysis.get("fluency", 0.0)
        
        # Grammar score (1.0 nếu no errors)
        grammar_errors = analysis.get("grammar", {}).get("errors", [])
        scores["grammar"] = max(0.0, 1.0 - len(grammar_errors) * 0.1)
        
        # Vocabulary score (map level to 0-1)
        vocab_level = analysis.get("vocabulary", "B1")
        vocab_mapping = {
            "A1": 0.3, "A2": 0.5, "B1": 0.7,
            "B2": 0.85, "C1": 0.95, "C2": 1.0
        }
        scores["vocabulary"] = vocab_mapping.get(vocab_level, 0.7)
        
        # Pronunciation score (if available)
        if "pronunciation" in analysis:
            scores["pronunciation"] = analysis["pronunciation"].get("accuracy", 0.0)
        
        # Overall weighted average
        weights = {
            "fluency": 0.3,
            "grammar": 0.4,
            "vocabulary": 0.2,
            "pronunciation": 0.1
        }
        
        overall = sum(
            scores.get(k, 0.0) * weights.get(k, 0.0)
            for k in weights
        )
        
        scores["overall"] = round(overall, 2)
        
        return scores
    
    def _determine_next_action(self, response: Dict[str, Any]) -> str:
        """
        Determine next action based on response quality.
        
        Actions:
        - continue_conversation: Good performance (>0.85)
        - provide_hint: Moderate (0.6-0.85)
        - provide_correction: Needs work (<0.6)
        """
        overall_score = response["score"].get("overall", 0.0)
        
        if overall_score >= 0.85:
            return "continue_conversation"
        elif overall_score >= 0.6:
            return "provide_hint"
        else:
            return "provide_correction"
    
    def _generate_pronunciation_tip(self, pronunciation: Dict[str, Any]) -> str:
        """Generate pronunciation tip from errors."""
        errors = pronunciation.get("errors", [])
        
        if not errors:
            return "Great pronunciation!"
        
        # Focus on first error
        first_error = errors[0]
        return f"Focus on the '{first_error.get('phoneme', '')}' sound."
    
    # =================================================================
    # PHASE 5: STATE MANAGEMENT
    # =================================================================
    
    async def _update_state(
        self,
        session_id: str,
        user_id: Optional[str],
        response: Dict[str, Any]
    ):
        """
        Update conversation state and cache results.
        """
        
        # Update conversation history
        await self.context_manager.add_turn(session_id, {
            "role": "assistant",
            "text": response["text"],
            "analysis": response["analysis"],
            "timestamp": datetime.utcnow().isoformat()
        })
        
        # Cache response (if Redis available)
        if self.cache:
            cache_key = self._generate_cache_key(response["text"])
            await self.cache.set(
                f"response:{cache_key}",
                response,
                ttl=7 * 24 * 3600  # 7 days
            )
        
        # Update learner profile with errors (if user_id provided)
        if user_id and self.cache:
            errors = response["analysis"].get("grammar", {}).get("errors", [])
            if errors:
                error_types = [e.get("type", "unknown") for e in errors]
                # TODO: Append to learner error history
                logger.debug(f"Recorded {len(error_types)} errors for user {user_id}")
    
    def _generate_cache_key(self, text: str) -> str:
        """Generate cache key from text."""
        import hashlib
        return hashlib.md5(text.encode()).hexdigest()
    
    # =================================================================
    # ERROR HANDLING
    # =================================================================
    
    async def _handle_error(
        self,
        error: Exception,
        text: str,
        session_id: str,
        processing_time_ms: int
    ) -> Dict[str, Any]:
        """
        Graceful degradation when errors occur.
        
        Fallback hierarchy:
        1. Try cache (similar responses)
        2. Rule-based analysis
        3. Generic error response
        """
        
        logger.error(f"Handling error: {error}")
        
        # Level 1: Try cache fallback
        if self.cache:
            # TODO: Implement similarity search in cache
            # similar = await self.cache.get_similar(text)
            # if similar:
            #     return similar
            pass
        
        
        # Level 2: Rule-based fallback
        try:
            from api.services.fallback import RuleBasedChecker
            
            logger.info("Using rule-based fallback checker")
            checker = RuleBasedChecker()
            analysis_result = checker.check_grammar(text)
            
            # Extract components from analysis
            analysis = {
                "fluency": analysis_result.get("fluency_score", 0.5),
                "grammar": analysis_result.get("grammar", {}),
                "vocabulary": analysis_result.get("vocabulary_level", "B1")
            }
            
            return {
                "text": analysis_result.get("tutor_response", "I see. Let me help you with that."),
                "analysis": analysis,
                "score": self._calculate_overall_score(analysis),
                "next_action": "continue_conversation",
                "strategy": "rule_based_fallback",
                "fallback": True,
                "fallback_type": "rule_based",
                "error": str(error),
                "metadata": {
                    "processing_time_ms": processing_time_ms,
                    "models_used": ["rule_based"],
                    "cached": False,
                    "timestamp": datetime.utcnow().isoformat()
                }
            }
            
        except Exception as fallback_error:
            logger.error(f"Fallback also failed: {fallback_error}")
            
            # Level 3: Generic error response
            return {
                "text": "I'm having trouble analyzing your input right now. Please try again.",
                "analysis": {},
                "score": {"overall": 0.0},
                "next_action": "retry",
                "fallback": True,
                "error": str(error),
                "metadata": {
                    "processing_time_ms": processing_time_ms,
                    "models_used": [],
                    "cached": False,
                    "timestamp": datetime.utcnow().isoformat()
                }
            }
    
    # =================================================================
    # UTILITY METHODS
    # =================================================================
    
    async def get_stats(self) -> Dict[str, Any]:
        """Get orchestrator statistics."""
        metrics = self.metrics.get_stats()
        resource_stats = self.resource_manager.get_usage_stats()
        
        return {
            "orchestrator": {
                "is_initialized": self.is_initialized,
                "loaded_models": list(self.loaded_models),
                "active_sessions": len(self.session_states)
            },
            "performance": metrics,
            "resources": resource_stats
        }
    
    async def health_check(self) -> Dict[str, Any]:
        """Health check for orchestrator."""
        return {
            "status": "healthy" if self.is_initialized else "initializing",
            "models_loaded": list(self.loaded_models),
            "cache_available": self.cache is not None,
            "memory_usage_percent": self.resource_manager.get_usage_percent()
        }


# =================================================================
# SINGLETON
# =================================================================

_orchestrator: Optional[AIOrchestrator] = None


async def get_orchestrator() -> AIOrchestrator:
    """
    Get AIOrchestrator singleton.
    
    Returns:
        Initialized AIOrchestrator instance
    """
    global _orchestrator
    
    if _orchestrator is None:
        _orchestrator = AIOrchestrator()
        await _orchestrator.initialize()
    
    return _orchestrator
