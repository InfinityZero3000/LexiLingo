import pytest

from api.core import audit_emitter


@pytest.mark.asyncio
async def test_emit_ai_audit_event_noop_without_url(monkeypatch):
    monkeypatch.setenv("BACKEND_AUDIT_INGEST_URL", "")

    # Should be a no-op without raising.
    await audit_emitter.emit_ai_audit_event({"request_id": "r1"})


@pytest.mark.asyncio
async def test_emit_ai_audit_event_posts_with_secret(monkeypatch):
    calls = {}

    class _Resp:
        status_code = 200
        text = "ok"

    class _Client:
        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            calls["url"] = url
            calls["json"] = json
            calls["headers"] = headers
            return _Resp()

    monkeypatch.setenv("BACKEND_AUDIT_INGEST_URL", "http://localhost:8000/api/v1/ai-audit/events")
    monkeypatch.setenv("AI_AUDIT_INGEST_SECRET", "secret-123")
    monkeypatch.setattr(audit_emitter.httpx, "AsyncClient", lambda timeout: _Client())

    payload = {"request_id": "r2", "endpoint": "lexi.chat"}
    await audit_emitter.emit_ai_audit_event(payload)

    assert calls["url"].endswith("/api/v1/ai-audit/events")
    assert calls["json"] == payload
    assert calls["headers"]["X-AI-Service-Secret"] == "secret-123"
