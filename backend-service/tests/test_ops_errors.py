"""Error monitoring: capture, grouping, flush, alerts, digests, settings and routes."""

import json
from datetime import UTC, datetime, timedelta
from unittest.mock import patch

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.config import settings
from app.core.exceptions import http_exception_handler, unhandled_exception_handler
from app.core.middleware import RequestIDMiddleware, RequestLoggingMiddleware
from app.core.redis import RedisClient
from app.models.ops_error import OpsErrorCount, OpsErrorGroup
from app.services import ops_errors
from app.services.ops_errors import (
    BUF_KEY,
    ErrorReportSettingsUpdate,
    fingerprint,
    location_from_exc,
    record_error,
    redact,
    run_digest,
    run_flush,
)

NOW = datetime(2026, 11, 28, 10, 30, tzinfo=UTC)


class FakePipeline:
    def __init__(self, redis):
        self.redis = redis
        self.calls = []

    def __getattr__(self, name):
        def queue(*args, **kwargs):
            self.calls.append((name, args, kwargs))
            return self

        return queue

    async def execute(self):
        for name, args, kwargs in self.calls:
            getattr(self.redis, f"_{name}")(*args, **kwargs)
        self.calls = []


class FakeRedis:
    """The Redis calls ops_errors makes, with real RENAME / NX / HINCRBY semantics."""

    def __init__(self):
        self.data = {}

    def pipeline(self, transaction=False):
        return FakePipeline(self)

    def _hincrby(self, key, field, amount=1):
        h = self.data.setdefault(key, {})
        h[field] = int(h.get(field, 0)) + amount

    def _set(self, key, value, ex=None, nx=False):
        if nx and key in self.data:
            return None
        self.data[key] = value
        return True

    def _incrby(self, key, amount=1):
        self.data[key] = int(self.data.get(key, 0)) + amount

    def _expire(self, key, seconds):
        return True

    async def set(self, *args, **kwargs):
        return self._set(*args, **kwargs)

    async def exists(self, key):
        return int(key in self.data)

    async def rename(self, src, dst):
        self.data[dst] = self.data.pop(src)

    async def hgetall(self, key):
        return {k: str(v) for k, v in self.data.get(key, {}).items()}

    async def mget(self, keys):
        return [self.data.get(k) for k in keys]

    async def delete(self, *keys):
        for k in keys:
            self.data.pop(k, None)


@pytest.fixture
def redis(monkeypatch):
    fake = FakeRedis()

    async def get_instance():
        return fake

    monkeypatch.setattr(RedisClient, "get_instance", staticmethod(get_instance))
    return fake


@pytest.fixture
def smtp(monkeypatch):
    for name, value in {"SMTP_HOST": "smtp.test", "SMTP_USERNAME": "u", "SMTP_PASSWORD": "p", "SMTP_USE_SSL": False}.items():
        monkeypatch.setattr(settings, name, value)
    with patch("app.services.email_service.smtplib.SMTP", autospec=True) as client:
        yield client.return_value.__enter__.return_value.send_message


def mails(send_message):
    return [call.args[0] for call in send_message.call_args_list]


async def err(route="/api/v1/lessons/{lesson_id}", status=500, kind="error", count=1, **kw):
    kw.setdefault("error_type", "ValueError")
    kw.setdefault("location", "learning.py:start_lesson")
    assert await record_error(
        service="backend", kind=kind, method="GET", route=route, status=status, count=count, **kw
    )


def test_fingerprint_ignores_message_and_client_groups_ignore_location():
    a = fingerprint("backend", "error", "GET", "/x/{id}", 500, "ValueError", "a.py:f")
    assert a == fingerprint("backend", "error", "GET", "/x/{id}", 500, "ValueError", "a.py:f")
    assert a != fingerprint("backend", "error", "GET", "/x/{id}", 500, "KeyError", "a.py:f")
    c = fingerprint("backend", "client", "GET", "/x/{id}", 404, "A", "a.py:f")
    assert c == fingerprint("backend", "client", "GET", "/x/{id}", 404, "B", "b.py:g")


