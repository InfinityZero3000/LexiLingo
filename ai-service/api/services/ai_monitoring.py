"""Admin read models over tracecag_turn_metrics, the Groq key pool and the observation spool."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from api.core.groq_key_pool import GroqKeyPool, resolve_groq_model
from api.services.trace_cag.turn_metrics import COLLECTION

SHADOW_STATS_KEY = "v1:l1_shadow:stats"
SPOOL_COLLECTION = "learner_observation_spool"
_QUEUED = ("pending", "retry", "processing")
_F1_EDGES = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0001]
_LATENCY_FIELDS = ("latency_ms", "ttft_ms", "first_chunk_ms")


@dataclass(frozen=True)
class Window:
    seconds: int
    unit: str
    bin_size: int


WINDOWS = {
    "1h": Window(3600, "minute", 5),
    "24h": Window(86400, "hour", 1),
    "7d": Window(7 * 86400, "day", 1),
}


_TOPIC_CHAT = {"$eq": ["$generation_policy", "skip"]}
_MEASURED = {"$in": ["$usage_source", ["provider", "partial"]]}


def _percentiles(field: str) -> dict[str, Any]:
    # $percentile needs MongoDB 7.0, which docker-compose pins (mongo:7.0).
    # Topic-chat rows time analysis only, so they do not belong in a reply-latency percentile.
    return {"$percentile": {
        "input": {"$cond": [_TOPIC_CHAT, None, f"${field}"]}, "p": [0.5, 0.95], "method": "approximate",
    }}


def _measured(field: str) -> dict[str, Any]:
    return {"$cond": [_MEASURED, f"${field}", None]}


def _count_by(expr: Any, name: str = "turns") -> list[dict[str, Any]]:
    return [{"$group": {"_id": expr, name: {"$sum": 1}}}]


def build_chat_pipeline(since: datetime, window: Window) -> list[dict[str, Any]]:
    latency = {field: _percentiles(field) for field in _LATENCY_FIELDS}
    return [
        {"$match": {"ts": {"$gte": since}}},
        {"$facet": {
            "totals": [{"$group": {
                "_id": None,
                "turns": {"$sum": 1},
                "errors": {"$sum": {"$cond": [{"$eq": ["$error", True]}, 1, 0]}},
                "degraded": {"$sum": {"$cond": [{"$eq": ["$learner_state_degraded", True]}, 1, 0]}},
                "hits": {"$sum": {"$cond": [{"$eq": ["$cache_hit", True]}, 1, 0]}},
                "topic_turns": {"$sum": {"$cond": [_TOPIC_CHAT, 1, 0]}},
                "prompt_sum": {"$sum": _measured("prompt_tokens")},
                "completion_sum": {"$sum": _measured("completion_tokens")},
                "cached_sum": {"$sum": _measured("cached_tokens")},
                "prompt_avg": {"$avg": _measured("prompt_tokens")},
                "completion_avg": {"$avg": _measured("completion_tokens")},
                "cached_avg": {"$avg": _measured("cached_tokens")},
                "usage_turns": {"$sum": {"$cond": [_MEASURED, 1, 0]}},
                "partial_turns": {"$sum": {"$cond": [{"$eq": ["$usage_source", "partial"]}, 1, 0]}},
            }}],
            "latency_all": [{"$group": {"_id": None, **latency}}],
            "latency_by_hit": [{"$group": {"_id": {"$eq": ["$cache_hit", True]}, **latency}}],
            "usage_source": _count_by({"$cond": [
                {"$in": ["$usage_source", ["provider", "partial", "none"]]}, "$usage_source", "not_recorded",
            ]}),
            "layers": _count_by({"$ifNull": ["$cache_layer", "none"]}),
            "bypass": _count_by({"$ifNull": ["$cache_bypass", ""]}),
            "models": [
                {"$project": {"models": {"$setUnion": [{"$ifNull": ["$models", []]}, []]}}},
                {"$unwind": "$models"},
                {"$group": {"_id": "$models", "turns": {"$sum": 1}}},
                {"$sort": {"turns": -1}},
                {"$limit": 10},
            ],
            "series": [
                {"$group": {
                    "_id": {"$dateTrunc": {
                        "date": "$ts", "unit": window.unit, "binSize": window.bin_size,
                    }},
                    "turns": {"$sum": 1},
                    "latency_ms": _percentiles("latency_ms"),
                    "tokens": {"$sum": {"$cond": [
                        _MEASURED,
                        {"$add": [{"$ifNull": ["$prompt_tokens", 0]}, {"$ifNull": ["$completion_tokens", 0]}],
                         },
                        0,
                    ]}},
                }},
                {"$sort": {"_id": 1}},
            ],
            "f1": [
                {"$match": {"l1_shadow_f1": {"$type": "number"}}},
                {"$bucket": {
                    "groupBy": "$l1_shadow_f1", "boundaries": _F1_EDGES,
                    "default": "out", "output": {"count": {"$sum": 1}},
                }},
            ],
        }},
    ]


def _pair(values: Any) -> dict[str, float | None]:
    values = list(values or [None, None])
    return {"p50": values[0], "p95": values[1]}


def _latency(row: dict[str, Any] | None) -> dict[str, dict[str, float | None]]:
    row = row or {}
    return {field: _pair(row.get(field)) for field in _LATENCY_FIELDS}


def _rate(part: float, whole: float) -> float | None:
    return round(part / whole, 4) if whole else None


def _share_map(rows: list[dict[str, Any]], total: int) -> dict[str, dict[str, Any]]:
    return {str(r["_id"]): {"turns": r["turns"], "share": _rate(r["turns"], total)} for r in rows}


def _to_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _utc(value: datetime) -> datetime:
    # Motor hands back naive datetimes that are UTC; a bare ISO string would be read as local time.
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _floor(moment: datetime, window: Window) -> datetime:
    if window.unit == "day":
        return moment.replace(hour=0, minute=0, second=0, microsecond=0)
    if window.unit == "hour":
        return moment.replace(minute=0, second=0, microsecond=0)
    return moment.replace(minute=moment.minute - moment.minute % window.bin_size, second=0, microsecond=0)


def _step(window: Window) -> timedelta:
    return timedelta(**{f"{window.unit}s": window.bin_size})


def _filled_series(rows: list[dict[str, Any]], window: Window, now: datetime) -> list[dict[str, Any]]:
    by_bucket = {_utc(r["_id"]): r for r in rows}
    bucket = _floor(now - timedelta(seconds=window.seconds), window)
    out = []
    while bucket <= now:
        row = by_bucket.get(bucket, {})
        out.append({
            "ts": bucket.isoformat(),
            "turns": row.get("turns", 0),
            "p95_latency_ms": _pair(row.get("latency_ms"))["p95"],
            "tokens": row.get("tokens", 0),
        })
        bucket += _step(window)
    return out


def shape_chat_report(
    raw: dict[str, list[dict[str, Any]]],
    *,
    window: str,
    now: datetime,
    shadow: dict[str, Any] | None,
) -> dict[str, Any]:
    now = _utc(now)
    totals = (raw.get("totals") or [{}])[0]
    turns = totals.get("turns", 0)
    by_hit = {bool(r["_id"]): r for r in raw.get("latency_by_hit") or []}
    prompt_avg, completion_avg = totals.get("prompt_avg"), totals.get("completion_avg")
    per_turn = None if prompt_avg is None and completion_avg is None else (prompt_avg or 0) + (completion_avg or 0)
    compared = _to_int((shadow or {}).get("compared"))
    low = _to_int((shadow or {}).get("low_similarity"))
    edges = _F1_EDGES
    f1 = {r["_id"]: r["count"] for r in raw.get("f1") or [] if r["_id"] != "out"}
    return {
        "window": window,
        "since": (now - timedelta(seconds=WINDOWS[window].seconds)).isoformat(),
        "generated_at": now.isoformat(),
        "turns": turns,
        "topic_turns": totals.get("topic_turns", 0),
        "errors": totals.get("errors", 0),
        "error_rate": _rate(totals.get("errors", 0), turns),
        "latency": {
            "all": _latency((raw.get("latency_all") or [None])[0]),
            "hit": _latency(by_hit.get(True)),
            "miss": _latency(by_hit.get(False)),
        },
        "tokens": {
            "prompt_sum": totals.get("prompt_sum", 0),
            "completion_sum": totals.get("completion_sum", 0),
            "cached_sum": totals.get("cached_sum", 0),
            "prompt_avg": prompt_avg,
            "completion_avg": completion_avg,
            "cached_avg": totals.get("cached_avg"),
            "per_turn": per_turn,
            "reported_turns": totals.get("usage_turns", 0),
            "partial_turns": totals.get("partial_turns", 0),
            "usage_source": _share_map(raw.get("usage_source") or [], turns),
        },
        "cache": {
            "hit_rate": _rate(totals.get("hits", 0), turns),
            "layers": _share_map(raw.get("layers") or [], turns),
            "bypass": _share_map([r for r in raw.get("bypass") or [] if r["_id"]], turns),
            "l1_shadow": {
                "compared": compared,
                "low_similarity": low,
                "low_similarity_rate": _rate(low or 0, compared or 0),
                "f1_distribution": [
                    {"from": edge, "count": f1.get(edge, 0)} for edge in edges[:-1]
                ],
            },
        },
        "learner_state": {
            "degraded": totals.get("degraded", 0),
            "degraded_rate": _rate(totals.get("degraded", 0), turns),
        },
        "models": [{"model": r["_id"], "turns": r["turns"]} for r in raw.get("models") or []],
        "series": _filled_series(raw.get("series") or [], WINDOWS[window], now),
    }


async def _shadow_counters(redis: Any) -> dict[str, Any] | None:
    if redis is None:
        return None
    try:
        raw = await redis.hgetall(SHADOW_STATS_KEY)
    except Exception:
        return None
    return {(k.decode() if isinstance(k, bytes) else k): v for k, v in (raw or {}).items()}


async def chat_report(
    db: Any, redis: Any, window: str, now: datetime | None = None
) -> dict[str, Any]:
    now = now or datetime.now(UTC)
    spec = WINDOWS[window]
    pipeline = build_chat_pipeline(now - timedelta(seconds=spec.seconds), spec)
    docs, shadow = await asyncio.gather(
        db[COLLECTION].aggregate(pipeline).to_list(1), _shadow_counters(redis)
    )
    return shape_chat_report(docs[0] if docs else {}, window=window, now=now, shadow=shadow)


def shape_spool(status_counts: list[dict[str, Any]], counters: dict[str, Any]) -> dict[str, Any]:
    by_status = {str(r["_id"]): r["n"] for r in status_counts}
    return {
        "queue_depth": sum(by_status.get(s, 0) for s in _QUEUED),
        "by_status": by_status,
        "dead": by_status.get("dead", 0),
        "delivered": by_status.get("delivered", 0),
        "receiver_off_since_start": counters.get("learner_state_degraded_total.receiver_off", 0),
        "dead_since_start": counters.get("learner_state_degraded_total.observation_dead", 0),
        "worker_loop_errors_since_start": counters.get("learner_state_degraded_total.worker_loop", 0),
    }


async def spool_report(db: Any, counters: dict[str, Any]) -> dict[str, Any]:
    rows = await db[SPOOL_COLLECTION].aggregate(
        [{"$group": {"_id": "$status", "n": {"$sum": 1}}}]
    ).to_list(20)
    return shape_spool(rows, counters)


async def llm_key_report(pool: GroqKeyPool | None, configured: int = 0) -> dict[str, Any]:
    model = resolve_groq_model("GROQ_MODEL")
    keys = await pool.usage_snapshot() if pool else []
    states = [k["state"] for k in keys]
    return {
        "mode": "pool" if pool else "unpooled",
        "model": model,
        "keys": keys,
        "totals": {
            "keys": len(keys) if pool else configured,
            **{s: states.count(s) for s in ("available", "busy", "cooling", "exhausted")},
        },
    }
