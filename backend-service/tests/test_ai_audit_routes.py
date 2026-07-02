import pytest
import json
from types import SimpleNamespace
from contextlib import asynccontextmanager

from httpx import ASGITransport, AsyncClient

from app.main import app
from app.core.config import settings
from app.core.dependencies import get_current_admin, get_current_user
from app.routes import ai_audit as ai_audit_route


class _FakeRedis:
    def __init__(self):
        self.store = {}

    async def lpush(self, key, value):
        self.store.setdefault(key, [])
        self.store[key].insert(0, value)

    async def ltrim(self, key, start, end):
        values = self.store.get(key, [])
        self.store[key] = values[start : end + 1]

    async def expire(self, key, _ttl):
        return True

    async def lrange(self, key, start, end):
        values = self.store.get(key, [])
        return values[start : end + 1]


@asynccontextmanager
async def _test_client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.mark.asyncio
async def test_ingest_ai_audit_event_requires_secret(monkeypatch):
    monkeypatch.setattr(settings, "AI_AUDIT_INGEST_SECRET", "my-secret")

    async with _test_client() as client:
        response = await client.post(
            "/api/v1/ai-audit/events",
            json={"request_id": "r1", "user_id": "u1", "endpoint": "lexi.chat"},
        )

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_ingest_and_list_my_ai_audit_events(monkeypatch):
    fake_redis = _FakeRedis()
    monkeypatch.setattr(settings, "AI_AUDIT_INGEST_SECRET", "my-secret")
    fake_user_id = "user-smoke-1"

    async def _fake_get_redis():
        return fake_redis

    async def _fake_current_user():
        return SimpleNamespace(id=fake_user_id)

    monkeypatch.setattr(ai_audit_route, "get_redis", _fake_get_redis)
    app.dependency_overrides[get_current_user] = _fake_current_user

    try:
        async with _test_client() as client:
            ingest = await client.post(
                "/api/v1/ai-audit/events",
                headers={"X-AI-Service-Secret": "my-secret"},
                json={
                    "request_id": "req-123",
                    "user_id": fake_user_id,
                    "endpoint": "lexi.chat",
                    "status": "success",
                },
            )
            assert ingest.status_code == 200
            assert ingest.json().get("success") is True

            me = await client.get("/api/v1/ai-audit/events/me")
            assert me.status_code == 200
            payload = me.json()
            assert payload["total"] >= 1
            assert payload["events"][0]["request_id"] == "req-123"
    finally:
        app.dependency_overrides.pop(get_current_user, None)


@pytest.mark.asyncio
async def test_admin_quality_summary_aggregates_ai_audit_events(monkeypatch):
    fake_redis = _FakeRedis()
    fake_redis.store["ai:audit:all"] = [
        json.dumps({
            "request_id": "req-stt",
            "user_id": "u1",
            "endpoint": "stt.transcribe",
            "status": "failed",
            "latency_ms": 820,
            "error": "primary failed",
        }),
        json.dumps({
            "request_id": "req-lexi",
            "user_id": "u2",
            "endpoint": "lexi.chat",
            "status": "success",
            "latency_ms": 240,
            "metadata": {"pipeline_steps": ["stt_complete", "tts_failed"]},
        }),
        json.dumps({
            "request_id": "req-correction",
            "user_id": "u3",
            "endpoint": "writing.correction",
            "status": "success",
            "duration_ms": 120,
            "correction_score": 0.86,
        }),
    ]

    async def _fake_get_redis():
        return fake_redis

    async def _fake_current_admin():
        return SimpleNamespace(id="admin-1")

    monkeypatch.setattr(ai_audit_route, "get_redis", _fake_get_redis)
    app.dependency_overrides[get_current_admin] = _fake_current_admin

    try:
        async with _test_client() as client:
            response = await client.get("/api/v1/ai-audit/quality-summary?limit=10")

        assert response.status_code == 200
        payload = response.json()
        summary = payload["summary"]
        assert payload["source"] == "ai:audit:all"
        assert summary["total_events"] == 3
        assert summary["failure_count"] == 1
        assert summary["stt"]["failures"] == 1
        assert summary["tts"]["failures"] == 1
        assert summary["correction"]["average_score"] == 0.86
        assert summary["endpoint_breakdown"][0]["total"] == 1
    finally:
        app.dependency_overrides.pop(get_current_admin, None)
