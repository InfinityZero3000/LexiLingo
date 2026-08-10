"""Tests for the best-effort ai-service error-diagnosis client."""

from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.clients.ai_service_client import diagnose_error


def _mock_client(response=None, *, side_effect=None):
    client = MagicMock()
    client.post = AsyncMock(return_value=response, side_effect=side_effect)
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=None)
    return client


@pytest.mark.asyncio
async def test_diagnose_error_returns_primary_type(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "secret-key")
    response = MagicMock()
    response.json.return_value = {"errors": [{"type": "past_tense"}]}
    client = _mock_client(response)

    with (
        patch(
            "app.clients.ai_service_client.httpx.AsyncClient",
            return_value=client,
        ) as client_cls,
        patch(
            "app.clients.ai_service_client.settings.AI_SERVICE_URL",
            "http://ai.test/api/v1",
        ),
    ):
        result = await diagnose_error("Yesterday I go", level="B1")

    assert result == "past_tense"
    client.post.assert_awaited_once_with(
        "http://ai.test/api/v1/internal/diagnose",
        headers={"X-Admin-Api-Key": "secret-key"},
        json={"text": "Yesterday I go", "level": "B1"},
    )
    assert client_cls.call_args.kwargs["timeout"].connect == 5.0
    response.raise_for_status.assert_called_once_with()


@pytest.mark.asyncio
async def test_diagnose_error_returns_none_for_empty_errors(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "secret-key")
    response = MagicMock()
    response.json.return_value = {"errors": []}
    client = _mock_client(response)

    with patch("app.clients.ai_service_client.httpx.AsyncClient", return_value=client):
        result = await diagnose_error("This is correct", level=None)

    assert result is None


@pytest.mark.asyncio
async def test_diagnose_error_returns_none_on_network_failure(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "secret-key")
    client = _mock_client(side_effect=httpx.ConnectError("ai-service unavailable"))

    with patch("app.clients.ai_service_client.httpx.AsyncClient", return_value=client):
        result = await diagnose_error("I goes home", level="A2")

    assert result is None
