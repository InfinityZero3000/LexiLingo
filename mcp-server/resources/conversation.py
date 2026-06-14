"""Conversation History Resource"""

import json
import logging
from urllib.parse import quote

from resources.common import freshness, source, upstream_error
from utils.api_client import UpstreamServiceError, call_ai_service

logger = logging.getLogger(__name__)


async def get(session_id: str) -> str:
    """
    Get conversation history by session ID
    
    Returns JSON with:
    - session_id
    - messages: [{role, content, timestamp}]
    - context_embedding
    """
    logger.info(f"Fetching conversation history: session_id={session_id}")
    safe_session_id = quote(session_id, safe="")

    try:
        try:
            response = await call_ai_service(
                "GET", f"/api/v1/lexi/sessions/{safe_session_id}/messages?full=true"
            )
            entity = "lexi_messages"
        except UpstreamServiceError as exc:
            if exc.status_code != 404:
                raise
            response = await call_ai_service(
                "GET", f"/api/v1/topics/topic-sessions/{safe_session_id}/messages"
            )
            entity = "chat_messages"
        history = {
            "session_id": session_id,
            "messages": response.get("messages", []),
            "context_summary": response.get("context_summary"),
            "source": source("ai-service", "mongodb", entity),
            "freshness": freshness(),
            "error": None,
        }
        return json.dumps(history, ensure_ascii=False)

    except Exception as e:
        logger.error(f"Error fetching conversation history: {e}")
        return json.dumps(
            {
                "session_id": session_id,
                "messages": [],
                "context_summary": None,
                "source": source("ai-service", "mongodb", "conversation"),
                "freshness": freshness("unavailable"),
                "error": upstream_error(e),
            },
            ensure_ascii=False,
        )
