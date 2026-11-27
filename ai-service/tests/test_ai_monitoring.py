import asyncio
import json
import time
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from redis.exceptions import MaxConnectionsError

from api.core.groq_key_pool import GroqKeyPool
from api.routes import ai as ai_routes
from api.services import ai_monitoring

NOW = datetime(2026, 11, 24, 12, 30, tzinfo=UTC)
# Shaped like a Groq key so a leak is recognisable; joined at runtime so no secret-looking literal is committed.
SECRET = "_".join(["gsk", "fixture", "never", "real"])


def _facet_names(pipeline):
    return set(next(s for s in pipeline if "$facet" in s)["$facet"])


def _facets(pipeline):
    return next(s for s in pipeline if "$facet" in s)["$facet"]


def test_window_picks_the_series_bucket():
    assert ai_monitoring.WINDOWS["1h"].unit == "minute"
    assert ai_monitoring.WINDOWS["24h"].unit == "hour"
    assert ai_monitoring.WINDOWS["7d"].unit == "day"


def test_pipeline_is_one_scan_bounded_by_the_window():
    since = NOW - timedelta(hours=24)
    pipeline = ai_monitoring.build_chat_pipeline(since, ai_monitoring.WINDOWS["24h"])

    assert pipeline[0] == {"$match": {"ts": {"$gte": since}}}
    assert {"totals", "latency_all", "latency_by_hit", "usage_source", "layers", "bypass",
            "models", "series", "f1"} <= _facet_names(pipeline)


def test_pipeline_uses_percentile_accumulator_that_mongo_7_has():
    pipeline = ai_monitoring.build_chat_pipeline(NOW, ai_monitoring.WINDOWS["24h"])
    dumped = json.dumps(pipeline, default=str)

    assert '"$percentile"' in dumped and '"approximate"' in dumped
    assert '"$dateTrunc"' in dumped


def test_rows_missing_the_newer_fields_are_counted_not_dropped():
    facets = _facets(ai_monitoring.build_chat_pipeline(NOW, ai_monitoring.WINDOWS["24h"]))

    layers_group = next(s for s in facets["layers"] if "$group" in s)["$group"]
    assert layers_group["_id"] == {"$ifNull": ["$cache_layer", "none"]}


def test_usage_source_blank_or_unknown_is_not_recorded():
    facets = _facets(ai_monitoring.build_chat_pipeline(NOW, ai_monitoring.WINDOWS["24h"]))

    group = next(s for s in facets["usage_source"] if "$group" in s)["$group"]
    assert group["_id"] == {"$cond": [
        {"$in": ["$usage_source", ["provider", "partial", "none"]]}, "$usage_source", "not_recorded",
    ]}


def test_token_averages_read_only_rows_with_measured_usage():
    facets = _facets(ai_monitoring.build_chat_pipeline(NOW, ai_monitoring.WINDOWS["24h"]))
    totals = next(s for s in facets["totals"] if "$group" in s)["$group"]
    measured = {"$in": ["$usage_source", ["provider", "partial"]]}

    assert totals["prompt_avg"] == {"$avg": {"$cond": [measured, "$prompt_tokens", None]}}
    assert totals["usage_turns"] == {"$sum": {"$cond": [measured, 1, 0]}}
    assert totals["partial_turns"] == {"$sum": {"$cond": [{"$eq": ["$usage_source", "partial"]}, 1, 0]}}


def test_topic_chat_rows_are_left_out_of_latency_but_counted():
    facets = _facets(ai_monitoring.build_chat_pipeline(NOW, ai_monitoring.WINDOWS["24h"]))
    skip = {"$eq": ["$generation_policy", "skip"]}

    for name in ("latency_all", "latency_by_hit"):
        group = next(s for s in facets[name] if "$group" in s)["$group"]
        assert group["latency_ms"]["$percentile"]["input"] == {"$cond": [skip, None, "$latency_ms"]}
        assert group["ttft_ms"]["$percentile"]["input"] == {"$cond": [skip, None, "$ttft_ms"]}
    totals = next(s for s in facets["totals"] if "$group" in s)["$group"]
    assert totals["topic_turns"] == {"$sum": {"$cond": [skip, 1, 0]}}


def test_a_model_repeated_on_one_row_is_counted_once():
    facets = _facets(ai_monitoring.build_chat_pipeline(NOW, ai_monitoring.WINDOWS["24h"]))

    assert {"$project": {"models": {"$setUnion": [{"$ifNull": ["$models", []]}, []]}}} in facets["models"]
    assert facets["models"].index({"$unwind": "$models"}) > 0


