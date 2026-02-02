"""
Model Gateway - Unified Model Management for LexiLingo

This is the CORE MCP tool that manages all AI models:
- Lazy loading: Models only load when first requested
- Auto unload: Free RAM after idle timeout
- Smart routing: Route requests to appropriate models
- Health monitoring: Track model status and memory usage

Architecture:
┌─────────────────────────────────────────────────────────────┐
│                     MODEL GATEWAY                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐        │
│  │   REGISTRY  │   │   LOADER    │   │  SCHEDULER  │        │
│  │  (metadata) │   │(lazy load)  │   │(auto unload)│        │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘        │
│         │                 │                 │               │
│         └─────────────────┼─────────────────┘               │
│                           │                                 │
│                    ┌──────┴──────┐                          │
│                    │   ROUTER    │                          │
│                    │(smart route)│                          │
│                    └──────┬──────┘                          │
│                           │                                 │
│    ┌──────────────────────┼──────────────────────┐          │
│    ▼           ▼          ▼          ▼           ▼          │
│ ┌──────┐  ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐         │
│ │ Qwen │  │Whispr│   │ TTS  │   │HuBERT│   │LLaMA │         │
│ │(chat)│  │(stt) │   │(piper│   │(pron)│   │ (vi) │         │
│ └──────┘  └──────┘   └──────┘   └──────┘   └──────┘         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
"""

import asyncio
import logging
import time
import psutil
from enum import Enum
from typing import Any, Dict, Optional, List, Callable, Awaitable
from dataclasses import dataclass, field
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


class ModelStatus(Enum):
    """Model lifecycle status"""
    UNLOADED = "unloaded"       # Not in memory
    LOADING = "loading"         # Currently loading
    READY = "ready"             # Loaded and ready
    BUSY = "busy"               # Processing request
    ERROR = "error"             # Failed to load/process
    UNLOADING = "unloading"     # Being unloaded


class ModelPriority(Enum):
    """Model priority for memory management"""
    CRITICAL = 1    # Never unload (e.g., main chat model)
    HIGH = 2        # Unload only when memory pressure
    NORMAL = 3      # Unload after idle timeout
    LOW = 4         # Unload immediately after use


@dataclass
class ModelInfo:
    """Model metadata and runtime info"""
    name: str
    model_type: str  # "chat", "stt", "tts", "pronunciation", "embedding"
    description: str
    
    # Loading config
    loader_fn: Optional[Callable[[], Awaitable[Any]]] = None
    unloader_fn: Optional[Callable[[Any], Awaitable[None]]] = None
    
    # Memory & Performance
    estimated_memory_mb: int = 0
    avg_latency_ms: float = 0
    
    # Runtime state
    status: ModelStatus = ModelStatus.UNLOADED
    priority: ModelPriority = ModelPriority.NORMAL
    instance: Any = None
    
    # Usage tracking
    last_used: Optional[datetime] = None
    request_count: int = 0
    total_latency_ms: float = 0
    error_count: int = 0
    
    # Config
    idle_timeout_seconds: int = 300  # 5 minutes default
    preload: bool = False  # Whether to load at startup


