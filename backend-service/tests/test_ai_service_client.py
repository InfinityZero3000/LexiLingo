from unittest.mock import AsyncMock, MagicMock

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

    result = await AIServiceClient(
        base_url="http://ai.test/api/v1",
        client=http,
    ).translate_word(word="hello", lang="vi")

    assert result["translation"] == "xin chao"
    http.get.assert_awaited_once()
    assert http.get.call_args.kwargs["headers"] == {"X-Admin-Key": "secret"}
