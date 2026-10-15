"""is_premium must fail OPEN to "free tier" on any error — a missed
entitlement check costs one chat message's cap, never blocks the chat."""

import httpx
import pytest

from api.clients import entitlement_client


class _FakeResponse:
    def __init__(self, status_code: int, payload: dict):
        self.status_code = status_code
        self._payload = payload

    def json(self):
        return self._payload


class _FakeAsyncClient:
    def __init__(self, response=None, error: Exception | None = None):
        self._response = response
        self._error = error

    async def get(self, *args, **kwargs):
        if self._error is not None:
            raise self._error
        return self._response


@pytest.fixture(autouse=True)
def _reset_client(monkeypatch):
    # is_premium reuses one pooled client across calls — reset it so each
    # test's fake client is the one actually hit, not a previous test's.
    monkeypatch.setattr(entitlement_client, "_client", None)


@pytest.mark.asyncio
async def test_is_premium_true_on_active_entitlement(monkeypatch):
    monkeypatch.setattr(entitlement_client.settings, "LEARNER_STATE_INTERNAL_TOKEN", "secret")
    monkeypatch.setattr(
        entitlement_client,
        "_get_client",
        lambda: _FakeAsyncClient(response=_FakeResponse(200, {"active": True})),
    )

    assert await entitlement_client.is_premium("user-1") is True


@pytest.mark.asyncio
async def test_is_premium_false_when_not_active(monkeypatch):
    monkeypatch.setattr(entitlement_client.settings, "LEARNER_STATE_INTERNAL_TOKEN", "secret")
    monkeypatch.setattr(
        entitlement_client,
        "_get_client",
        lambda: _FakeAsyncClient(response=_FakeResponse(200, {"active": False})),
    )

    assert await entitlement_client.is_premium("user-1") is False


@pytest.mark.asyncio
async def test_is_premium_fails_open_on_transport_error(monkeypatch):
    monkeypatch.setattr(entitlement_client.settings, "LEARNER_STATE_INTERNAL_TOKEN", "secret")
    monkeypatch.setattr(
        entitlement_client,
        "_get_client",
        lambda: _FakeAsyncClient(error=httpx.ConnectTimeout("boom")),
    )

    assert await entitlement_client.is_premium("user-1") is False


@pytest.mark.asyncio
async def test_is_premium_fails_open_on_http_error_status(monkeypatch):
    monkeypatch.setattr(entitlement_client.settings, "LEARNER_STATE_INTERNAL_TOKEN", "secret")
    monkeypatch.setattr(
        entitlement_client,
        "_get_client",
        lambda: _FakeAsyncClient(response=_FakeResponse(401, {})),
    )

    assert await entitlement_client.is_premium("user-1") is False


@pytest.mark.asyncio
async def test_is_premium_false_when_no_internal_token_configured(monkeypatch):
    monkeypatch.setattr(entitlement_client.settings, "LEARNER_STATE_INTERNAL_TOKEN", "")

    assert await entitlement_client.is_premium("user-1") is False
