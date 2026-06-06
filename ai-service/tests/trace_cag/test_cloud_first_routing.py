import pytest
import os
from unittest.mock import AsyncMock, MagicMock, patch
from api.services.handlers.ollama_qwen_handler import OllamaQwenHandler, OllamaQwenConfig

@pytest.mark.asyncio
async def test_cloud_first_groq_success(monkeypatch):
    # Mock environment keys
    monkeypatch.setenv("TRACECAG_PREFER_CLOUD_LLM", "true")
    monkeypatch.setenv("GROQ_API_KEY", "mock-groq-key")
    monkeypatch.setenv("GEMINI_API_KEY", "")

    handler = OllamaQwenHandler()

    # Mock get_available_groq_key
    mock_get_key = AsyncMock(return_value="mock-groq-key")
    monkeypatch.setattr("api.core.groq_key_pool.get_available_groq_key", mock_get_key)
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", AsyncMock())

    # Mock httpx AsyncClient post
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "choices": [
            {
                "message": {
                    "content": "Groq response text"
                }
            }
        ],
        "usage": {
            "total_tokens": 100
        }
    }

    # We patch httpx.AsyncClient.post
    with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
        mock_post.return_value = mock_response

        # Call chat
        res = await handler.chat(message="Hello")

        assert res == "Groq response text"
        mock_post.assert_called_once()
        # Ensure it posted to Groq api url
        args, kwargs = mock_post.call_args
        assert "api.groq.com" in args[0]


@pytest.mark.asyncio
async def test_cloud_first_groq_fails_gemini_success(monkeypatch):
    monkeypatch.setenv("TRACECAG_PREFER_CLOUD_LLM", "true")
    monkeypatch.setenv("GROQ_API_KEY", "mock-groq-key")
    monkeypatch.setenv("GEMINI_API_KEY", "mock-gemini-key")

    handler = OllamaQwenHandler()

    # Mock Groq keys & record
    monkeypatch.setattr("api.core.groq_key_pool.get_available_groq_key", AsyncMock(return_value="mock-groq-key"))
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", AsyncMock())

    # Mock httpx AsyncClient post to fail for Groq (e.g. status 500)
    mock_groq_response = MagicMock()
    mock_groq_response.status_code = 500

    # Mock get_gemini_handler and chat
    mock_gemini_handler = MagicMock()
    mock_gemini_handler.chat = AsyncMock(return_value="Gemini response text")
    monkeypatch.setattr("api.services.handlers.gemini_handler.get_gemini_handler", lambda: mock_gemini_handler)

    with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
        mock_post.return_value = mock_groq_response

        res = await handler.chat(message="Hello")

        assert res == "Gemini response text"
        mock_gemini_handler.chat.assert_called_once()


@pytest.mark.asyncio
async def test_cloud_first_fallback_to_ollama(monkeypatch):
    # Groq fails, Gemini fails, fallback to local Ollama
    monkeypatch.setenv("TRACECAG_PREFER_CLOUD_LLM", "true")
    monkeypatch.setenv("GROQ_API_KEY", "mock-groq-key")
    monkeypatch.setenv("GEMINI_API_KEY", "mock-gemini-key")

    handler = OllamaQwenHandler()

    # Mock Groq to fail
    monkeypatch.setattr("api.core.groq_key_pool.get_available_groq_key", AsyncMock(return_value="mock-groq-key"))
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", AsyncMock())
    mock_groq_response = MagicMock()
    mock_groq_response.status_code = 500

    # Mock Gemini to fail (raise exception)
    mock_gemini_handler = MagicMock()
    mock_gemini_handler.chat = AsyncMock(side_effect=Exception("Gemini error"))
    monkeypatch.setattr("api.services.handlers.gemini_handler.get_gemini_handler", lambda: mock_gemini_handler)

    # Mock Ollama local load/execution success
    # First we mock load to return True
    handler.load = AsyncMock(return_value=True)
    handler.client = MagicMock()

    mock_ollama_response = MagicMock()
    mock_ollama_response.status_code = 200
    mock_ollama_response.json.return_value = {
        "message": {
            "content": "Ollama response text"
        }
    }

    # Patch AsyncClient post
    with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
        # First call is Groq (fails), second call (via handler.client.post) is Ollama
        # We need mock_post to return the 500 response for Groq, and we mock handler.client.post to return Ollama response
        mock_post.return_value = mock_groq_response
        handler.client.post = AsyncMock(return_value=mock_ollama_response)

        res = await handler.chat(message="Hello")

        assert res == "Ollama response text"
        handler.load.assert_called_once()
        handler.client.post.assert_called_once()
