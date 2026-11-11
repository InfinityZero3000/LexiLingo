"""Read-only measurement of TRACE-CAG data in Mongo (chat, spool, reconcile).

Usage:  python measure_tracecag_prod.py [kg_dir]    # MONGODB_URI / MONGODB_DATABASE from env
"""
import collections
import glob
import json
import os
import statistics
import sys
from typing import Any

from pymongo import MongoClient

KG_DIR = sys.argv[1] if len(sys.argv) > 1 else "data/kg"


def pct(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return round(ordered[min(len(ordered) - 1, int(q * len(ordered)))], 3)


def dist(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"n": 0}
    return {"n": len(values), "mean": round(statistics.mean(values), 2), "p50": pct(values, 0.5), "p95": pct(values, 0.95), "max": max(values)}


def group(col: Any, key: str) -> dict[str, int]:
    rows = col.aggregate([{"$group": {"_id": f"${key}", "n": {"$sum": 1}}}, {"$sort": {"n": -1}}])
    return {str(r["_id"]): r["n"] for r in rows}


def kg_ids() -> set[str]:
    ids: set[str] = set()
    for path in glob.glob(os.path.join(KG_DIR, "*.json")):
        try:
            data = json.load(open(path))
        except (OSError, ValueError):
            continue
        for c in data.get("concepts", []) if isinstance(data, dict) else []:
            if isinstance(c, dict) and c.get("id"):
                ids.add(c["id"])
    return ids


def chat(db: Any) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for name in ("lexi_messages", "chat_messages"):
        col = db[name]
        by_role = group(col, "role")
        months: collections.Counter[str] = collections.Counter()
        per_session: collections.Counter[str] = collections.Counter()
        length = {"user": [], "assistant": []}
        for d in col.find({}, {"role": 1, "content": 1, "timestamp": 1, "session_id": 1}):
            months[str(d.get("timestamp"))[:7]] += 1
            per_session[d.get("session_id")] += 1
            if d.get("role") in length:
                length[d["role"]].append(len(d.get("content") or ""))
        out[name] = {
            "total": col.estimated_document_count(),
            "by_role": by_role,
            "by_month": dict(sorted(months.items())),
            "sessions": len(per_session),
            "msgs_per_session": dist(list(per_session.values())),
            "chars_user": dist(length["user"]),
            "chars_assistant": dist(length["assistant"]),
        }
    return out


def spool(db: Any, known: set[str]) -> dict[str, Any]:
    col = db["learner_observation_spool"]
    rows = list(col.find({}, {"concept_id": 1, "outcome": 1, "confidence": 1, "turn_id": 1, "user_id": 1, "attempt_count": 1, "created_at": 1, "payload": 1}))
    n = len(rows)
    per_turn: collections.Counter[str] = collections.Counter(r.get("turn_id") for r in rows)
    per_user: collections.Counter[str] = collections.Counter(r.get("user_id") for r in rows)
    concepts: collections.Counter[str] = collections.Counter(r.get("concept_id") for r in rows)
    prefix: dict[str, list[int]] = collections.defaultdict(lambda: [0, 0])
    for r in rows:
        cid = str(r.get("concept_id") or "")
        head = cid.split(":", 1)[-1].split(".", 1)[0] if cid.startswith("concept:") else cid.split(":", 1)[0]
        prefix[head][0] += 1
        prefix[head][1] += r.get("outcome") == "incorrect"
    inside = sum(1 for c in concepts if c in known)
    dates = [r["created_at"] for r in rows if r.get("created_at")]
    return {
        "events": n,
        "by_status": group(col, "status"),
        "by_error_code": group(col, "last_error_code"),
        "by_outcome": group(col, "outcome"),
        "incorrect_rate": round(sum(r.get("outcome") == "incorrect" for r in rows) / n, 3) if n else None,
        "confidence": dist([r["confidence"] for r in rows if isinstance(r.get("confidence"), (int, float))]),
        "attempts": dist([r.get("attempt_count", 0) for r in rows]),
        "users": len(per_user),
        "top_user_share": round(per_user.most_common(1)[0][1] / n, 3) if n else None,
        "turns": len(per_turn),
        "events_per_turn": dist(list(per_turn.values())),
        "distinct_concepts": len(concepts),
        "concepts_in_kg_files": f"{inside}/{len(concepts)}",
        "kg_concept_ids_loaded": len(known),
        "by_concept_family": {k: {"events": v[0], "incorrect_rate": round(v[1] / v[0], 3)} for k, v in sorted(prefix.items(), key=lambda kv: -kv[1][0])},
        "top_concepts": concepts.most_common(8),
        "first": str(min(dates)) if dates else None,
        "last": str(max(dates)) if dates else None,
    }


def reconcile(db: Any) -> dict[str, Any]:
    col = db["ai_interactions"]
    docs = list(col.find({}, {"observation_reconcile": 1}))
    rec = [d["observation_reconcile"] for d in docs if d.get("observation_reconcile")]
    return {
        "docs": len(docs),
        "by_status": collections.Counter(r.get("status") for r in rec),
        "by_error_code": collections.Counter(r.get("last_error_code") for r in rec),
        "attempts": dist([r.get("attempt_count", 0) for r in rec]),
        "observations_per_turn": dist([len(r.get("observations") or []) for r in rec]),
    }


def turns(db: Any) -> dict[str, Any]:
    rows = list(db["tracecag_turn_metrics"].find({}))
    n = len(rows)

    def nums(key: str) -> list[float]:
        return [r[key] for r in rows if isinstance(r.get(key), (int, float))]

    def rate(key: str) -> float | None:
        return round(sum(bool(r.get(key)) for r in rows) / n, 3) if n else None

    fresh = [r["latency_ms"] for r in rows if not r.get("cache_hit") and isinstance(r.get("latency_ms"), (int, float))]
    return {
        "turns": n,
        "by_path": dict(collections.Counter(r.get("path") for r in rows)),
        "cache_hit_rate": rate("cache_hit"),
        "error_rate": rate("error"),
        "learner_state_degraded_rate": rate("learner_state_degraded"),
        "latency_ms": dist(nums("latency_ms")),
        "latency_ms_uncached": dist(fresh),
        "ttft_ms": dist(nums("ttft_ms")),
        "learner_state_ms": dist(nums("learner_state_ms")),
        "kg_seed": dist(nums("kg_seed")),
        "kg_expanded": dist(nums("kg_expanded")),
        "retrieved": dist(nums("retrieved")),
        "diagnosis_errors": dist(nums("diagnosis_errors")),
        "prompt_tokens": dist(nums("prompt_tokens")),
        "models": dict(collections.Counter(m for r in rows for m in r.get("models") or [])),
        "first": str(min(r["ts"] for r in rows)) if rows else None,
        "last": str(max(r["ts"] for r in rows)) if rows else None,
    }


def main() -> None:
    db = MongoClient(os.environ.get("MONGODB_URI", "mongodb://mongodb:27017"), serverSelectionTimeoutMS=10000)[os.environ.get("MONGODB_DATABASE", "lexilingo")]
    report = {"turn_metrics": turns(db), "chat": chat(db), "spool": spool(db, kg_ids()), "reconcile": reconcile(db)}
    print(json.dumps(report, indent=2, default=str, ensure_ascii=False))


if __name__ == "__main__":
    main()