def test_redact_hides_identifying_data_and_caps_length():
    text = (
        "user a.b+c@mail.com id 123e4567-e89b-12d3-a456-426614174000 order 1234567 "
        "Bearer abc.def.ghi jwt eyJhbGciOi.eyJzdWIiOi.sig-nature ok 12345"
    )
    out = redact(text)
    assert "[email]" in out and "[id]" in out and "[n]" in out and "[token]" in out
    assert "mail.com" not in out and "1234567" not in out and "abc.def" not in out and "eyJ" not in out
    assert "12345" in out
    assert len(redact("x" * 1000)) == 300
    assert redact(None) is None


def test_location_is_the_last_frame_inside_the_app_package():
    try:
        redact(5)
    except TypeError as exc:
        assert location_from_exc(exc) == "ops_errors.py:redact"
    try:
        raise ValueError("outside the app")
    except ValueError as exc:
        assert location_from_exc(exc) is None
    assert location_from_exc(None) is None


def make_app() -> FastAPI:
    app = FastAPI()
    app.add_exception_handler(HTTPException, http_exception_handler)
    app.add_exception_handler(Exception, unhandled_exception_handler)
    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(RequestIDMiddleware)

    @app.get("/boom/{item_id}")
    async def boom(item_id: str):
        raise RuntimeError(f"cannot load {item_id} for owner@mail.com")

    @app.get("/unavailable")
    async def unavailable():
        raise HTTPException(503, "upstream down")

    @app.get("/direct-503")
    async def direct():
        return JSONResponse({"x": 1}, status_code=503)

    @app.get("/missing/{item_id}")
    async def missing(item_id: str):
        raise HTTPException(404, "nope")

    @app.get("/health")
    async def health():
        raise HTTPException(503, "db down")

    return app


