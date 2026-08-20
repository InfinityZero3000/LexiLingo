"""
Gateway Setup - Initialize ModelGateway with all handlers

This module registers all AI models with the gateway and provides
the initialization function to be called at startup.
"""

import logging
import os
from typing import Optional

from api.core.config import settings
from api.services.model_gateway import ModelGateway, ModelPriority, get_gateway

logger = logging.getLogger(__name__)


async def setup_gateway(
    max_memory_mb: int = 8000,
    enable_auto_unload: bool = True,
    use_gemini_fallback: bool = True,
    use_ollama: bool = True,
) -> ModelGateway:
    """
    Initialize and configure the ModelGateway with all handlers.
    
    Args:
        max_memory_mb: Maximum memory for all models
        enable_auto_unload: Whether to auto-unload idle models
        use_gemini_fallback: Use Gemini as cloud fallback
        use_ollama: Register the local Ollama chat model
        
    Returns:
        Configured ModelGateway instance
    """
    gateway = await get_gateway()
    
    # Configure gateway settings
    gateway.max_memory_mb = max_memory_mb
    gateway.enable_auto_unload = enable_auto_unload
    
    # Register all models
    if use_ollama:
        await _register_qwen(gateway)
    else:
        logger.info("Skipped: qwen (OLLAMA_ENABLED is off) — chat runs on Groq")
    await _register_whisper(gateway)
    await _register_piper(gateway)
    await _register_hubert(gateway)
    await _register_minilm(gateway)
    
    if use_gemini_fallback:
        await _register_gemini(gateway)
    
    # Start background tasks
    await gateway.start()
    
    logger.info(" ModelGateway setup complete")
    return gateway


async def _register_qwen(gateway: ModelGateway) -> None:
    """Register Qwen model via Ollama for chat and grammar."""
    from api.services.handlers.ollama_qwen_handler import (
        OllamaQwenConfig,
        OllamaQwenHandler,
    )

    handler: Optional[OllamaQwenHandler] = None
    
    async def loader():
        nonlocal handler
        config = OllamaQwenConfig(
            base_url=settings.OLLAMA_BASE_URL,
            model=os.getenv("OLLAMA_MODEL", "lexilingo-qwen3-1.7b"),
            timeout=float(os.getenv("OLLAMA_TIMEOUT", "120")),
            context_length=int(os.getenv("OLLAMA_CONTEXT_LENGTH", "2048")),
            num_threads=int(os.getenv("OLLAMA_NUM_THREADS", "8")),
            keep_alive=os.getenv("OLLAMA_KEEP_ALIVE", "24h"),
        )
        handler = OllamaQwenHandler(config)
        await handler.load()
        return handler
    
    async def unloader(instance):
        if instance:
            await instance.unload()
    
    gateway.register(
        name="qwen",
        model_type="chat",
        loader_fn=loader,
        unloader_fn=unloader,
        description="Qwen via Ollama for chat, grammar analysis, and response generation",
        estimated_memory_mb=200,
        # CRITICAL priority models are never auto-unloaded regardless of
        # idle_timeout_seconds (see ModelGateway._auto_unload_loop's
        # `if model.priority == ModelPriority.CRITICAL: continue`) — no
        # idle_timeout_seconds is passed here since it would never apply.
        priority=ModelPriority.CRITICAL,  # Main chat model
        preload=True,  # Preload for performance
    )
    
    logger.info("Registered: qwen (chat)")


async def _register_whisper(gateway: ModelGateway) -> None:
    """Register a compatibility façade over the unified STT runtime."""
    from api.services.handlers.whisper_handler import WhisperHandler
    
    async def loader():
        return WhisperHandler()
    
    async def unloader(instance):
        if instance:
            await instance.unload()
    
    gateway.register(
        name="whisper",
        model_type="stt",
        loader_fn=loader,
        unloader_fn=unloader,
        description="Faster-Whisper for speech-to-text",
        estimated_memory_mb=0,
        priority=ModelPriority.NORMAL,
        idle_timeout_seconds=300,  # 5 minutes
        preload=False,
    )
    
    logger.info("Registered: whisper (stt)")


async def _register_piper(gateway: ModelGateway) -> None:
    """Register Piper model for TTS."""
    from api.services.handlers.piper_handler import PiperHandler, PiperConfig
    
    async def loader():
        config = PiperConfig(
            model_path=os.getenv("PIPER_MODEL_PATH", "models/piper/en_US-lessac-low.onnx"),
            voice=os.getenv("PIPER_VOICE", "en_US-lessac-low"),
            sample_rate=int(os.getenv("PIPER_SAMPLE_RATE", "16000")),
        )
        handler = PiperHandler(config)
        await handler.load()
        return handler
    
    async def unloader(instance):
        if instance:
            await instance.unload()
    
    gateway.register(
        name="piper",
        model_type="tts",
        loader_fn=loader,
        unloader_fn=unloader,
        description="Piper TTS for speech synthesis",
        estimated_memory_mb=100,
        priority=ModelPriority.NORMAL,
        idle_timeout_seconds=300,
        preload=False,
    )
    
    logger.info("Registered: piper (tts)")


