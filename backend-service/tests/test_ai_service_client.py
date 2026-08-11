from unittest.mock import AsyncMock, MagicMock, patch

import pytest


@pytest.mark.asyncio
async def test_translate_word_sends_admin_key(monkeypatch):
    from app.clients.ai_service_client import AIServiceClient

    monkeypatch.setenv("AI_ADMIN_API_KEY", "secret")

    response = MagicMock()
    response.status_code = 200
    response.json.return_value = {"translation": "xin chao"}

    http = AsyncMock()
    http.get = AsyncMock(return_value=response)

    with patch("app.clients.ai_service_client.httpx.AsyncClient") as client_cls:
        client_cls.return_value.__aenter__ = AsyncMock(return_value=http)
        client_cls.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await AIServiceClient(base_url="http://ai.test/api/v1").translate_word(
            word="hello",
            lang="vi",
        )

    assert result["translation"] == "xin chao"
    http.get.assert_awaited_once()
    assert http.get.call_args.kwargs["headers"] == {"X-Admin-Key": "secret"}