@pytest.fixture
async def client():
    transport = ASGITransport(app=make_app(), raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


def buffered(redis: FakeRedis) -> dict:
    return {fp: int(n) for fp, n in redis.data.get(BUF_KEY, {}).items()}


def metas(redis: FakeRedis) -> list[dict]:
    return [json.loads(v) for k, v in redis.data.items() if k.startswith("ops:err:meta:")]


async def test_two_ids_on_one_route_make_one_group_and_a_failing_request_counts_once(client, redis):
    assert (await client.get("/boom/1")).status_code == 500
    assert (await client.get("/boom/2")).status_code == 500

    assert list(buffered(redis).values()) == [2]
    (meta,) = metas(redis)
    assert meta["route"] == "/boom/{item_id}"
    assert meta["error_type"] == "RuntimeError"
    assert meta["location"] is None, "a middleware frame is not where the error happened"
    assert meta["message"].endswith("for [email]")
    assert "owner@mail.com" not in meta["message"]
    assert meta["request_id"]


async def test_http_exception_503_and_a_direct_503_response_are_each_recorded_once(client, redis):
    await client.get("/unavailable")
    await client.get("/direct-503")

    by_route = {m["route"]: m for m in metas(redis)}
    assert by_route["/unavailable"]["message"] == "upstream down"
    assert by_route["/direct-503"]["status"] == 503
    assert sorted(buffered(redis).values()) == [1, 1]


async def test_a_4xx_is_a_client_group_and_health_is_never_recorded(client, redis):
    await client.get("/missing/9")
    await client.get("/health")
    await client.get("/nowhere")

    kinds = {(m["route"], m["kind"], m["status"]) for m in metas(redis)}
    assert kinds == {("/missing/{item_id}", "client", 404), ("<unmatched>", "client", 404)}


async def test_redis_down_leaves_the_failing_request_a_plain_500(client, monkeypatch):
    async def none():
        return None

    monkeypatch.setattr(RedisClient, "get_instance", staticmethod(none))
    response = await client.get("/boom/1")

    assert response.status_code == 500
    assert response.json()["error"]["code"] == "INTERNAL_ERROR"


async def test_redis_that_raises_never_reaches_the_request(client, monkeypatch):
    async def broken():
        raise ConnectionError("redis gone")

    monkeypatch.setattr(RedisClient, "get_instance", staticmethod(broken))
    assert (await client.get("/boom/1")).status_code == 500
    assert (await client.get("/unavailable")).status_code == 503


async def test_flush_upserts_groups_and_one_hourly_bucket(db_session, redis):
    await err(count=3)
    await run_flush_only(db_session, redis, NOW)
    await err(count=2)
    await run_flush_only(db_session, redis, NOW + timedelta(minutes=20))

    (group,) = (await db_session.execute(select(OpsErrorGroup))).scalars().all()
    assert (group.total_count, group.state, group.reported_count, group.regressed) == (5, "open", 0, False)
    assert group.first_seen == NOW and group.last_seen == NOW + timedelta(minutes=20)
    (bucket,) = (await db_session.execute(select(OpsErrorCount))).scalars().all()
    assert bucket.bucket_start == NOW.replace(minute=0) and bucket.count == 5
    assert BUF_KEY not in redis.data and ops_errors.FLUSHING_KEY not in redis.data


async def run_flush_only(db, redis, now):
    return await ops_errors.flush_buffer(db, redis, now)


async def test_a_buffer_left_by_a_crashed_flush_is_not_lost(db_session, redis):
    await err()
    await redis.rename(BUF_KEY, ops_errors.FLUSHING_KEY)
    await err(route="/other")

    await run_flush_only(db_session, redis, NOW)
    assert (await db_session.execute(select(OpsErrorGroup))).scalars().all()[0].total_count == 1
    await run_flush_only(db_session, redis, NOW)

    totals = sorted(g.total_count for g in (await db_session.execute(select(OpsErrorGroup))).scalars())
    assert totals == [1, 1]


async def test_a_new_5xx_group_alerts_once_and_a_spike_waits_out_the_cooldown(db_session, redis, smtp):
    await err()
    result = await run_flush(db_session, redis)
    assert result["alerts"] == 1
    subject = mails(smtp)[0]["Subject"]
    assert subject == "[LexiLingo ALERT] 1 error in 1 group · last 5 min"

    await err(count=30)
    await run_flush(db_session, redis)
    assert len(mails(smtp)) == 1

    del redis.data[ops_errors.ALERTED_KEY.format(fp=next(iter(await _fps(db_session))))]
    await err(count=30)
    await run_flush(db_session, redis)
    assert len(mails(smtp)) == 2


async def _fps(db):
    return (await db.execute(select(OpsErrorGroup.fingerprint))).scalars().all()


async def test_a_client_spike_alerts_only_past_its_threshold_and_then_cools_down(db_session, redis, smtp):
    await err(route="/login", status=401, kind="client", count=150, error_type=None, location=None)
    await run_flush(db_session, redis)
    assert mails(smtp) == []

    await err(route="/login", status=401, kind="client", count=100, error_type=None, location=None)
    await run_flush(db_session, redis)
    assert len(mails(smtp)) == 1

    await err(route="/login", status=401, kind="client", count=300, error_type=None, location=None)
    await run_flush(db_session, redis)
    assert len(mails(smtp)) == 1


async def test_muted_groups_never_alert_and_a_resolved_group_reopens_as_regressed(db_session, redis, smtp):
    await err()
    await run_flush(db_session, redis)
    group = (await db_session.execute(select(OpsErrorGroup))).scalar_one()
    group.state = "muted"
    await db_session.commit()
    redis.data.pop(ops_errors.ALERTED_KEY.format(fp=group.fingerprint), None)
    await err(count=50)
    await run_flush(db_session, redis)
    assert len(mails(smtp)) == 1
    await db_session.refresh(group)
    assert group.state == "muted"

    group.state = "resolved"
    await db_session.commit()
    redis.data.pop(ops_errors.ALERTED_KEY.format(fp=group.fingerprint), None)
    await err()
    await run_flush(db_session, redis)
    await db_session.refresh(group)
    assert (group.state, group.regressed) == ("open", True)
    assert len(mails(smtp)) == 2


async def test_digest_mails_only_new_errors_and_respects_the_interval(db_session, redis, smtp):
    assert (await run_digest(db_session, NOW))["skipped"] == "no new errors"

    await err(count=4)
    await err(route="/other", count=2, error_type="KeyError", location="x.py:y")
    await ops_errors.flush_buffer(db_session, redis, NOW)

    result = await run_digest(db_session, NOW)
    assert result["groups"] == 2
    (mail,) = mails(smtp)
    assert mail["Subject"] == "[LexiLingo] 6 errors in 2 groups · last 60 min"
    assert mail["To"] == "support@lexilingo.me"
    body = mail.get_body(("plain",)).get_content()
    assert "NEW" in body and "/api/v1/lessons/{lesson_id}" in body
    assert all(g.reported_count == g.total_count for g in (await db_session.execute(select(OpsErrorGroup))).scalars())

    await err()
    await ops_errors.flush_buffer(db_session, redis, NOW + timedelta(minutes=10))
    assert (await run_digest(db_session, NOW + timedelta(minutes=10)))["skipped"] == "not due"

    later = await run_digest(db_session, NOW + timedelta(minutes=61))
    assert later["groups"] == 1
    assert mails(smtp)[1]["Subject"] == "[LexiLingo] 1 error in 1 group · last 60 min"
    assert (await run_digest(db_session, NOW + timedelta(minutes=200)))["skipped"] == "no new errors"


async def test_digest_skips_muted_and_small_client_groups_but_not_big_ones(db_session, redis, smtp):
    await err(count=3)
    await err(route="/muted", count=3)
    await err(route="/login", status=401, kind="client", count=199, error_type=None, location=None)
    await ops_errors.flush_buffer(db_session, redis, NOW)
    muted = (await db_session.execute(select(OpsErrorGroup).where(OpsErrorGroup.route == "/muted"))).scalar_one()
    muted.state = "muted"
    await db_session.commit()

    assert (await run_digest(db_session, NOW))["groups"] == 1

    await err(route="/login", status=401, kind="client", count=200, error_type=None, location=None)
    await ops_errors.flush_buffer(db_session, redis, NOW + timedelta(hours=2))
    assert (await run_digest(db_session, NOW + timedelta(hours=2)))["groups"] == 1
    assert "/login" in mails(smtp)[1].get_body(("plain",)).get_content()


async def test_a_failed_send_leaves_the_baseline_for_the_next_try(db_session, redis, monkeypatch):
    await err()
    await ops_errors.flush_buffer(db_session, redis, NOW)
    monkeypatch.setattr(settings, "SMTP_HOST", None)

    assert (await run_digest(db_session, NOW))["skipped"] == "send failed"
    group = (await db_session.execute(select(OpsErrorGroup))).scalar_one()
    assert group.reported_count == 0


async def test_prune_drops_buckets_older_than_30_days(db_session, redis):
    await err()
    await ops_errors.flush_buffer(db_session, redis, NOW - timedelta(days=40))
    await err()
    await ops_errors.flush_buffer(db_session, redis, NOW)

    assert await ops_errors.prune_counts(db_session, NOW) == 1
    assert len((await db_session.execute(select(OpsErrorCount))).scalars().all()) == 1


def test_settings_validation_rules():
    ok = ErrorReportSettingsUpdate(recipients=[" A@x.io ", "a@x.io", "b@x.io"], digest_interval_minutes=15)
    assert ok.recipients == ["a@x.io", "b@x.io"]
    for bad in (
        {"recipients": []},
        {"recipients": ["not-an-email"]},
        {"recipients": [f"u{i}@x.io" for i in range(11)]},
        {"digest_interval_minutes": 7},
        {"spike_threshold": -1},
        {"client_spike_threshold": -5},
        {"cooldown_minutes": 0},
        {"last_digest_at": "2026-01-01"},
    ):
        with pytest.raises(ValueError):
            ErrorReportSettingsUpdate(**bad)


ROUTE = "/api/v1/admin/ops"


async def test_learner_and_plain_admin_permissions_on_the_ops_error_routes(
    async_client, auth_headers, admin_headers, super_admin_headers, redis
):
    for path in ("/errors", "/error-report/settings"):
        assert (await async_client.get(f"{ROUTE}{path}", headers=auth_headers)).status_code in (401, 403)
        assert (await async_client.get(f"{ROUTE}{path}", headers=admin_headers)).status_code == 200

    body = {"enabled": False}
    assert (await async_client.put(f"{ROUTE}/error-report/settings", json=body, headers=auth_headers)).status_code == 403
    assert (await async_client.put(f"{ROUTE}/error-report/settings", json=body, headers=admin_headers)).status_code == 403
    assert (await async_client.patch(f"{ROUTE}/errors/abc", json={"state": "muted"}, headers=admin_headers)).status_code == 403
    assert (await async_client.post(f"{ROUTE}/error-report/test", headers=admin_headers)).status_code == 403
    assert (await async_client.put(f"{ROUTE}/error-report/settings", json=body, headers=super_admin_headers)).status_code == 200


async def test_settings_roundtrip_validation_and_audit(async_client, super_admin_headers, db_session):
    url = f"{ROUTE}/error-report/settings"
    first = (await async_client.get(url, headers=super_admin_headers)).json()["data"]
    assert first == {
        "enabled": True, "recipients": ["support@lexilingo.me"], "digest_interval_minutes": 60,
        "spike_threshold": 20, "client_spike_threshold": 200, "cooldown_minutes": 60, "last_digest_at": None,
    }

    for bad in ({"recipients": []}, {"recipients": ["nope"]}, {"digest_interval_minutes": 10},
                {"spike_threshold": -1}, {"last_digest_at": "x"}):
        assert (await async_client.put(url, json=bad, headers=super_admin_headers)).status_code == 422

    saved = await async_client.put(
        url, json={"recipients": ["ops@x.io", "dev@x.io"], "digest_interval_minutes": 180}, headers=super_admin_headers
    )
    assert saved.json()["data"]["recipients"] == ["ops@x.io", "dev@x.io"]
    assert saved.json()["data"]["digest_interval_minutes"] == 180
    assert saved.json()["data"]["spike_threshold"] == 20

    from app.models.rbac import AuditLog

    rows = (await db_session.execute(select(AuditLog).where(AuditLog.action == "error_report_settings_update"))).scalars().all()
    assert len(rows) == 1


async def test_list_filters_and_state_changes(async_client, super_admin_headers, db_session, redis):
    await err(count=5)
    await err(route="/b", status=502, count=2, error_type="HTTPStatusError", location="x.py:f")
    await err(route="/c", kind="client", status=404, count=9, error_type=None, location=None)
    await ops_errors.flush_buffer(db_session, redis, datetime.now(UTC))

    data = (await async_client.get(f"{ROUTE}/errors", headers=super_admin_headers)).json()["data"]
    assert [g["route"] for g in data["groups"]] == ["/c", "/api/v1/lessons/{lesson_id}", "/b"]
    assert [g["count_window"] for g in data["groups"]] == [9, 5, 2]
    assert data["totals"] == {"errors": 16, "groups": 3, "by_service": {"backend": 16}}
    assert set(data["groups"][0]) == {
        "fingerprint", "service", "kind", "method", "route", "status_code", "error_type", "location",
        "sample_message", "sample_request_id", "first_seen", "last_seen", "total_count", "count_window",
        "state", "regressed",
    }

    only_errors = (await async_client.get(f"{ROUTE}/errors?kind=error", headers=super_admin_headers)).json()["data"]
    assert only_errors["totals"]["groups"] == 2
    assert (await async_client.get(f"{ROUTE}/errors?service=worker", headers=super_admin_headers)).json()["data"]["groups"] == []
    assert (await async_client.get(f"{ROUTE}/errors?hours=0", headers=super_admin_headers)).status_code == 422
    assert (await async_client.get(f"{ROUTE}/errors?state=bogus", headers=super_admin_headers)).status_code == 422

    fp = data["groups"][1]["fingerprint"]
    patched = await async_client.patch(f"{ROUTE}/errors/{fp}", json={"state": "resolved"}, headers=super_admin_headers)
    assert patched.status_code == 200 and patched.json()["data"]["state"] == "resolved"
    assert patched.json()["data"]["count_window"] == 5
    assert (await async_client.get(f"{ROUTE}/errors", headers=super_admin_headers)).json()["data"]["totals"]["groups"] == 2
    assert (await async_client.get(f"{ROUTE}/errors?state=all", headers=super_admin_headers)).json()["data"]["totals"]["groups"] == 3
    assert (await async_client.patch(f"{ROUTE}/errors/nope", json={"state": "open"}, headers=super_admin_headers)).status_code == 404
    assert (await async_client.patch(f"{ROUTE}/errors/{fp}", json={"state": "bogus"}, headers=super_admin_headers)).status_code == 422


async def test_test_report_sends_without_moving_the_baseline_and_needs_smtp(
    async_client, super_admin_headers, db_session, redis, smtp, monkeypatch
):
    url = f"{ROUTE}/error-report/test"
    empty = await async_client.post(url, headers=super_admin_headers)
    assert empty.json()["data"] == {"sent_to": ["support@lexilingo.me"], "groups": 0}
    assert "no new errors" in mails(smtp)[0]["Subject"]

    await err(count=3)
    await ops_errors.flush_buffer(db_session, redis, NOW)
    sent = await async_client.post(url, headers=super_admin_headers)
    assert sent.json()["data"] == {"sent_to": ["support@lexilingo.me"], "groups": 1}
    assert mails(smtp)[1]["Subject"] == "[LexiLingo] 3 errors in 1 group · last 60 min"
    group = (await db_session.execute(select(OpsErrorGroup))).scalar_one()
    assert group.reported_count == 0
    assert (await ops_errors.get_report_settings(db_session))["last_digest_at"] is None

    monkeypatch.setattr(settings, "SMTP_HOST", None)
    unavailable = await async_client.post(url, headers=super_admin_headers)
    assert unavailable.status_code == 503
    assert "SMTP_HOST" in unavailable.json()["error"]["message"]


INTERNAL = "/api/v1/internal/ops/errors:batch"


@pytest.fixture
def service_headers(monkeypatch):
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_TOKEN", "t" * 40)
    return {"X-LexiLingo-Service-Token": "t" * 40, "X-LexiLingo-Audience": settings.LEARNER_STATE_INTERNAL_AUDIENCE}


def event(**over):
    return {
        "occurred_at": "2026-11-28T10:00:00Z", "method": "POST", "route": "/api/v1/chat/{session_id}",
        "status": 500, "error_type": "TimeoutError", "location": "chat.py:stream",
        "message": "groq timeout for a@b.co", "request_id": "r-1", **over,
    }


async def test_internal_batch_rejects_a_bad_token_and_oversized_batches(async_client, service_headers, redis):
    body = {"service": "ai-service", "dropped": 0, "events": [event()]}
    assert (await async_client.post(INTERNAL, json=body)).status_code == 401
    bad = {**service_headers, "X-LexiLingo-Service-Token": "wrong"}
    assert (await async_client.post(INTERNAL, json=body, headers=bad)).status_code == 401
    too_many = {**body, "events": [event()] * 201}
    assert (await async_client.post(INTERNAL, json=too_many, headers=service_headers)).status_code == 422


async def test_internal_batch_redacts_groups_and_counts(async_client, service_headers, redis, db_session):
    body = {
        "service": "ai-service", "dropped": 3,
        "events": [event(), event(request_id="r-2"), event(status=429, error_type=None, location=None),
                   event(status=200), event(route="/health")],
    }
    response = await async_client.post(INTERNAL, json=body, headers=service_headers)
    assert response.json()["success"] is True
    assert response.json()["data"] == {"accepted": 3}

    await ops_errors.flush_buffer(db_session, redis, NOW)
    groups = {g.status_code: g for g in (await db_session.execute(select(OpsErrorGroup))).scalars()}
    assert groups[500].total_count == 2 and groups[500].service == "ai-service" and groups[500].kind == "error"
    assert groups[500].sample_message == "groq timeout for [email]"
    assert groups[429].kind == "client"


def test_a_failed_celery_task_is_recorded_under_the_worker_service(monkeypatch):
    fake = FakeRedis()

    class SyncPipeline(FakePipeline):
        def execute(self):
            for name, args, kwargs in self.calls:
                getattr(self.redis, f"_{name}")(*args, **kwargs)

    class SyncRedis:
        def pipeline(self, transaction=False):
            return SyncPipeline(fake)

    monkeypatch.setattr(ops_errors, "_sync_client", SyncRedis())
    try:
        redact(5)
    except TypeError as exc:
        ops_errors.record_error_sync(
            service="worker", kind="error", method="TASK", route="app.tasks.x.y", status=500,
            error_type=type(exc).__name__, location=location_from_exc(exc), message=str(exc),
        )

    (meta,) = metas(fake)
    assert (meta["service"], meta["method"], meta["route"], meta["location"]) == (
        "worker", "TASK", "app.tasks.x.y", "ops_errors.py:redact"
    )


async def test_reopening_a_group_lets_it_alert_again(async_client, super_admin_headers, db_session, redis):
    await err(count=3)
    await ops_errors.flush_buffer(db_session, redis, datetime.now(UTC))
    fp = (await async_client.get(f"{ROUTE}/errors", headers=super_admin_headers)).json()["data"]["groups"][0]["fingerprint"]
    key = ops_errors.ALERTED_KEY.format(fp=fp)

    await async_client.patch(f"{ROUTE}/errors/{fp}", json={"state": "muted"}, headers=super_admin_headers)
    redis.data[key] = "1"
    await async_client.patch(f"{ROUTE}/errors/{fp}", json={"state": "open"}, headers=super_admin_headers)

    assert key not in redis.data
