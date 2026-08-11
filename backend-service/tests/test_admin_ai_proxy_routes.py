"""Tests for the admin AI proxy routes.

Guards against regressing the fix for the leaked client-side AI admin key:
these routes must stay behind JWT+role auth, and must inject the
X-Admin-Key server-side rather than accept one from the caller.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.routing import APIRoute

from app.core.dependencies import get_current_admin, get_current_super_admin
from app.routes import admin_ai_proxy

router = admin_ai_proxy.router


def _dependency_calls(route: APIRoute) -> set:
    calls = set()
    pending = list(route.dependant.dependencies)
    while pending:
        dep = pending.pop()
        if dep.call is not None:
            calls.add(dep.call)
        pending.extend(dep.dependencies)
    return calls


def test_topics_routes_require_admin():
    topics_routes = [r for r in router.routes if isinstance(r, APIRoute) and r.path.endswith("/topics")]
    assert topics_routes, "No /topics routes found — router might not be wired"
    for route in topics_routes:
        assert get_current_admin in _dependency_calls(route), (
            f"{route.path} is missing get_current_admin dependency"
        )


def test_config_routes_require_super_admin():
    config_routes = [r for r in router.routes if isinstance(r, APIRoute) and r.path.endswith("/config")]
    assert config_routes, "No /config routes found — router might not be wired"
    for route in config_routes:
        assert get_current_super_admin in _dependency_calls(route), (
            f"{route.path} is missing get_current_super_admin dependency"
        )


@pytest.mark.asyncio
async def test_forward_injects_admin_key_server_side(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "server-secret")

    response = MagicMock()
    response.status_code = 200
    response.json.return_value = {"success": True, "data": {"topics": [], "total": 0}}

    http = AsyncMock()
    http.request = AsyncMock(return_value=response)

    with patch("app.routes.admin_ai_proxy.httpx.AsyncClient") as client_cls:
        client_cls.return_value.__aenter__ = AsyncMock(return_value=http)
        client_cls.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await admin_ai_proxy._forward("GET", "/topics", params={"limit": 200})

    assert result["data"]["total"] == 0
    http.request.assert_awaited_once()
    assert http.request.call_args.kwargs["headers"] == {"X-Admin-Key": "server-secret"}
    # The caller never gets to supply/override this header.
    assert "headers" not in http.request.call_args.args


@pytest.mark.asyncio
async def test_forward_fails_closed_when_key_not_configured(monkeypatch):
    monkeypatch.delenv("AI_ADMIN_API_KEY", raising=False)

    with pytest.raises(Exception) as exc_info:
        await admin_ai_proxy._forward("GET", "/config")

    assert getattr(exc_info.value, "status_code", None) == 503
