"""Topic Chat Service — extracted business logic from send_topic_message route."""

import asyncio
import logging
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from motor.motor_asyncio import AsyncIOMotorDatabase

from api.services.subgraph_hot_cache import get_subgraph
import os


def _env_float(name: str, default: float, minimum: float = 0.0) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return max(minimum, float(raw))
    except ValueError:
        return default

logger = logging.getLogger(__name__)

SAFE_FIXED_RESPONSE = (
    "I'm sorry, I can't respond right now. "
    "Please try again shortly."
)

_PRIMARY_TIMEOUT = _env_float("TOPIC_TRACECAG_TIMEOUT_SEC", 12.0)
_RETRY_TIMEOUT = _env_float("TOPIC_TRACECAG_RETRY_TIMEOUT_SEC", 6.0)


async def resolve_kg_seeds(
    session: dict[str, Any],
    redis_client: Any,
) -> list[str]:
    """Load KG seed concepts from session doc, fallback to subgraph cache."""
    kg_seeds: list[str] = list(session.get("kg_seed_concepts") or [])
    if not kg_seeds:
        try:
            subgraph = await get_subgraph(session.get("story_id", ""), redis_client)
            if subgraph:
                kg_seeds = subgraph.get("seed_concepts", [])
        except Exception as exc:
            logger.debug("[topic_chat_service] ignored subgraph fallback error: %s", exc)
    return kg_seeds


@dataclass
class TracecagResult:
    ai_response: str
    llm_metadata: dict[str, Any]


async def call_tracecag_with_retry(
    message: str,
    session_id: str,
    user_id: str,
    difficulty_level: str,
    conversation_history: list[dict[str, Any]],
    kg_seeds: list[str],
    preferred_llm: str,
    primary_timeout: float = _PRIMARY_TIMEOUT,
    retry_timeout: float = _RETRY_TIMEOUT,
) -> TracecagResult:
    """Primary TraceCAG call -> degraded retry -> SAFE_FIXED_RESPONSE fallback."""
    from api.services.orchestrator import get_orchestrator

    try:
        graph_start = time.time()
        orchestrator = await get_orchestrator()
        graph_result = await asyncio.wait_for(
            orchestrator.process(
                user_input=message,
                session_id=session_id,
                user_id=user_id,
                learner_profile={"level": difficulty_level},
                conversation_history=conversation_history[-6:],
                retrieval_policy="rapid",
                diagnosis_policy="rules",
                generation_policy="auto",
                kg_seed_concepts=kg_seeds or None,
            ),
            timeout=primary_timeout,
        )
        ai_response = str(graph_result.get("tutor_response") or "").strip()
        if not ai_response:
            raise RuntimeError("TraceCAG returned empty tutor_response")
        graph_metadata = graph_result.get("metadata", {}) or {}
        llm_metadata = {
            "provider": "trace-cag",
            "model": ", ".join(graph_metadata.get("models_used") or ["trace-cag_pipeline"]),
            "latency_ms": int((time.time() - graph_start) * 1000),
            "fallback_used": preferred_llm != "trace-cag",
        }
        logger.info("Topic chat response via TraceCAG")
        return TracecagResult(ai_response=ai_response, llm_metadata=llm_metadata)

    except Exception as graph_err:
        logger.error("TraceCAG failed for topic chat (primary): %s", graph_err)

    try:
        retry_start = time.time()
        orchestrator = await get_orchestrator()
        retry_result = await asyncio.wait_for(
            orchestrator.process(
                user_input=message,
                session_id=session_id,
                user_id=user_id,
                learner_profile={"level": difficulty_level},
                conversation_history=[],
                cache_policy="off",
                retrieval_policy="rapid",
                diagnosis_policy="rules",
                generation_policy="auto",
            ),
            timeout=retry_timeout,
        )
        ai_response = str(retry_result.get("tutor_response") or "").strip()
        if not ai_response:
            raise RuntimeError("TraceCAG degraded retry returned empty tutor_response")
        retry_meta = retry_result.get("metadata", {}) or {}
        llm_metadata = {
            "provider": "trace-cag",
            "model": ", ".join(retry_meta.get("models_used") or ["trace-cag_retry"]),
            "latency_ms": int((time.time() - retry_start) * 1000),
            "fallback_used": True,
            "retry_mode": "trace-cag_degraded",
        }
        return TracecagResult(ai_response=ai_response, llm_metadata=llm_metadata)

    except Exception as retry_err:
        logger.error("TraceCAG failed for topic chat (degraded retry): %s", retry_err)
        return TracecagResult(
            ai_response=SAFE_FIXED_RESPONSE,
            llm_metadata={
                "provider": "trace-cag_safe_response",
                "model": "safe_fixed_response",
                "latency_ms": 0,
                "fallback_used": True,
            },
        )


async def persist_topic_turn(
    session_id: str,
    user_id: str,
    message: str,
    ai_response: str,
    db: AsyncIOMotorDatabase,
) -> str:
    """Insert user + AI messages, update session message_count. Returns ai_message_id."""
    now = datetime.now(timezone.utc)

    user_message = {
        "message_id": str(uuid.uuid4()),
        "session_id": session_id,
        "user_id": user_id,
        "content": message,
        "role": "user",
        "timestamp": now,
    }
    ai_message_id = str(uuid.uuid4())
    ai_message_doc = {
        "message_id": ai_message_id,
        "session_id": session_id,
        "content": ai_response,
        "role": "assistant",
        "timestamp": now,
    }
    await db["chat_messages"].insert_many([user_message, ai_message_doc])

    await db["chat_sessions"].update_one(
        {"session_id": session_id},
        {
            "$set": {"last_activity": now},
            "$inc": {"message_count": 2},
        },
    )

    return ai_message_id
