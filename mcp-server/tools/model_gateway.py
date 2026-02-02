"""
MCP Model Gateway Tool

This is THE CORE MCP tool for LexiLingo that provides:
1. Unified interface to all AI models
2. Automatic lazy loading
3. Smart routing based on task type
4. Memory management

Usage in MCP:
    - Tool: model_gateway
    - Actions: invoke, status, preload, unload
"""

import logging
import json
from typing import Any, Dict

logger = logging.getLogger(__name__)

# Import gateway (will be initialized lazily)
_gateway = None


async def get_gateway():
    """Get or initialize the model gateway"""
    global _gateway
    
    if _gateway is None:
        from api.services.model_gateway import initialize_gateway
        _gateway = await initialize_gateway()
    
    return _gateway


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute model gateway operations.
    
    This is the main MCP tool entry point for AI model operations.
    
    Args:
        action: One of "invoke", "task", "status", "preload", "unload"
        
        For "invoke":
            model: Model name (qwen, whisper, piper, hubert)
            method: Method to call
            params: Method parameters
        
        For "task" (smart routing):
            task_type: Type of task (chat, stt, tts, pronunciation, grammar, etc.)
            params: Task parameters
        
        For "preload":
            models: List of model names to preload (optional, all if empty)
        
        For "unload":
            model: Model name to unload
    
    Returns:
        Result of the operation
    
    Examples:
        # Chat with Qwen (auto-loads if needed)
        {"action": "task", "task_type": "chat", "params": {"message": "Hello"}}
        
        # Transcribe audio (auto-loads Whisper)
        {"action": "task", "task_type": "stt", "params": {"audio_bytes": "..."}}
        
        # Direct model invoke
        {"action": "invoke", "model": "qwen", "method": "chat", "params": {...}}
        
        # Get status
        {"action": "status"}
        
        # Unload model to free memory
        {"action": "unload", "model": "hubert"}
    """
    action = args.get("action", "task")
    
    try:
        gateway = await get_gateway()
        
        if action == "invoke":
            # Direct model invocation
            model = args.get("model")
            method = args.get("method")
            params = args.get("params", {})
            
            if not model:
                return {"error": "model is required for invoke action"}
            if not method:
                return {"error": "method is required for invoke action"}
            
            result = await gateway.invoke(model, method, params)
            return result
        
        elif action == "task":
            # Smart routing based on task type
            task_type = args.get("task_type")
            params = args.get("params", {})
            
            if not task_type:
                return {"error": "task_type is required for task action"}
            
            result = await gateway.execute_task(task_type, params)
            return result
        
        elif action == "status":
            # Get gateway and models status
            status = gateway.get_status()
            return {"success": True, "data": status}
        
        elif action == "preload":
            # Preload specific models or all marked for preload
            models = args.get("models", [])
            
            if models:
                for model_name in models:
                    await gateway._ensure_loaded(model_name)
            else:
                await gateway.preload_models()
            
            return {
                "success": True,
                "message": f"Preloaded models: {models or 'all marked'}"
            }
        
        elif action == "unload":
            # Unload a specific model
            model = args.get("model")
            
            if not model:
                return {"error": "model is required for unload action"}
            
            success = await gateway.unload_model(model)
            return {
                "success": success,
                "message": f"Model '{model}' unloaded" if success else f"Failed to unload '{model}'"
            }
        
        elif action == "list_models":
            # List all registered models
            status = gateway.get_status()
            models = []
            for name, info in status["models"].items():
                models.append({
                    "name": name,
                    "type": info["type"],
                    "status": info["status"],
                    "memory_mb": info["memory_mb"],
                })
            return {"success": True, "models": models}
        
        elif action == "route":
            # Get model for a task type (without invoking)
            task_type = args.get("task_type")
            if not task_type:
                return {"error": "task_type is required for route action"}
            
            try:
                model_name = gateway.route(task_type)
                return {"success": True, "model": model_name, "task_type": task_type}
            except ValueError as e:
                return {"error": str(e)}
        
        else:
            return {
                "error": f"Unknown action: {action}",
                "valid_actions": ["invoke", "task", "status", "preload", "unload", "list_models", "route"]
            }
    
    except Exception as e:
        logger.error(f"Model gateway error: {e}", exc_info=True)
        return {"error": str(e)}


# ============================================================
# MCP TOOL DEFINITION (for server.py registration)
# ============================================================

TOOL_DEFINITION = {
    "name": "model_gateway",
    "description": """
Unified AI Model Gateway for LexiLingo.

This tool manages all AI models with:
- Lazy loading: Models only load when needed
- Auto unload: Free memory after idle timeout  
- Smart routing: Auto-select model based on task

Supported task types:
- chat, dialogue, grammar, fluency, vocabulary → Qwen
- stt, transcribe → Whisper
- tts, speak → Piper
- pronunciation, phoneme → HuBERT
- translate_vi, explain_vi → LLaMA-VI

Memory is automatically managed. Heavy models (HuBERT) unload quickly.
""",
    "inputSchema": {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["invoke", "task", "status", "preload", "unload", "list_models", "route"],
                "description": "Action to perform",
                "default": "task",
            },
            "task_type": {
                "type": "string",
                "description": "For 'task' action: chat, stt, tts, pronunciation, grammar, etc.",
            },
            "model": {
                "type": "string",
                "description": "For 'invoke'/'unload': model name (qwen, whisper, piper, hubert)",
            },
            "method": {
                "type": "string",
                "description": "For 'invoke': method to call on model",
            },
            "params": {
                "type": "object",
                "description": "Parameters for task or method",
            },
            "models": {
                "type": "array",
                "items": {"type": "string"},
                "description": "For 'preload': list of model names",
            },
        },
        "required": [],
    },
}
