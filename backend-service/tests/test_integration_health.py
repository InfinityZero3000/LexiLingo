"""Guards for app/services/integration_health.py.

The point of this module is to distinguish a credential that is present from
one that still works — a revoked key passes every truthiness guard in the
codebase and fails only when a learner triggers the feature.
"""

import asyncio
from types import SimpleNamespace

import pytest

from app.services import integration_health as ih


class _Resp(SimpleNamespace):
    pass


def _client_returning(status):
    async def call(_client, _key):
        return _Resp(status_code=status, text="body")
    return call


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


@pytest.mark.asyncio
async def test_missing_key_is_not_configured(monkeypatch):
    monkeypatch.delenv("SOME_KEY", raising=False)
    r = await ih._probe(None, "x", "SOME_KEY", "feat", _client_returning(200))
    assert r["state"] == "not_configured"


@pytest.mark.asyncio
async def test_live_key_is_ok(monkeypatch):
    monkeypatch.setenv("SOME_KEY", "abc")
    r = await ih._probe(None, "x", "SOME_KEY", "feat", _client_returning(200))
    assert r["state"] == "ok"


@pytest.mark.asyncio
async def test_revoked_key_is_dead_not_ok(monkeypatch):
    """The case that mattered: key present, provider rejects it."""
    monkeypatch.setenv("SOME_KEY", "AIzaSyRevoked")
    r = await ih._probe(None, "x", "SOME_KEY", "content-agent", _client_returning(400))
    assert r["state"] == "dead"
    assert "400" in r["detail"]
    assert r["feature"] == "content-agent"


@pytest.mark.asyncio
async def test_rate_limited_key_counts_as_alive(monkeypatch):
    """429 means the credential is valid and merely throttled."""
    monkeypatch.setenv("SOME_KEY", "abc")
    r = await ih._probe(None, "x", "SOME_KEY", "feat", _client_returning(429))
    assert r["state"] == "ok"


@pytest.mark.asyncio
async def test_network_failure_is_unreachable_not_dead(monkeypatch):
    monkeypatch.setenv("SOME_KEY", "abc")

    async def boom(_c, _k):
        raise ConnectionError("dns")

    r = await ih._probe(None, "x", "SOME_KEY", "feat", boom)
    assert r["state"] == "unreachable"


@pytest.mark.asyncio
async def test_partially_dead_groq_pool_is_degraded(monkeypatch):
    """Losing headroom must not read as healthy."""
    monkeypatch.setenv("GROQ_API_KEYS", "k1,k2,k3")
    monkeypatch.setenv("GROQ_MODEL", "llama-3.1-8b-instant")

    class C:
        async def post(self, _url, headers=None, json=None):
            ok = headers["Authorization"].endswith("k1")
            return _Resp(status_code=200 if ok else 401, text="")

    r = await ih._groq_pool(C())
    assert r["state"] == "degraded"
    assert "1/3" in r["detail"]


@pytest.mark.asyncio
async def test_healthy_flag_is_false_when_anything_is_dead(monkeypatch):
    async def fake(_client, name, env, feature, call, **kw):
        return ih._result(name, env, feature, "dead" if name == "gemini" else "ok")

    monkeypatch.setattr(ih, "_probe", fake)
    monkeypatch.setattr(ih, "_groq_pool", lambda c: _ok_groq())

    async def _ok_groq():
        return ih._result("groq", "GROQ_API_KEYS", "chat", "ok")

    out = await ih.check_all()
    assert out["healthy"] is False
    assert out["broken"] == 1