RAW = {
    "totals": [{"turns": 4, "errors": 1, "degraded": 1, "hits": 2, "topic_turns": 1, "prompt_sum": 3000,
                "completion_sum": 600, "cached_sum": 1200, "prompt_avg": 1500.0,
                "completion_avg": 300.0, "cached_avg": 600.0, "usage_turns": 2, "partial_turns": 1}],
    "latency_all": [{"_id": None, "latency_ms": [800.0, 2400.0], "ttft_ms": [300.0, 900.0],
                     "first_chunk_ms": [None, None]}],
    "latency_by_hit": [
        {"_id": True, "latency_ms": [20.0, 40.0], "ttft_ms": [5.0, 9.0], "first_chunk_ms": [None, None]},
        {"_id": False, "latency_ms": [1500.0, 2600.0], "ttft_ms": [600.0, 950.0], "first_chunk_ms": [200.0, 300.0]},
    ],
    "usage_source": [{"_id": "provider", "turns": 1}, {"_id": "partial", "turns": 1},
                     {"_id": "none", "turns": 1}, {"_id": "not_recorded", "turns": 1}],
    "layers": [{"_id": "L0", "turns": 1}, {"_id": "L1", "turns": 1}, {"_id": "none", "turns": 2}],
    "bypass": [{"_id": "facts", "turns": 1}, {"_id": "", "turns": 2}, {"_id": None, "turns": 1}],
    "models": [{"_id": "qwen/qwen3.8-27b", "turns": 2}],
    # Motor returns naive datetimes that are UTC
    "series": [
        {"_id": datetime(2026, 11, 24, 10, 0), "turns": 3, "latency_ms": [700.0, 2000.0], "tokens": 2400},
        {"_id": datetime(2026, 11, 24, 12, 0), "turns": 1, "latency_ms": [None, None], "tokens": 0},
    ],
    "f1": [{"_id": 0.0, "count": 1}, {"_id": 0.8, "count": 2}, {"_id": "out", "count": 0}],
}


def _report(raw=RAW, window="24h", shadow=None):
    return ai_monitoring.shape_chat_report(raw, window=window, now=NOW, shadow=shadow)


def test_shape_reports_every_section():
    report = _report(shadow={"compared": 10, "low_similarity": 2})

    assert report["turns"] == 4 and report["error_rate"] == 0.25
    assert report["topic_turns"] == 1
    assert report["latency"]["all"]["latency_ms"] == {"p50": 800.0, "p95": 2400.0}
    assert report["latency"]["all"]["first_chunk_ms"] == {"p50": None, "p95": None}
    assert report["latency"]["hit"]["latency_ms"]["p95"] == 40.0
    assert report["latency"]["miss"]["first_chunk_ms"]["p50"] == 200.0
    assert report["tokens"]["prompt_avg"] == 1500.0
    assert report["tokens"]["per_turn"] == 1800.0
    assert report["tokens"]["reported_turns"] == 2 and report["tokens"]["partial_turns"] == 1
    assert report["tokens"]["usage_source"]["partial"] == {"turns": 1, "share": 0.25}
    assert report["tokens"]["usage_source"]["not_recorded"] == {"turns": 1, "share": 0.25}
    assert report["cache"]["hit_rate"] == 0.5
    assert report["cache"]["layers"]["L0"] == {"turns": 1, "share": 0.25}
    assert report["cache"]["bypass"] == {"facts": {"turns": 1, "share": 0.25}}
    assert report["cache"]["l1_shadow"]["low_similarity_rate"] == 0.2
    assert report["cache"]["l1_shadow"]["f1_distribution"][0] == {"from": 0.0, "count": 1}
    assert report["learner_state"] == {"degraded": 1, "degraded_rate": 0.25}
    assert report["models"] == [{"model": "qwen/qwen3.8-27b", "turns": 2}]


def test_timestamps_are_utc_with_an_offset_even_from_naive_motor_datetimes():
    report = _report()

    assert report["generated_at"] == "2026-11-24T12:30:00+00:00"
    assert report["since"] == "2026-11-23T12:30:00+00:00"
    stamps = [p["ts"] for p in report["series"]]
    assert all(ts.endswith("+00:00") for ts in stamps)
    assert datetime.fromisoformat("2026-11-24T10:00:00+00:00").isoformat() in stamps


