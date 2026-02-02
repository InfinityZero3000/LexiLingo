"""
Chat Tool - Chat with AI tutor (Qwen or Gemini)
"""

import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)

# Global handlers (lazy loaded)
_qwen_handler = None
_gemini_handler = None


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute chat tool
    
    Args:
        message: User message
        context: Conversation context (session_id, user_level, etc.)
        model: "qwen" or "gemini"
    
    Returns:
        response: AI response
        confidence: Confidence score
        suggestions: Learning suggestions
        model_used: Which model was used
    """
    global _qwen_handler, _gemini_handler
    
    message = args.get("message", "")
    context = args.get("context", {})
    model = args.get("model", "qwen")
    
    if not message:
        return {"error": "Message is required"}
    
    logger.info(f"Chat request: model={model}, message_len={len(message)}")
    
    try:
        # Select and load model
        if model == "qwen":
            if _qwen_handler is None:
                logger.info("Loading Qwen handler...")
                from handlers.qwen import QwenHandler
                _qwen_handler = QwenHandler()
                await _qwen_handler.load()
            
            response = await _qwen_handler.chat(
                message=message,
                context=context,
            )
        
        elif model == "gemini":
            if _gemini_handler is None:
                logger.info("Loading Gemini handler...")
                from handlers.gemini import GeminiHandler
                _gemini_handler = GeminiHandler()
            
            response = await _gemini_handler.chat(
                message=message,
                context=context,
            )
        
        else:
            return {"error": f"Unknown model: {model}"}
        
        return {
            "response": response.get("text", ""),
            "confidence": response.get("confidence", 0.95),
            "suggestions": response.get("suggestions", []),
            "model_used": model,
            "context_used": bool(context),
        }
    
    except Exception as e:
        logger.error(f"Chat execution error: {e}", exc_info=True)
        return {
            "error": str(e),
            "model": model,
        }


async def cleanup():
    """Cleanup resources"""
    global _qwen_handler, _gemini_handler
    
    if _qwen_handler:
        await _qwen_handler.unload()
        _qwen_handler = None
    
    if _gemini_handler:
        _gemini_handler = None
    
    logger.info("Chat tool cleaned up")