class ModelGateway:
    """
    Unified Model Gateway for LexiLingo
    
    Features:
    1. Lazy Loading: Models load on first request
    2. Auto Unload: Free memory after idle timeout
    3. Smart Routing: Route to appropriate model
    4. Health Monitoring: Track status and metrics
    5. Memory Management: Respect memory limits
    
    Usage:
        gateway = ModelGateway()
        gateway.register("qwen", loader_fn, unloader_fn, config)
        
        # Models load automatically when called
        response = await gateway.invoke("qwen", "chat", {"message": "Hello"})
    """
    
    def __init__(
        self,
        max_memory_mb: int = 8000,  # 8GB default
        enable_auto_unload: bool = True,
        health_check_interval: int = 60,
    ):
        self.max_memory_mb = max_memory_mb
        self.enable_auto_unload = enable_auto_unload
        self.health_check_interval = health_check_interval
        
        # Model registry
        self._models: Dict[str, ModelInfo] = {}
        
        # Locks for thread safety
        self._locks: Dict[str, asyncio.Lock] = {}
        
        # Background tasks
        self._unload_task: Optional[asyncio.Task] = None
        self._health_task: Optional[asyncio.Task] = None
        
        # Metrics
        self._started_at = datetime.now()
        self._total_requests = 0
        
        logger.info(f"ModelGateway initialized: max_memory={max_memory_mb}MB")
    
    # ============================================================
    # REGISTRATION
    # ============================================================
    
    def register(
        self,
        name: str,
        model_type: str,
        loader_fn: Callable[[], Awaitable[Any]],
        unloader_fn: Optional[Callable[[Any], Awaitable[None]]] = None,
        description: str = "",
        estimated_memory_mb: int = 0,
        priority: ModelPriority = ModelPriority.NORMAL,
        idle_timeout_seconds: int = 300,
        preload: bool = False,
    ) -> None:
        """
        Register a model with the gateway.
        
        Args:
            name: Unique model identifier
            model_type: Type of model (chat, stt, tts, pronunciation, embedding)
            loader_fn: Async function to load the model
            unloader_fn: Async function to unload (optional)
            description: Human-readable description
            estimated_memory_mb: Expected memory usage
            priority: Unload priority
            idle_timeout_seconds: Time before auto-unload
            preload: Whether to load at startup
        """
        if name in self._models:
            logger.warning(f"Model '{name}' already registered, updating...")
        
        self._models[name] = ModelInfo(
            name=name,
            model_type=model_type,
            description=description,
            loader_fn=loader_fn,
            unloader_fn=unloader_fn,
            estimated_memory_mb=estimated_memory_mb,
            priority=priority,
            idle_timeout_seconds=idle_timeout_seconds,
            preload=preload,
        )
        
        self._locks[name] = asyncio.Lock()
        
        logger.info(f"Registered model: {name} (type={model_type}, mem={estimated_memory_mb}MB)")
    
    # ============================================================
    # CORE: INVOKE (Smart loading + execution)
    # ============================================================
    
    async def invoke(
        self,
        model_name: str,
        method: str,
        params: Dict[str, Any],
        timeout: float = 30.0,
    ) -> Dict[str, Any]:
        """
        Invoke a model method with automatic loading.
        
        This is the main entry point. It will:
        1. Load the model if not loaded
        2. Execute the method
        3. Track metrics
        4. Handle errors gracefully
        
        Args:
            model_name: Name of registered model
            method: Method to call on model instance
            params: Parameters for the method
            timeout: Max execution time
        
        Returns:
            Response from model
        """
        if model_name not in self._models:
            raise ValueError(f"Model '{model_name}' not registered")
        
        model_info = self._models[model_name]
        start_time = time.time()
        
        try:
            # Ensure model is loaded
            await self._ensure_loaded(model_name)
            
            # Update status
            model_info.status = ModelStatus.BUSY
            
            # Get model instance
            instance = model_info.instance
            if instance is None:
                raise RuntimeError(f"Model '{model_name}' instance is None after loading")
            
            # Call method
            if hasattr(instance, method):
                method_fn = getattr(instance, method)
                if asyncio.iscoroutinefunction(method_fn):
                    result = await asyncio.wait_for(method_fn(**params), timeout=timeout)
                else:
                    result = method_fn(**params)
            else:
                raise AttributeError(f"Model '{model_name}' has no method '{method}'")
            
            # Update metrics
            latency_ms = (time.time() - start_time) * 1000
            model_info.last_used = datetime.now()
            model_info.request_count += 1
            model_info.total_latency_ms += latency_ms
            model_info.avg_latency_ms = model_info.total_latency_ms / model_info.request_count
            model_info.status = ModelStatus.READY
            
            self._total_requests += 1
            
            logger.debug(f"Model '{model_name}'.{method}() completed in {latency_ms:.1f}ms")
            
            return {
                "success": True,
                "data": result,
                "latency_ms": latency_ms,
                "model": model_name,
            }
        
        except asyncio.TimeoutError:
            model_info.error_count += 1
            model_info.status = ModelStatus.READY
            logger.error(f"Model '{model_name}'.{method}() timed out after {timeout}s")
            return {
                "success": False,
                "error": f"Timeout after {timeout}s",
                "model": model_name,
            }
        
        except Exception as e:
            model_info.error_count += 1
            model_info.status = ModelStatus.ERROR
            logger.error(f"Model '{model_name}'.{method}() failed: {e}")
            return {
                "success": False,
                "error": str(e),
                "model": model_name,
            }
    
    # ============================================================
    # LOADING & UNLOADING
    # ============================================================
    
    async def _ensure_loaded(self, model_name: str) -> None:
        """Ensure model is loaded (with lock for thread safety)"""
        model_info = self._models[model_name]
        
        if model_info.status == ModelStatus.READY:
            return
        
        async with self._locks[model_name]:
            # Double check after acquiring lock
            if model_info.status == ModelStatus.READY:
                return
            
            await self._load_model(model_name)
    
    async def _load_model(self, model_name: str) -> None:
        """Load a model into memory"""
        model_info = self._models[model_name]
        
        if model_info.loader_fn is None:
            raise RuntimeError(f"No loader function for model '{model_name}'")
        
        # Check memory before loading
        current_memory = self._get_used_memory_mb()
        if current_memory + model_info.estimated_memory_mb > self.max_memory_mb:
            logger.warning(f"Memory pressure detected, freeing space...")
            await self._free_memory(model_info.estimated_memory_mb)
        
        logger.info(f"Loading model: {model_name} (est. {model_info.estimated_memory_mb}MB)...")
        model_info.status = ModelStatus.LOADING
        
        try:
            start_time = time.time()
            model_info.instance = await model_info.loader_fn()
            load_time = time.time() - start_time
            
            model_info.status = ModelStatus.READY
            model_info.last_used = datetime.now()
            
            logger.info(f"Model '{model_name}' loaded in {load_time:.1f}s")
        
        except Exception as e:
            model_info.status = ModelStatus.ERROR
            logger.error(f"Failed to load model '{model_name}': {e}")
            raise
    
    async def unload_model(self, model_name: str) -> bool:
        """Unload a model from memory"""
        if model_name not in self._models:
            return False
        
        model_info = self._models[model_name]
        
        if model_info.status != ModelStatus.READY:
            logger.debug(f"Model '{model_name}' not loaded, skip unload")
            return False
        
        async with self._locks[model_name]:
            logger.info(f"Unloading model: {model_name}...")
            model_info.status = ModelStatus.UNLOADING
            
            try:
                if model_info.unloader_fn and model_info.instance:
                    await model_info.unloader_fn(model_info.instance)
                
                model_info.instance = None
                model_info.status = ModelStatus.UNLOADED
                
                # Force garbage collection
                import gc
                gc.collect()
                
                logger.info(f"Model '{model_name}' unloaded")
                return True
            
            except Exception as e:
                logger.error(f"Error unloading model '{model_name}': {e}")
                model_info.status = ModelStatus.ERROR
                return False
    
    async def _free_memory(self, needed_mb: int) -> None:
        """Free memory by unloading low-priority idle models"""
        # Sort by priority (lowest first) then by last_used (oldest first)
        candidates = [
            m for m in self._models.values()
            if m.status == ModelStatus.READY and m.priority != ModelPriority.CRITICAL
        ]
        candidates.sort(key=lambda m: (m.priority.value, m.last_used or datetime.min))
        
        freed = 0
        for model in candidates:
            if freed >= needed_mb:
                break
            
            if await self.unload_model(model.name):
                freed += model.estimated_memory_mb
                logger.info(f"Freed {model.estimated_memory_mb}MB from '{model.name}'")
    
    # ============================================================
    # AUTO-UNLOAD SCHEDULER
    # ============================================================
    
    async def start(self) -> None:
        """Start the gateway (alias for start_scheduler)"""
        await self.start_scheduler()
    
    async def start_scheduler(self) -> None:
        """Start background scheduler for auto-unload"""
        if not self.enable_auto_unload:
            return
        
        self._unload_task = asyncio.create_task(self._auto_unload_loop())
        logger.info("Auto-unload scheduler started")
    
    async def stop_scheduler(self) -> None:
        """Stop background scheduler"""
        if self._unload_task:
            self._unload_task.cancel()
            try:
                await self._unload_task
            except asyncio.CancelledError:
                pass
        logger.info("Auto-unload scheduler stopped")
    
    async def _auto_unload_loop(self) -> None:
        """Background loop to unload idle models"""
        while True:
            try:
                await asyncio.sleep(60)  # Check every minute
                
                now = datetime.now()
                for model in self._models.values():
                    if model.status != ModelStatus.READY:
                        continue
                    
                    if model.priority == ModelPriority.CRITICAL:
                        continue
                    
                    if model.last_used is None:
                        continue
                    
                    idle_time = (now - model.last_used).total_seconds()
                    if idle_time > model.idle_timeout_seconds:
                        logger.info(
                            f"Model '{model.name}' idle for {idle_time:.0f}s, unloading..."
                        )
                        await self.unload_model(model.name)
            
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Auto-unload error: {e}")
    
    # ============================================================
    # SMART ROUTING
    # ============================================================
    
    def route(self, task_type: str) -> str:
        """
        Route a task to the appropriate model.
        
        Args:
            task_type: Type of task (chat, stt, tts, pronunciation, translate_vi, etc.)
        
        Returns:
            Model name to use
        """
        routing_table = {
            # Chat tasks
            "chat": "qwen",
            "dialogue": "qwen",
            "grammar": "qwen",
            "grammar_check": "qwen",
            "fluency": "qwen",
            "vocabulary": "qwen",
            
            # Voice tasks
            "stt": "whisper",
            "transcribe": "whisper",
            "speech_to_text": "whisper",
            
            "tts": "piper",
            "text_to_speech": "piper",
            "speak": "piper",
            
            # Pronunciation
            "pronunciation": "hubert",
            "phoneme": "hubert",
            "accent": "hubert",
            
            # Vietnamese
            "translate_vi": "llama_vi",
            "explain_vi": "llama_vi",
            "vietnamese": "llama_vi",
            
            # Embeddings
            "embed": "minilm",
            "semantic_search": "minilm",
        }
        
        model_name = routing_table.get(task_type)
        if model_name is None:
            raise ValueError(f"Unknown task type: {task_type}")
        
        if model_name not in self._models:
            raise ValueError(f"Model '{model_name}' not registered for task '{task_type}'")
        
        return model_name
    
    async def execute_task(
        self,
        task_type: str,
        params: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Execute a task with automatic model routing.
        
        This is the highest-level API. It will:
        1. Route to appropriate model
        2. Load model if needed
        3. Execute task
        4. Return result
        
        Args:
            task_type: Type of task
            params: Task parameters
        
        Returns:
            Task result
        """
        model_name = self.route(task_type)
        
        # Map task type to method
        method_map = {
            "chat": "chat",
            "dialogue": "chat",
            "grammar": "analyze_grammar",
            "grammar_check": "check",
            "fluency": "score_fluency",
            "stt": "transcribe",
            "transcribe": "transcribe",
            "tts": "synthesize",
            "speak": "synthesize",
            "pronunciation": "analyze",
            "translate_vi": "translate",
            "explain_vi": "explain",
            "embed": "encode",
        }
        
        method = method_map.get(task_type, "execute")
        
        return await self.invoke(model_name, method, params)
    
    # ============================================================
    # STATUS & METRICS
    # ============================================================
    
    def get_status(self) -> Dict[str, Any]:
        """Get gateway status and all model statuses"""
        models_status = {}
        for name, model in self._models.items():
            models_status[name] = {
                "status": model.status.value,
                "type": model.model_type,
                "memory_mb": model.estimated_memory_mb,
                "priority": model.priority.name,
                "request_count": model.request_count,
                "avg_latency_ms": round(model.avg_latency_ms, 1),
                "error_count": model.error_count,
                "last_used": model.last_used.isoformat() if model.last_used else None,
                "idle_timeout": model.idle_timeout_seconds,
            }
        
        return {
            "gateway": {
                "started_at": self._started_at.isoformat(),
                "uptime_seconds": (datetime.now() - self._started_at).total_seconds(),
                "total_requests": self._total_requests,
                "max_memory_mb": self.max_memory_mb,
                "used_memory_mb": self._get_used_memory_mb(),
                "auto_unload_enabled": self.enable_auto_unload,
            },
            "models": models_status,
            "loaded_models": [
                name for name, m in self._models.items()
                if m.status == ModelStatus.READY
            ],
        }
    
    def _get_used_memory_mb(self) -> int:
        """Get current process memory usage in MB"""
        try:
            process = psutil.Process()
            return int(process.memory_info().rss / 1024 / 1024)
        except Exception:
            return 0
    
    # ============================================================
    # PRELOAD
    # ============================================================
    
    async def preload_models(self) -> None:
        """Load all models marked for preload"""
        for name, model in self._models.items():
            if model.preload:
                logger.info(f"Preloading model: {name}")
                await self._ensure_loaded(name)
    
    # ============================================================
    # CLEANUP
    # ============================================================
    
    async def shutdown(self) -> None:
        """Graceful shutdown - unload all models"""
        logger.info("Shutting down ModelGateway...")
        
        await self.stop_scheduler()
        
        for name in list(self._models.keys()):
            await self.unload_model(name)
        
        logger.info("ModelGateway shutdown complete")


# ============================================================
# SINGLETON INSTANCE
# ============================================================

_gateway_instance: Optional[ModelGateway] = None


def get_model_gateway() -> ModelGateway:
    """Get or create the singleton ModelGateway instance (sync)"""
    global _gateway_instance
    
    if _gateway_instance is None:
        _gateway_instance = ModelGateway()
    
    return _gateway_instance


async def get_gateway() -> ModelGateway:
    """Get or create the singleton ModelGateway instance (async wrapper)"""
    return get_model_gateway()
