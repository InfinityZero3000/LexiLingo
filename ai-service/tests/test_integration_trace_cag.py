from __future__ import annotations

import hashlib
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from api.core.config import get_settings
from api.core.integration_service_auth import verify_trace_cag_service_token
from api.routes import integration_trace_cag as route
from api.services.trace_cag.external_request_cache import ExternalRequestCache
from service.tracecag_service.schemas import TraceCAGResponse


class FakeService:
    calls = 0

    async def analyze(self, _request):
        self.calls += 1
        return TraceCAGResponse(
            tutor_response="Good answer.",
            corrections=[],
            vietnamese_hint="Try the greeting.",
            action={"type": "continue"},
            metadata={"provider": "test", "model": "trace-cag", "version": "1"},
        )


@pytest.fixture
def app():
    application = FastAPI()
    application.include_router(route.router)
    service = FakeService()
    application.dependency_overrides[route.get_trace_cag_service] = lambda: service
    application.dependency_overrides[verify_trace_cag_service_token] = lambda: "ok"
    route._cache = ExternalRequestCache()
    return application, service


def payload(text: str = "hello") -> dict:
    return {
        "subject": "subject_abcdefghijklmnopqrstuvwxyz123456",
        "session_id": "session-1",
        "input_type": "answer",
        "learner_snapshot": {
            "learning_goal": "English greetings",
            "cefr_level": "A1",
            "concepts": [],
            "recent_errors": [],
        },
        "exercise_context": {
            "type": "flashcard",
            "prompt": "hello",
            "expected_answer": "xin chào",
            "concept_codes": ["vocabulary:1"],
        },
        "text": text,
    }


@pytest.mark.asyncio
async def test_success_replay_conflict_and_bounds(app):
    application, service = app
    request_id = str(uuid4())
    async with AsyncClient(transport=ASGITransport(app=application), base_url="http://test") as client:
        first = await client.post(
            "/api/v1/integrations/trace-cag/v1/analyze",
            headers={"X-Request-ID": request_id},
            json=payload(),
        )
        replay = await client.post(
            "/api/v1/integrations/trace-cag/v1/analyze",
            headers={"X-Request-ID": request_id},
            json=payload(),
        )
        conflict = await client.post(
            "/api/v1/integrations/trace-cag/v1/analyze",
            headers={"X-Request-ID": request_id},
            json=payload("different"),
        )
        oversized_text = await client.post(
            "/api/v1/integrations/trace-cag/v1/analyze",
            headers={"X-Request-ID": str(uuid4())},
            json=payload("x" * 2001),
        )

    assert first.status_code == 200
    assert first.json()["schema_version"] == "1.0"
    assert replay.json() == first.json()
    assert service.calls == 1
    assert conflict.status_code == 409
    assert oversized_text.status_code == 422


@pytest.mark.asyncio
async def test_current_previous_and_expired_service_tokens(monkeypatch):
    current = "current-secret"
    previous = "previous-secret"
    monkeypatch.setenv("TRACE_CAG_EXTERNAL_ENABLED", "true")
    monkeypatch.setenv("TRACE_CAG_SERVICE_TOKEN_HASH", hashlib.sha256(current.encode()).hexdigest())
    monkeypatch.setenv("TRACE_CAG_PREVIOUS_TOKEN_HASH", hashlib.sha256(previous.encode()).hexdigest())
    monkeypatch.setenv(
        "TRACE_CAG_PREVIOUS_TOKEN_VALID_UNTIL",
        (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat(),
    )
    get_settings.cache_clear()

    assert await verify_trace_cag_service_token(current) == current
    assert await verify_trace_cag_service_token(previous) == previous

    monkeypatch.setenv(
        "TRACE_CAG_PREVIOUS_TOKEN_VALID_UNTIL",
        (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat(),
    )
    get_settings.cache_clear()
    with pytest.raises(Exception) as error:
        await verify_trace_cag_service_token(previous)
    assert error.value.status_code == 403
