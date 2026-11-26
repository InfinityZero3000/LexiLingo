"""Tests for the admin AI proxy routes.

Guards against regressing the fix for the leaked client-side AI admin key:
these routes must stay behind JWT+role auth, and must inject the
X-Admin-Key server-side rather than accept one from the caller.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi.routing import APIRoute

from app.core.dependencies import get_current_admin
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


def test_there_is_no_config_proxy_for_settings_nothing_reads():
    assert [r.path for r in router.routes if isinstance(r, APIRoute) and r.path.endswith("/config")] == []


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
        await admin_ai_proxy._forward("GET", "/topics")

    assert getattr(exc_info.value, "status_code", None) == 503


def test_every_topic_route_the_admin_ui_calls_exists_behind_admin_auth():
    wanted = {
        ("GET", "/admin/ai-proxy/topics/{story_id}"),
        ("POST", "/admin/ai-proxy/topics/suggest-meta"),
        ("POST", "/admin/ai-proxy/topics/draft"),
    }
    found = {}
    for route in router.routes:
        if isinstance(route, APIRoute):
            for method in route.methods:
                found[(method, route.path)] = route
    assert wanted <= set(found)
    for key in wanted:
        assert get_current_admin in _dependency_calls(found[key]), f"{key} is not behind admin auth"


@pytest.mark.asyncio
async def test_draft_waits_longer_than_other_forwards_and_ids_are_encoded(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "server-secret")
    response = MagicMock()
    response.status_code = 200
    response.json.return_value = {"success": True}
    http = AsyncMock()
    http.request = AsyncMock(return_value=response)

    with patch("app.routes.admin_ai_proxy.httpx.AsyncClient") as client_cls:
        client_cls.return_value.__aenter__ = AsyncMock(return_value=http)
        client_cls.return_value.__aexit__ = AsyncMock(return_value=False)
        await admin_ai_proxy.draft_topic({"title": "x"}, _admin=MagicMock())
        draft_timeout = client_cls.call_args.kwargs["timeout"]
        await admin_ai_proxy.get_topic("a/b c", _admin=MagicMock())
        plain_timeout = client_cls.call_args.kwargs["timeout"]

    assert draft_timeout.read >= 60
    assert plain_timeout.read < draft_timeout.read
    assert http.request.await_args.args[1].endswith("/admin/topics/a%2Fb%20c")


@pytest.mark.asyncio
async def test_monitoring_forwards_to_the_ai_router_not_the_admin_router(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "server-secret")
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"turns": 3})

    real_client = httpx.AsyncClient
    monkeypatch.setattr(
        admin_ai_proxy.httpx, "AsyncClient",
        lambda **kw: real_client(transport=httpx.MockTransport(handler), **kw),
    )

    await admin_ai_proxy.chat_monitoring(window="7d", _admin=MagicMock())
    await admin_ai_proxy.llm_key_monitoring(_admin=MagicMock())
    await admin_ai_proxy.observation_spool_monitoring(_admin=MagicMock())
    await admin_ai_proxy.dashboard_monitoring(_admin=MagicMock())

    chat, keys, spool, dashboard = seen
    assert dashboard.url.path.endswith("/ai/monitoring/dashboard")
    assert chat.url.path.endswith("/ai/monitoring/chat") and chat.url.params["window"] == "7d"
    assert keys.url.path.endswith("/ai/monitoring/llm-keys")
    assert spool.url.path.endswith("/ai/monitoring/observation-spool")
    assert all(r.headers["X-Admin-Key"] == "server-secret" for r in seen)
    assert not any("/admin/monitoring" in r.url.path for r in seen)


def test_monitoring_routes_need_the_ops_permission():
    routes = [r for r in router.routes if isinstance(r, APIRoute) and "/monitoring/" in r.path]
    assert len(routes) == 4
    for route in routes:
        assert get_current_admin in _dependency_calls(route)
