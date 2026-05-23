"""
MCP Model Gateway Tool

Unified interface to all AI model handlers in the MCP server.
Routes tasks to the appropriate handler:
- chat/grammar/exercise/concepts → GeminiHandler (direct API)
- stt/transcribe → WhisperHandler (ai-service proxy)
- tts/speak → PiperHandler (ai-service proxy)

Actions: invoke, task, status, list_models, route
"""

import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)

# Lazy-loaded handler instances
_handlers: Dict[str, Any] = {}

# Task-to-handler routing table
TASK_ROUTES = {
    "chat": "gemini",
    "dialogue": "gemini",
    "grammar": "gemini",
    "fluency": "gemini",
    "vocabulary": "gemini",
    "exercise": "gemini",
    "concepts": "gemini",
    "pronunciation": "gemini",
    "stt": "whisper",
    "transcribe": "whisper",
    "tts": "piper",
    "speak": "piper",
}

# Task-to-method mapping
TASK_METHODS = {
    "chat": "chat",
    "dialogue": "chat",
    "grammar": "analyze_grammar",
    "exercise": "generate_exercise",
    "concepts": "expand_concepts",
    "pronunciation": "analyze_pronunciation",
    "stt": "transcribe",
    "transcribe": "transcribe",
    "tts": "synthesize",
    "speak": "synthesize",
}


async def _get_handler(name: str):
    """Get or create a handler by name"""
    if name in _handlers:
        return _handlers[name]

    if name == "gemini":
        from handlers.gemini import GeminiHandler
        _handlers[name] = GeminiHandler()
    elif name == "qwen":
        from handlers.qwen import QwenHandler
        handler = QwenHandler()
        await handler.load()
        _handlers[name] = handler
    elif name == "whisper":
        from handlers.whisper import WhisperHandler
        handler = WhisperHandler()
        await handler.load()
        _handlers[name] = handler
    elif name == "piper":
        from handlers.piper import PiperHandler
        handler = PiperHandler()
        await handler.load()
        _handlers[name] = handler
    else:
        raise ValueError(f"Unknown handler: {name}")

    return _handlers[name]


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute model gateway operations.

    Args:
        action: One of 'invoke', 'task', 'status', 'list_models', 'route'

        For 'invoke':
            model: Handler name (gemini, qwen, whisper, piper)
            method: Method to call on handler
            params: Method parameters

        For 'task' (smart routing):
            task_type: Type of task (chat, stt, tts, grammar, exercise, etc.)
            params: Task parameters

        For 'status':
            (no extra params)

        For 'list_models':
            (no extra params)

        For 'route':
            task_type: Task type to get handler name for
    """
    action = args.get("action", "task")

    try:
        if action == "invoke":
            return await _handle_invoke(args)
        elif action == "task":
            return await _handle_task(args)
        elif action == "status":
            return _handle_status()
        elif action == "list_models":
            return _handle_list_models()
        elif action == "route":
            return _handle_route(args)
        else:
            return {
                "error": f"Unknown action: {action}",
                "valid_actions": [
                    "invoke", "task", "status", "list_models", "route"
                ],
            }
    except Exception as e:
        logger.error(f"Model gateway error: {e}", exc_info=True)
        return {"error": str(e)}


async def _handle_invoke(args: Dict[str, Any]) -> Dict[str, Any]:
    """Direct handler invocation"""
    model = args.get("model")
    method = args.get("method")
    params = args.get("params", {})

    if not model:
        return {"error": "model is required for invoke action"}
    if not method:
        return {"error": "method is required for invoke action"}

    handler = await _get_handler(model)

    if not hasattr(handler, method):
        return {"error": f"Handler '{model}' has no method '{method}'"}

    fn = getattr(handler, method)
    result = await fn(**params) if params else await fn()
    return {"success": True, "data": result, "model": model, "method": method}


async def _handle_task(args: Dict[str, Any]) -> Dict[str, Any]:
    """Smart-routed task execution"""
    task_type = args.get("task_type")
    params = args.get("params", {})

    if not task_type:
        return {"error": "task_type is required for task action"}

    handler_name = TASK_ROUTES.get(task_type)
    if not handler_name:
        return {
            "error": f"No handler for task type: {task_type}",
            "valid_tasks": list(TASK_ROUTES.keys()),
        }

    method_name = TASK_METHODS.get(task_type, "chat")
    handler = await _get_handler(handler_name)

    if not hasattr(handler, method_name):
        return {
            "error": f"Handler '{handler_name}' has no method '{method_name}'"
        }

    fn = getattr(handler, method_name)
    result = await fn(**params)
    return {
        "success": True,
        "data": result,
        "handler": handler_name,
        "task_type": task_type,
    }


def _handle_status() -> Dict[str, Any]:
    """Get status of loaded handlers"""
    status = {}
    for name, handler in _handlers.items():
        loaded = getattr(handler, "loaded", getattr(handler, "_initialized", False))
        status[name] = {
            "loaded": loaded,
            "type": type(handler).__name__,
        }
    return {"success": True, "handlers": status, "loaded_count": len(_handlers)}


def _handle_list_models() -> Dict[str, Any]:
    """List available models/handlers"""
    models = [
        {
            "name": "gemini",
            "type": "GeminiHandler",
            "backend": "Google Gemini API (direct)",
            "tasks": ["chat", "grammar", "exercise", "concepts", "pronunciation"],
        },
        {
            "name": "qwen",
            "type": "QwenHandler",
            "backend": "ai-service proxy (localhost:8001)",
            "tasks": ["chat", "dialogue"],
        },
        {
            "name": "whisper",
            "type": "WhisperHandler",
            "backend": "ai-service proxy (localhost:8001)",
            "tasks": ["stt", "transcribe"],
        },
        {
            "name": "piper",
            "type": "PiperHandler",
            "backend": "ai-service proxy (localhost:8001)",
            "tasks": ["tts", "speak"],
        },
    ]
    return {"success": True, "models": models}


def _handle_route(args: Dict[str, Any]) -> Dict[str, Any]:
    """Get handler name for a task type without invoking"""
    task_type = args.get("task_type")
    if not task_type:
        return {"error": "task_type is required for route action"}

    handler_name = TASK_ROUTES.get(task_type)
    if handler_name:
        return {"success": True, "model": handler_name, "task_type": task_type}
    return {
        "error": f"No handler for task type: {task_type}",
        "valid_tasks": list(TASK_ROUTES.keys()),
    }


# ============================================================
# MCP TOOL DEFINITION (for server.py registration)
# ============================================================

TOOL_DEFINITION = {
    "name": "model_gateway",
    "description": (
        "Unified AI Model Gateway for LexiLingo. "
        "Routes tasks to Gemini (chat/grammar/exercise), "
        "Whisper (STT via ai-service), or Piper (TTS via ai-service). "
        "Actions: invoke, task, status, list_models, route."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["invoke", "task", "status", "list_models", "route"],
                "description": "Action to perform",
                "default": "task",
            },
            "task_type": {
                "type": "string",
                "description": "For 'task'/'route': chat, stt, tts, grammar, exercise, concepts, pronunciation",
            },
            "model": {
                "type": "string",
                "description": "For 'invoke': handler name (gemini, qwen, whisper, piper)",
            },
            "method": {
                "type": "string",
                "description": "For 'invoke': method to call on handler",
            },
            "params": {
                "type": "object",
                "description": "Parameters for task or method",
            },
        },
        "required": [],
    },
}