def test_quiet_hours_are_filled_with_zero_turn_buckets():
    series = _report()["series"]

    hours = [p["ts"][:13] for p in series]
    assert hours[0] == "2026-11-23T12" and hours[-1] == "2026-11-24T12"
    assert len(hours) == 25
    quiet = next(p for p in series if p["ts"].startswith("2026-11-24T11"))
    assert quiet == {"ts": "2026-11-24T11:00:00+00:00", "turns": 0, "p95_latency_ms": None, "tokens": 0}
    busy = next(p for p in series if p["ts"].startswith("2026-11-24T10"))
    assert busy["turns"] == 3 and busy["p95_latency_ms"] == 2000.0


def test_bucket_edges_for_the_short_and_long_windows():
    five_min = _report(window="1h")["series"]
    assert len(five_min) == 13 and five_min[-1]["ts"] == "2026-11-24T12:30:00+00:00"
    daily = _report(window="7d")["series"]
    assert len(daily) == 8 and daily[0]["ts"] == "2026-11-17T00:00:00+00:00"


def test_an_empty_window_is_a_zero_report_not_a_crash():
    report = _report({k: [] for k in RAW}, window="1h")

    assert report["turns"] == 0 and report["error_rate"] is None
    assert report["latency"]["all"]["latency_ms"] == {"p50": None, "p95": None}
    assert report["cache"]["hit_rate"] is None
    assert report["cache"]["l1_shadow"]["compared"] is None
    assert report["models"] == []
    assert all(p["turns"] == 0 for p in report["series"])


class _Cursor:
    def __init__(self, docs):
        self._docs = docs

    async def to_list(self, length):
        return self._docs[:length]


def _db_returning(docs):
    collection = MagicMock()
    collection.aggregate = MagicMock(return_value=_Cursor(docs))
    db = MagicMock()
    db.__getitem__ = MagicMock(return_value=collection)
    return db, collection


@pytest.mark.asyncio
async def test_chat_report_aggregates_in_mongo_and_reads_shadow_from_redis():
    db, collection = _db_returning([RAW])
    redis = MagicMock()
    redis.hgetall = AsyncMock(return_value={b"compared": b"10", b"low_similarity": b"2"})

    report = await ai_monitoring.chat_report(db, redis, "24h", now=NOW)

    pipeline = collection.aggregate.call_args.args[0]
    assert pipeline[0]["$match"]["ts"]["$gte"] == NOW - timedelta(hours=24)
    redis.hgetall.assert_awaited_once_with("v1:l1_shadow:stats")
    assert report["cache"]["l1_shadow"]["compared"] == 10


@pytest.mark.asyncio
async def test_a_dead_redis_only_blanks_the_shadow_counters():
    db, _ = _db_returning([RAW])
    redis = MagicMock()
    redis.hgetall = AsyncMock(side_effect=ConnectionError("down"))

    report = await ai_monitoring.chat_report(db, redis, "24h", now=NOW)

    assert report["turns"] == 4
    assert report["cache"]["l1_shadow"]["compared"] is None


@pytest.mark.asyncio
async def test_mongo_and_redis_are_read_together():
    gate = asyncio.Event()
    seen: list[str] = []

    class _Slow:
        def to_list(self, length):
            async def run():
                seen.append("mongo")
                await asyncio.wait_for(gate.wait(), 1)
                return [RAW]
            return run()

    collection = MagicMock()
    collection.aggregate = MagicMock(return_value=_Slow())
    db = MagicMock()
    db.__getitem__ = MagicMock(return_value=collection)
    redis = MagicMock()

    async def hgetall(key):
        seen.append("redis")
        gate.set()
        return {}

    redis.hgetall = hgetall

    await ai_monitoring.chat_report(db, redis, "24h", now=NOW)

    assert seen == ["mongo", "redis"]


@pytest.mark.asyncio
async def test_no_rows_means_no_facet_document():
    db, _ = _db_returning([])

    report = await ai_monitoring.chat_report(db, None, "7d", now=NOW)

    assert report["turns"] == 0


def test_spool_numbers_come_from_status_counts_and_telemetry():
    spool = ai_monitoring.shape_spool(
        [{"_id": "pending", "n": 3}, {"_id": "retry", "n": 2}, {"_id": "processing", "n": 1},
         {"_id": "dead", "n": 5}, {"_id": "delivered", "n": 90}],
        {"learner_state_degraded_total.receiver_off": 4, "learner_state_degraded_total.observation_dead": 1},
    )

    assert spool["queue_depth"] == 6
    assert spool["dead"] == 5 and spool["delivered"] == 90
    assert spool["receiver_off_since_start"] == 4
    assert spool["dead_since_start"] == 1


