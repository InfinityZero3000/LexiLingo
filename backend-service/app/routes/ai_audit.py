"""AI audit ingestion routes.

These endpoints allow ai-service to push interaction audit events to backend-service.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, status

from app.core.config import settings
from app.core.dependencies import get_current_admin, get_current_user
from app.core.redis import get_redis
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ai-audit", tags=["AI Audit"])


def _decode_audit_row(row: Any) -> dict[str, Any] | None:
    try:
        if isinstance(row, bytes):
            row = row.decode("utf-8")
        payload = json.loads(row)
        return payload if isinstance(payload, dict) else None
    except Exception:
        return None


def _audit_latency_ms(event: dict[str, Any]) -> float | None:
    for key in ("latency_ms", "duration_ms", "elapsed_ms", "response_time_ms"):
        value = event.get(key)
        if isinstance(value, (int, float)):
            return float(value)
    metadata = event.get("metadata")
    if isinstance(metadata, dict):
        for key in ("latency_ms", "duration_ms", "elapsed_ms"):
            value = metadata.get(key)
            if isinstance(value, (int, float)):
                return float(value)
    return None


def _audit_pipeline_steps(event: dict[str, Any]) -> list[str]:
    steps = event.get("pipeline_steps")
    metadata = event.get("metadata")
    if steps is None and isinstance(metadata, dict):
        steps = metadata.get("pipeline_steps")
    if isinstance(steps, list):
        return [str(step).lower() for step in steps]
    return []


def _audit_failed(event: dict[str, Any]) -> bool:
    status_value = str(event.get("status") or "").lower()
    if status_value in {"success", "ok", "completed", "ready"}:
        return False
    if status_value:
        return True
    return any(step.endswith("_failed") or "error" in step for step in _audit_pipeline_steps(event))


def _component_failed(event: dict[str, Any], component: str) -> bool:
    endpoint = str(event.get("endpoint") or "").lower()
    steps = _audit_pipeline_steps(event)
    return (
        component in endpoint and _audit_failed(event)
    ) or any(component in step and ("failed" in step or "error" in step) for step in steps)


def _event_score(event: dict[str, Any]) -> float | None:
    for key in ("correction_score", "quality_score", "score"):
        value = event.get(key)
        if isinstance(value, (int, float)):
            return float(value)
    metadata = event.get("metadata")
    if isinstance(metadata, dict):
        for key in ("correction_score", "quality_score", "score"):
            value = metadata.get(key)
            if isinstance(value, (int, float)):
                return float(value)
    return None


def _avg(values: list[float]) -> float:
    return round(sum(values) / len(values), 2) if values else 0.0


def _p95(values: list[float]) -> float:
    if not values:
        return 0.0
    sorted_values = sorted(values)
    index = min(len(sorted_values) - 1, int(round((len(sorted_values) - 1) * 0.95)))
    return round(sorted_values[index], 2)


def _summarize_ai_audit_events(events: list[dict[str, Any]]) -> dict[str, Any]:
    latencies = [value for event in events if (value := _audit_latency_ms(event)) is not None]
    failures = [event for event in events if _audit_failed(event)]
    correction_events = [
        event for event in events
        if "correction" in str(event.get("endpoint") or "").lower() or _event_score(event) is not None
    ]
    correction_scores = [
        score for event in correction_events if (score := _event_score(event)) is not None
    ]

    endpoint_stats: dict[str, dict[str, Any]] = {}
    for event in events:
        endpoint = str(event.get("endpoint") or "unknown")
        stats = endpoint_stats.setdefault(
            endpoint,
            {"endpoint": endpoint, "total": 0, "failures": 0, "latencies": []},
        )
        stats["total"] += 1
        if _audit_failed(event):
            stats["failures"] += 1
        latency = _audit_latency_ms(event)
        if latency is not None:
            stats["latencies"].append(latency)

    endpoint_breakdown = []
    for stats in endpoint_stats.values():
        endpoint_breakdown.append({
            "endpoint": stats["endpoint"],
            "total": stats["total"],
            "failures": stats["failures"],
            "average_latency_ms": _avg(stats["latencies"]),
        })
    endpoint_breakdown.sort(key=lambda item: item["total"], reverse=True)

    latest_failures = []
    for event in failures[:10]:
        latest_failures.append({
            "request_id": event.get("request_id"),
            "user_id": event.get("user_id"),
            "endpoint": event.get("endpoint"),
            "status": event.get("status"),
            "latency_ms": _audit_latency_ms(event),
            "received_at": event.get("received_at") or event.get("timestamp"),
            "error": event.get("error") or event.get("error_message") or event.get("message"),
        })

    total = len(events)
    success_count = total - len(failures)
    lexi_events = [
        event for event in events
        if "lexi" in str(event.get("endpoint") or "").lower()
        or "chat" in str(event.get("endpoint") or "").lower()
    ]
    lexi_latencies = [
        value for event in lexi_events if (value := _audit_latency_ms(event)) is not None
    ]

    return {
        "total_events": total,
        "success_count": success_count,
        "failure_count": len(failures),
        "success_rate": round((success_count / total) * 100, 2) if total else 0.0,
        "average_latency_ms": _avg(latencies),
        "p95_latency_ms": _p95(latencies),
        "lexi": {
            "events": len(lexi_events),
            "failures": sum(1 for event in lexi_events if _audit_failed(event)),
            "average_latency_ms": _avg(lexi_latencies),
        },
        "stt": {
            "failures": sum(1 for event in events if _component_failed(event, "stt")),
        },
        "tts": {
            "failures": sum(1 for event in events if _component_failed(event, "tts")),
        },
        "correction": {
            "events": len(correction_events),
            "failures": sum(1 for event in correction_events if _audit_failed(event)),
            "average_score": _avg(correction_scores),
        },
        "endpoint_breakdown": endpoint_breakdown[:20],
        "latest_failures": latest_failures,
    }


def _check_ingest_secret(x_ai_service_secret: str | None) -> None:
    expected = settings.AI_AUDIT_INGEST_SECRET
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI audit ingest secret is not configured",
        )
    if not x_ai_service_secret or x_ai_service_secret != expected:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid AI service ingest secret",
        )


@router.post("/events")
async def ingest_ai_audit_event(
    payload: dict[str, Any],
    x_ai_service_secret: str | None = Header(default=None, alias="X-AI-Service-Secret"),
):
    """Ingest a single AI audit event from ai-service."""
    _check_ingest_secret(x_ai_service_secret)

    user_id = str(payload.get("user_id") or "unknown")
    event = {
        **payload,
        "received_at": datetime.now(timezone.utc).isoformat(),
    }

    redis_client = await get_redis()
    if redis_client is not None:
        key_user = f"ai:audit:user:{user_id}"
        key_global = "ai:audit:all"
        packed = json.dumps(event, ensure_ascii=True)
        # Keep a capped rolling history to avoid unbounded memory growth.
        await redis_client.lpush(key_user, packed)
        await redis_client.ltrim(key_user, 0, 299)
        await redis_client.expire(key_user, 14 * 24 * 3600)

        await redis_client.lpush(key_global, packed)
        await redis_client.ltrim(key_global, 0, 2999)
        await redis_client.expire(key_global, 14 * 24 * 3600)

    logger.info(
        "AI audit event ingested user_id=%s endpoint=%s status=%s request_id=%s",
        user_id,
        event.get("endpoint"),
        event.get("status"),
        event.get("request_id"),
    )

    return {"success": True}


@router.get("/events/me")
async def list_my_ai_audit_events(
    limit: int = 50,
    current_user: User = Depends(get_current_user),
):
    """Get latest AI audit events for the current authenticated user."""
    safe_limit = min(max(limit, 1), 200)

    redis_client = await get_redis()
    if redis_client is None:
        return {"events": [], "total": 0}

    key_user = f"ai:audit:user:{str(current_user.id)}"
    rows = await redis_client.lrange(key_user, 0, safe_limit - 1)

    events: list[dict[str, Any]] = []
    for row in rows:
        try:
            events.append(json.loads(row))
        except Exception:
            continue

    return {"events": events, "total": len(events)}


@router.get("/quality-summary")
async def get_ai_quality_summary(
    limit: int = 500,
    admin_user: User = Depends(get_current_admin),
):
    """Get admin AI quality metrics from the rolling ai-audit event log."""
    safe_limit = min(max(limit, 1), 2000)

    redis_client = await get_redis()
    if redis_client is None:
        return {
            "events": [],
            "summary": _summarize_ai_audit_events([]),
            "total": 0,
            "source": "redis_unavailable",
        }

    rows = await redis_client.lrange("ai:audit:all", 0, safe_limit - 1)
    events = [
        event for row in rows
        if (event := _decode_audit_row(row)) is not None
    ]

    return {
        "events": events[:50],
        "summary": _summarize_ai_audit_events(events),
        "total": len(events),
        "source": "ai:audit:all",
    }
