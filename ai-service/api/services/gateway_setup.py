"""
Gateway Setup - Initialize ModelGateway with all handlers

This module registers all AI models with the gateway and provides
the initialization function to be called at startup.
"""

import logging
import os
from typing import Optional

from api.services.model_gateway import ModelGateway, ModelPriority, get_gateway

logger = logging.getLogger(__name__)


async def setup_gateway(
    max_memory_mb: int = 8000,
    enable_auto_unload: bool = True,
    use_gemini_fallback: bool = True,
) -> ModelGateway:
    """
    Initialize and configure the ModelGateway with all handlers.
    
    Args:
        max_memory_mb: Maximum memory for all models
        enable_auto_unload: Whether to auto-unload idle models
        use_gemini_fallback: Use Gemini as cloud fallback
        
    Returns:
        Configured ModelGateway instance
    """
    gateway = await get_gateway()
    
    # Configure gateway settings
    gateway.max_memory_mb = max_memory_mb
    gateway.enable_auto_unload = enable_auto_unload
    
    # Register all models
    await _register_qwen(gateway)
    await _register_whisper(gateway)
    await _register_piper(gateway)
    await _register_hubert(gateway)
    
    if use_gemini_fallback:
        await _register_gemini(gateway)
    
    # Start background tasks
    await gateway.start()
    
    logger.info("✓ ModelGateway setup complete")
    return gateway


async def _register_qwen(gateway: ModelGateway) -> None:
    """Register Qwen model for chat and grammar."""
    from api.services.handlers.qwen_handler import QwenHandler, QwenConfig
    
    handler: Optional[QwenHandler] = None
    
    async def loader():
        nonlocal handler
        config = QwenConfig(
            model_path=os.getenv("QWEN_MODEL_PATH", "models/qwen3-1.7b"),
            model_id=os.getenv("QWEN_MODEL_ID", "Qwen/Qwen2.5-1.5B-Instruct"),
            device=os.getenv("MODEL_DEVICE", "auto"),
        )
        handler = QwenHandler(config)
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
        description="Qwen3-1.7B for chat, grammar analysis, and response generation",
        estimated_memory_mb=3500,
        priority=ModelPriority.CRITICAL,  # Main chat model
        idle_timeout_seconds=600,  # 10 minutes
        preload=False,  # Lazy load
    )
    
    logger.info("Registered: qwen (chat)")


async def _register_whisper(gateway: ModelGateway) -> None:
    """Register Whisper model for STT."""
    from api.services.handlers.whisper_handler import WhisperHandler, WhisperConfig
    
    async def loader():
        config = WhisperConfig(
            model_size=os.getenv("WHISPER_MODEL_SIZE", "base"),
            model_path=os.getenv("WHISPER_MODEL_PATH"),
            device=os.getenv("MODEL_DEVICE", "auto"),
        )
        handler = WhisperHandler(config)
        await handler.load()
        return handler
    
    async def unloader(instance):
        if instance:
            await instance.unload()
    
    gateway.register(
        name="whisper",
        model_type="stt",
        loader_fn=loader,
        unloader_fn=unloader,
        description="Faster-Whisper for speech-to-text",
        estimated_memory_mb=500,
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
            model_path=os.getenv("PIPER_MODEL_PATH", "models/piper/en_US-lessac-medium.onnx"),
            voice=os.getenv("PIPER_VOICE", "en_US-lessac-medium"),
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