async def _register_hubert(gateway: ModelGateway) -> None:
    """Register HuBERT model for pronunciation analysis."""
    from api.services.handlers.hubert_handler import HuBERTHandler, HuBERTConfig
    
    async def loader():
        config = HuBERTConfig(
            model_id=os.getenv("HUBERT_MODEL_ID", "facebook/hubert-large-ls960-ft"),
            model_path=os.getenv("HUBERT_MODEL_PATH"),
            device=os.getenv("MODEL_DEVICE", "auto"),
        )
        handler = HuBERTHandler(config)
        await handler.load()
        return handler
    
    async def unloader(instance):
        if instance:
            await instance.unload()
    
    gateway.register(
        name="hubert",
        model_type="pronunciation",
        loader_fn=loader,
        unloader_fn=unloader,
        description="HuBERT for pronunciation analysis",
        estimated_memory_mb=2000,
        priority=ModelPriority.LOW,  # Less frequently used
        idle_timeout_seconds=180,  # 3 minutes
        preload=False,
    )
    
    logger.info("Registered: hubert (pronunciation)")


async def _register_gemini(gateway: ModelGateway) -> None:
    """Register Gemini as cloud fallback."""
    from api.services.handlers.gemini_handler import GeminiHandler, GeminiConfig
    
    async def loader():
        config = GeminiConfig(
            api_key=os.getenv("GEMINI_API_KEY"),
            model=os.getenv("GEMINI_MODEL", "gemini-1.5-flash"),
        )
        handler = GeminiHandler(config)
        await handler.load()
        return handler
    
    async def unloader(instance):
        if instance:
            await instance.unload()
    
    gateway.register(
        name="gemini",
        model_type="chat",
        loader_fn=loader,
        unloader_fn=unloader,
        description="Gemini API as cloud fallback",
        estimated_memory_mb=10,  # Minimal for API client
        priority=ModelPriority.HIGH,  # Keep loaded as fallback
        idle_timeout_seconds=1800,  # 30 minutes
        preload=False,
    )
    
    logger.info("Registered: gemini (chat-fallback)")


async def _register_minilm(gateway: ModelGateway) -> None:
    """Register MiniLM model for sentence embeddings / semantic search."""
    from api.services.handlers.minilm_handler import MiniLMHandler, MiniLMConfig

    async def loader():
        config = MiniLMConfig(
            model_id=os.getenv(
                "MINILM_MODEL_ID", "sentence-transformers/all-MiniLM-L6-v2"
            ),
            model_path=os.getenv("MINILM_MODEL_PATH"),
            device=os.getenv("EMBED_DEVICE", "cpu"),
        )
        handler = MiniLMHandler(config)
        await handler.load()
        return handler

    async def unloader(instance):
        if instance:
            await instance.unload()

    gateway.register(
        name="minilm",
        model_type="embedding",
        loader_fn=loader,
        unloader_fn=unloader,
        description="all-MiniLM-L6-v2 for sentence embeddings and semantic search",
        estimated_memory_mb=25,
        priority=ModelPriority.NORMAL,
        idle_timeout_seconds=600,  # 10 minutes — very lightweight
        preload=False,
    )

    logger.info("Registered: minilm (embedding)")


# Task routing configuration
TASK_ROUTING = {
    # Task type -> Model name
    "chat": "qwen",
    "grammar": "qwen",
    "response": "qwen",
    "fluency": "qwen",
    
    "stt": "whisper",
    "transcribe": "whisper",
    
    "tts": "piper",
    "synthesize": "piper",
    
    "pronunciation": "hubert",
    
    # Embeddings
    "embed": "minilm",
    "semantic_search": "minilm",
    
    # Vietnamese explanations use Gemini for now
    "explain_vi": "gemini",
    "vietnamese": "gemini",
    
    # Fallback
    "default": "gemini",
}


async def execute_task(
    task_type: str,
    params: dict,
    fallback: bool = True,
) -> dict:
    """
    Execute a task using the appropriate model.
    
    This is the high-level interface that routes tasks to models.
    
    Args:
        task_type: Type of task (chat, grammar, stt, tts, etc.)
        params: Task parameters
        fallback: Whether to try fallback on failure
        
    Returns:
        Task result
    """
    gateway = await get_gateway()
    
    # Get primary model for task
    model_name = TASK_ROUTING.get(task_type, TASK_ROUTING["default"])
    
    # Add task type to params for handlers
    params["task"] = task_type
    
    try:
        result = await gateway.invoke(model_name, "invoke", params)
        
        if result.get("success"):
            return result
            
        # Try fallback if primary failed
        if fallback and model_name != "gemini":
            logger.warning(f"Primary model {model_name} failed, trying Gemini fallback")
            params["task"] = task_type
            return await gateway.invoke("gemini", "invoke", params)
            
        return result
        
    except Exception as e:
        if fallback and model_name != "gemini":
            logger.warning(f"Error with {model_name}: {e}, trying Gemini fallback")
            try:
                return await gateway.invoke("gemini", "invoke", params)
            except Exception as e2:
                return {
                    "success": False,
                    "error": f"All models failed: {e}, {e2}",
                }
        return {
            "success": False,
            "error": str(e),
        }


async def shutdown_gateway() -> None:
    """Shutdown the gateway gracefully."""
    gateway = await get_gateway()
    await gateway.shutdown()
    logger.info("ModelGateway shutdown complete")
