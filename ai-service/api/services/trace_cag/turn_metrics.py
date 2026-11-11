"""One small Mongo row per real chat turn, so prod latency and retrieval can be measured without reading text."""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime
from typing import Any

logger = logging.getLogger(__name__)

COLLECTION = "tracecag_turn_metrics"
RETENTION_SECONDS = 90 * 24 * 3600

_index_ready = False
_pending: set[asyncio.Task[None]] = set()


def build_turn_metrics(state: dict[str, Any]) -> dict[str, Any] | None:
    """Numbers and flags only; None for benchmark runs so they never pollute prod stats."""
    if state.get("benchmark_task") or state.get("benchmark_context"):
        return None
    return {
        "ts": datetime.now(UTC),
        "session_id": state.get("session_id"),
        "input_type": state.get("input_type"),
        "path": state.get("path"),
        "cache_hit": bool(state.get("cache_hit")),
        "latency_ms": state.get("latency_ms"),
        "ttft_ms": state.get("ttft_ms"),
        "learner_state_ms": state.get("learner_state_latency_ms"),
        "learner_state_degraded": bool(state.get("learner_state_degraded")),
        "retrieval_policy": state.get("retrieval_policy"),
        "generation_policy": state.get("generation_policy"),
        "kg_seed": len(state.get("kg_seed_concepts") or []),
        "kg_expanded": len(state.get("kg_expanded_nodes") or []),
        "retrieved": len(state.get("retrieval_trace") or []),
        "diagnosis_errors": len(state.get("diagnosis_errors") or []),
        "models": list(state.get("models_used") or []),
        "prompt_tokens": state.get("prompt_tokens"),
        "completion_tokens": state.get("completion_tokens"),
        "cached_tokens": state.get("cached_tokens"),
        "usage_source": state.get("usage_source"),
        "error": bool(state.get("error")),
    }


async def _write(doc: dict[str, Any]) -> None:
    global _index_ready
    try:
        from api.core.database import mongodb_manager

        collection = mongodb_manager.db[COLLECTION]
        if not _index_ready:
            await collection.create_index("ts", expireAfterSeconds=RETENTION_SECONDS)
            _index_ready = True
        await collection.insert_one(doc)
    except Exception as exc:
        logger.warning("turn metrics not recorded: %s", type(exc).__name__)


def record_turn_metrics(state: dict[str, Any]) -> None:
    """Fire and forget: a metrics failure must never cost the learner a reply."""
    doc = build_turn_metrics(state)
    if doc is None:
        return
    try:
        task = asyncio.get_running_loop().create_task(_write(doc))
    except RuntimeError:
        return
    _pending.add(task)
    task.add_done_callback(_pending.discard)
