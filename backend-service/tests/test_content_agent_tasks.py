import httpx
import pytest

from app.tasks.content_agent import (
    _public_error_message,
    _with_transient_retry,
)


async def test_transient_ai_calls_retry_with_a_bound(monkeypatch):
    attempts = 0

    async def operation():
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            raise httpx.ConnectError("temporary secret endpoint failure")
        return "ok"

    async def no_sleep(_delay):
        return None

    monkeypatch.setattr("app.tasks.content_agent.asyncio.sleep", no_sleep)

    assert await _with_transient_retry(operation) == "ok"
    assert attempts == 3


async def test_non_transient_ai_calls_are_not_retried(monkeypatch):
    attempts = 0
    request = httpx.Request("POST", "https://ai.internal/generate")
    response = httpx.Response(422, request=request)

    async def operation():
        nonlocal attempts
        attempts += 1
        raise httpx.HTTPStatusError(
            "payload included a private definition",
            request=request,
            response=response,
        )

    with pytest.raises(httpx.HTTPStatusError):
        await _with_transient_retry(operation)
    assert attempts == 1


def test_public_task_errors_do_not_expose_exception_payloads():
    request = httpx.Request("POST", "https://ai.internal/generate")
    response = httpx.Response(422, request=request)
    error = httpx.HTTPStatusError(
        "private uploaded definition: do not expose",
        request=request,
        response=response,
    )

    message = _public_error_message(error)

    assert message == "AI content service request failed with status 422"
    assert "private uploaded definition" not in message