@pytest.mark.asyncio
async def test_spool_report_raises_so_the_route_can_own_the_failure():
    db = MagicMock()
    db.__getitem__ = MagicMock(side_effect=RuntimeError("down"))

    with pytest.raises(RuntimeError):
        await ai_monitoring.spool_report(db, {})


# ---------------------------------------------------------------- key pool


class _Pipe:
    def __init__(self, redis):
        self._redis, self._ops = redis, []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    def zremrangebyscore(self, name, min, max):
        self._ops.append(lambda: 0)
        return self

    def zcard(self, name):
        self._ops.append(lambda: len(self._redis.zsets.get(name, {})))
        return self

    def zrange(self, name, start, end):
        self._ops.append(lambda: list(self._redis.zsets.get(name, {})))
        return self

    def zcount(self, name, min, max):
        self._ops.append(lambda: sum(1 for s in self._redis.zsets.get(name, {}).values() if float(min) <= s <= float(max)))
        return self

    def exists(self, *names):
        self._ops.append(lambda: sum(1 for n in names if n in self._redis.strings))
        return self

    async def execute(self):
        return [op() for op in self._ops]


class _Redis:
    def __init__(self, zsets=None, strings=None):
        self.zsets, self.strings = zsets or {}, strings or {}

    def pipeline(self, transaction=True):
        return _Pipe(self)


def _pool(redis, n=5):
    return GroqKeyPool(keys=[f"{SECRET}{i}" for i in range(n)], redis_client=redis)


@pytest.mark.asyncio
async def test_key_snapshot_applies_the_admission_rule_without_key_material():
    now = time.time()
    redis = _Redis(
        zsets={
            "groq:key0:tpm": {f"{now}-4900-1-tokens": now - 5},
            "groq:key1:rpm": {f"m{i}": now - 5 for i in range(28)},
            "groq:key1:tpm": {f"{now}-1000-1-tokens": now - 5},
            "groq:key1:rpd": {f"m{i}": now - 5 for i in range(28)},
            "groq:key2:rpd": {f"d{i}": now - 100 for i in range(13_000)},
            "groq:key4:voice:rpm": {f"v{i}": now - 5 for i in range(27)},
        },
        strings={"groq:key3:voice:lease": "tok"},
    )

    snapshot = await _pool(redis).usage_snapshot()

    assert [k["index"] for k in snapshot] == [0, 1, 2, 3, 4]
    assert [k["state"] for k in snapshot] == ["cooling", "cooling", "exhausted", "busy", "cooling"]
    assert snapshot[0]["tpm"] == 4900
    assert snapshot[1]["rpm"] == 28 and snapshot[1]["tpm"] == 1000
    assert snapshot[2]["rpd"] == 13_000 and snapshot[2]["rpd_limit"] == 14_400
    assert snapshot[4]["voice_rpm"] == 27
    assert SECRET not in json.dumps(snapshot)


class _LimitedPipe(_Pipe):
    """Holds one pooled connection while executing, as redis-py's non-blocking pool does."""

    async def execute(self):
        redis = self._redis
        if redis.in_use >= redis.max_connections:
            raise MaxConnectionsError("Too many connections")
        redis.in_use += 1
        try:
            await asyncio.sleep(0)
            return await super().execute()
        finally:
            redis.in_use -= 1


class _LimitedRedis(_Redis):
    def __init__(self, max_connections):
        super().__init__()
        self.max_connections, self.in_use = max_connections, 0

    def pipeline(self, transaction=True):
        return _LimitedPipe(self)


@pytest.mark.asyncio
async def test_a_large_key_pool_snapshot_does_not_exhaust_the_redis_pool():
    # Production: 34 keys against max_connections=50 returned 503. The smallest pool
    # redis_client allows is 10, and live chat shares it.
    snapshot = await _pool(_LimitedRedis(max_connections=10), n=34).usage_snapshot()

    assert [k["index"] for k in snapshot] == list(range(34))


@pytest.mark.asyncio
async def test_a_key_the_pool_would_hand_out_is_never_reported_cooling():
    now = time.time()
    redis = _Redis(zsets={"groq:key0:tpm": {f"{now}-4700-1-tokens": now - 5}})
    pool = _pool(redis, n=1)

    state = (await pool.usage_snapshot())[0]["state"]
    admitted = await pool._limiters[0].can_request(600)

    assert (state == "available") is admitted


