"""ai-service error reporter: capture, buffering and delivery to backend-service."""

from __future__ import annotations

import os
from unittest.mock import AsyncMock, patch

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from starlette.testclient import TestClient

from api.core.config import settings
from api.services import ops_error_reporter as reporter

URL = "http://backend.test/api/v1/internal"
TOKEN = "t" * 40


@pytest.fixture(autouse=True)
def _clean(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "LEARNER_STATE_API_URL", URL)
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_TOKEN", TOKEN)
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_AUDIENCE", "lexilingo-backend")
    reporter.reset()
    yield
    reporter.reset()


def _app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(reporter.OpsErrorMiddleware)
    app.add_exception_handler(Exception, reporter.unhandled_exception_handler)

    @app.get("/items/{item_id}")
    async def item(item_id: int):
        if item_id == 503:
            raise HTTPException(503, "upstream down for a@b.co")
        return {"id": item_id}

    @app.get("/boom")
    async def boom():
        raise ValueError("bad token Bearer abc.def and a@b.co")

    @app.get("/health")
    async def health():
        raise HTTPException(503, "unhealthy")

    return app


def test_unhandled_exception_returns_json_500_and_records_once(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(reporter, "_API_DIR", os.path.dirname(__file__) + os.sep)
    client = TestClient(_app(), raise_server_exceptions=False)

    response = client.get("/boom")

    assert response.status_code == 500
    assert response.json() == {"detail": "Internal server error"}
    assert len(reporter._buffer) == 1
    event = reporter._buffer[0]
    assert event["route"] == "/boom"
    assert event["status"] == 500
    assert event["error_type"] == "ValueError"
    assert event["location"] == "test_ops_error_reporter.py:boom"
    assert "a@b.co" not in event["message"] and "abc.def" not in event["message"]


def test_http_errors_use_the_route_template() -> None:
    client = TestClient(_app(), raise_server_exceptions=False)

    client.get("/items/503")
    client.get("/nope/123")

    first, second = list(reporter._buffer)
    assert (first["route"], first["status"], first["method"]) == ("/items/{item_id}", 503, "GET")
    assert (second["route"], second["status"]) == (reporter.UNMATCHED_ROUTE, 404)


def test_health_and_successful_requests_are_not_recorded() -> None:
    client = TestClient(_app(), raise_server_exceptions=False)

    client.get("/health")
    client.get("/items/1")

    assert len(reporter._buffer) == 0


def test_overflow_counts_dropped_events() -> None:
    for _ in range(reporter.BUFFER_SIZE + 3):
        reporter._enqueue({"status": 500})

    assert len(reporter._buffer) == reporter.BUFFER_SIZE
    assert reporter._dropped == 3


@pytest.mark.asyncio
async def test_flush_posts_batch_with_service_headers() -> None:
    for i in range(205):
        reporter._enqueue({"status": 500, "n": i})
    reporter._dropped = 2

    with patch.object(httpx.AsyncClient, "post", autospec=True) as post:
        post.return_value = httpx.Response(200, json={"success": True})
        async with httpx.AsyncClient() as client:
            await reporter.flush_once(client)

    _, url = post.call_args.args
    assert url == f"{URL}/ops/errors:batch"
    assert post.call_args.kwargs["headers"] == {
        "X-LexiLingo-Service-Token": TOKEN,
        "X-LexiLingo-Audience": "lexilingo-backend",
    }
    body = post.call_args.kwargs["json"]
    assert body["service"] == "ai-service"
    assert body["dropped"] == 2
    assert len(body["events"]) == 200
    assert len(reporter._buffer) == 5
    assert reporter._dropped == 0


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "outcome", [httpx.ConnectError("down"), httpx.Response(503), httpx.Response(404)]
)
async def test_backend_trouble_keeps_events_without_raising(outcome) -> None:
    reporter._enqueue({"status": 500})
    reporter._enqueue({"status": 502})

    with patch.object(httpx.AsyncClient, "post", autospec=True) as post:
        if isinstance(outcome, Exception):
            post.side_effect = outcome
        else:
            post.return_value = outcome
        async with httpx.AsyncClient() as client:
            await reporter.flush_once(client)

    assert [e["status"] for e in reporter._buffer] == [500, 502]


@pytest.mark.asyncio
@pytest.mark.parametrize("status", [401, 403, 422])
async def test_rejected_batch_is_dropped(status: int) -> None:
    reporter._enqueue({"status": 500})

    with patch.object(httpx.AsyncClient, "post", autospec=True) as post:
        post.return_value = httpx.Response(status)
        async with httpx.AsyncClient() as client:
            await reporter.flush_once(client)

    assert len(reporter._buffer) == 0


@pytest.mark.asyncio
async def test_start_is_disabled_without_a_token(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_TOKEN", "")

    assert reporter.start_ops_error_reporter() is False
    reporter._enqueue({"status": 500})
    assert len(reporter._buffer) == 0


@pytest.mark.asyncio
async def test_flusher_task_starts_and_cancels_cleanly() -> None:
    with patch.object(reporter, "flush_once", autospec=True, side_effect=AsyncMock()):
        assert reporter.start_ops_error_reporter(interval=0.01) is True
        await reporter.stop_ops_error_reporter()

    assert reporter._task is None
