"""Sensitive routes must fail closed (503) when the distributed rate
limiter is unreachable, instead of silently degrading to a per-process
in-memory counter that N worker replicas would each apply independently.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from starlette.requests import Request

from app.core.middleware import (
    RateLimitMiddleware,
    _is_sensitive_route,
    _RedisUnavailable,
)


def test_is_sensitive_route_exact_matches():
    assert _is_sensitive_route("POST", "/api/v1/auth/login")
    assert _is_sensitive_route("POST", "/api/v1/xp/award")
    assert not _is_sensitive_route("GET", "/api/v1/auth/login")
    assert not _is_sensitive_route("POST", "/api/v1/courses")


def test_is_sensitive_route_prefix_matches():
    assert _is_sensitive_route("POST", "/api/v1/challenges/daily/abc123/claim")
    assert _is_sensitive_route("GET", "/api/v1/integrations/courses")
    assert not _is_sensitive_route("GET", "/api/v1/challenges/daily/abc123/claim")


def _make_request(method: str, path: str) -> Request:
    scope = {
        "type": "http",
        "method": method,
        "path": path,
        "headers": [],
        "client": ("1.2.3.4", 12345),
        "query_string": b"",
    }
    return Request(scope)


async def _call_next(request):
    from starlette.responses import PlainTextResponse
    return PlainTextResponse("ok")


@pytest.mark.asyncio
async def test_redis_check_and_increment_raises_instead_of_failing_open():
    """A pipeline error must be visible to the caller, not swallowed as 'allowed'."""
    middleware = RateLimitMiddleware(app=AsyncMock())
    broken_redis = MagicMock()
    broken_pipe = MagicMock()
    broken_pipe.incr = MagicMock()
    broken_pipe.ttl = MagicMock()
    broken_pipe.execute = AsyncMock(side_effect=ConnectionError("redis down"))
    broken_redis.pipeline.return_value = broken_pipe

    with pytest.raises(_RedisUnavailable):
        await middleware._redis_check_and_increment(broken_redis, "k", 10, 60)


@pytest.mark.asyncio
async def test_sensitive_route_fails_closed_when_redis_unavailable():
    middleware = RateLimitMiddleware(app=AsyncMock())
    middleware.__class__._testing = False
    try:
        request = _make_request("POST", "/api/v1/auth/login")
        with patch("app.core.redis.RedisClient.get_instance", AsyncMock(return_value=None)):
            response = await middleware.dispatch(request, _call_next)
        assert response.status_code == 503
        assert response.headers.get("Retry-After") is not None
    finally:
        middleware.__class__._testing = True


@pytest.mark.asyncio
async def test_ordinary_route_falls_back_to_memory_when_redis_unavailable():
    middleware = RateLimitMiddleware(app=AsyncMock())
    middleware.__class__._testing = False
    try:
        request = _make_request("GET", "/api/v1/courses")
        with patch("app.core.redis.RedisClient.get_instance", AsyncMock(return_value=None)):
            response = await middleware.dispatch(request, _call_next)
        assert response.status_code == 200
    finally:
        middleware.__class__._testing = True


if __name__ == "__main__":
    import asyncio

    test_is_sensitive_route_exact_matches()
    test_is_sensitive_route_prefix_matches()
    asyncio.run(test_redis_check_and_increment_raises_instead_of_failing_open())
    asyncio.run(test_sensitive_route_fails_closed_when_redis_unavailable())
    asyncio.run(test_ordinary_route_falls_back_to_memory_when_redis_unavailable())
    print("All rate-limit fail-closed self-checks passed.")