@pytest.mark.asyncio
async def test_key_report_totals_and_model(monkeypatch):
    monkeypatch.setenv("GROQ_MODEL", "qwen/qwen3.8-27b")
    redis = _Redis(strings={"groq:key3:voice:lease": "tok"})

    report = await ai_monitoring.llm_key_report(_pool(redis, n=4))

    assert report["mode"] == "pool"
    assert report["model"] == "qwen/qwen3.8-27b"
    assert report["totals"] == {"keys": 4, "available": 3, "busy": 1, "cooling": 0, "exhausted": 0}
    assert SECRET not in json.dumps(report)


@pytest.mark.asyncio
async def test_without_a_pool_the_report_says_so():
    report = await ai_monitoring.llm_key_report(None, configured=34)

    assert report["mode"] == "unpooled" and report["keys"] == []
    assert report["totals"]["keys"] == 34


# ------------------------------------------------------------------ routes


def _app() -> FastAPI:
    app = FastAPI()
    app.include_router(ai_routes.router, prefix="/api/v1/ai")
    return app


def _with_db(app: FastAPI) -> None:
    from api.core.database import get_database

    app.dependency_overrides[get_database] = lambda: MagicMock()


@pytest.mark.asyncio
@pytest.mark.parametrize("path", ["chat", "llm-keys", "observation-spool"])
async def test_monitoring_routes_are_admin_guarded(monkeypatch, path):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "right")
    async with AsyncClient(transport=ASGITransport(app=_app()), base_url="http://t") as client:
        wrong = await client.get(f"/api/v1/ai/monitoring/{path}", headers={"X-Admin-Key": "wrong"})
        none = await client.get(f"/api/v1/ai/monitoring/{path}")

    assert wrong.status_code == 403 and none.status_code == 403


@pytest.mark.asyncio
async def test_chat_route_returns_the_report_without_the_spool(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "right")
    app = _app()
    _with_db(app)
    with patch.object(ai_routes, "chat_report", autospec=True,
                      return_value={"turns": 7, "window": "7d"}) as build, \
         patch.object(ai_routes, "_redis_or_none", autospec=True, return_value=None):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as client:
            ok = await client.get("/api/v1/ai/monitoring/chat?window=7d", headers={"X-Admin-Key": "right"})
            bad = await client.get("/api/v1/ai/monitoring/chat?window=1y", headers={"X-Admin-Key": "right"})

    assert ok.status_code == 200 and ok.json() == {"turns": 7, "window": "7d"}
    assert build.await_args.args[2] == "7d"
    assert bad.status_code == 422


@pytest.mark.asyncio
async def test_chat_route_hides_mongo_errors(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "right")
    app = _app()
    _with_db(app)
    with patch.object(ai_routes, "chat_report", autospec=True,
                      side_effect=RuntimeError("mongodb://user:pw@host")), \
         patch.object(ai_routes, "_redis_or_none", autospec=True, return_value=None):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as client:
            res = await client.get("/api/v1/ai/monitoring/chat", headers={"X-Admin-Key": "right"})

    assert res.status_code == 503 and "pw" not in res.text


@pytest.mark.asyncio
async def test_the_spool_answers_when_the_chat_aggregation_is_down(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "right")
    app = _app()
    _with_db(app)
    with patch.object(ai_routes, "chat_report", autospec=True, side_effect=RuntimeError("down")), \
         patch.object(ai_routes, "spool_report", autospec=True, return_value={"queue_depth": 2}), \
         patch.object(ai_routes, "_redis_or_none", autospec=True, return_value=None):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as client:
            chat = await client.get("/api/v1/ai/monitoring/chat", headers={"X-Admin-Key": "right"})
            spool = await client.get("/api/v1/ai/monitoring/observation-spool", headers={"X-Admin-Key": "right"})

    assert chat.status_code == 503
    assert spool.status_code == 200 and spool.json() == {"queue_depth": 2}


@pytest.mark.asyncio
async def test_spool_route_hides_its_own_errors(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "right")
    app = _app()
    _with_db(app)
    with patch.object(ai_routes, "spool_report", autospec=True, side_effect=RuntimeError("mongodb://u:pw@h")):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as client:
            res = await client.get("/api/v1/ai/monitoring/observation-spool", headers={"X-Admin-Key": "right"})

    assert res.status_code == 503 and "pw" not in res.text


@pytest.mark.asyncio
async def test_keys_route_returns_the_pool_report(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "right")
    with patch.object(ai_routes, "llm_key_report", autospec=True, return_value={"mode": "pool", "keys": []}):
        async with AsyncClient(transport=ASGITransport(app=_app()), base_url="http://t") as client:
            res = await client.get("/api/v1/ai/monitoring/llm-keys", headers={"X-Admin-Key": "right"})

    assert res.status_code == 200 and res.json()["mode"] == "pool"
