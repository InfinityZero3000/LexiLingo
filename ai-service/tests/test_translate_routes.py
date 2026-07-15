"""
Tests for ai-service /api/v1/ai/translate route.

Covers:
- Groq primary path (happy path)
- Ollama fallback when Groq returns None
- Graceful empty result when both fail
- JSON fence stripping (_parse_llm_json)
- Query param wiring (word, lang, context)
"""

import json
import pytest
from unittest.mock import AsyncMock, MagicMock, patch


# ── helpers ──────────────────────────────────────────────────────────────────

class TestParseLlmJson:
    def _parse(self, raw: str) -> dict:
        from api.routes.translate import _parse_llm_json
        return _parse_llm_json(raw)

    def test_plain_json(self):
        raw = '{"translation":"chạy","phonetic":"/rʌn/","part_of_speech":"verb"}'
        result = self._parse(raw)
        assert result["translation"] == "chạy"
        assert result["phonetic"] == "/rʌn/"
        assert result["part_of_speech"] == "verb"

    def test_strips_json_fence(self):
        raw = '```json\n{"translation":"công ty","phonetic":"","part_of_speech":"noun"}\n```'
        result = self._parse(raw)
        assert result["translation"] == "công ty"

    def test_strips_plain_fence(self):
        raw = '```\n{"translation":"học","phonetic":"/lɜːn/","part_of_speech":"verb"}\n```'
        result = self._parse(raw)
        assert result["translation"] == "học"

    def test_json_embedded_in_text(self):
        raw = 'Here is the result: {"translation":"chạy","phonetic":"","part_of_speech":"verb"} done.'
        result = self._parse(raw)
        assert result["translation"] == "chạy"

    def test_returns_empty_on_no_json(self):
        result = self._parse("Sorry, I cannot help with that.")
        assert result == {}

    def test_returns_empty_on_invalid_json(self):
        result = self._parse("{bad json}")
        assert result == {}


# ── route integration tests ───────────────────────────────────────────────────

@pytest.fixture
async def ai_client():
    """Async test client for ai-service app with mocked DB/Redis."""
    from httpx import AsyncClient, ASGITransport

    with patch("api.main.build_groq_key_pool", return_value=None), \
         patch("api.main._init_mongo", new_callable=AsyncMock), \
         patch("api.core.redis_client.get_redis_client", return_value=AsyncMock()):
        from api.main import app
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://localhost") as client:
            yield client


class TestTranslateRoute:

    @pytest.mark.asyncio
    async def test_route_requires_admin_key(self, monkeypatch):
        """HTTP route is server-to-server only."""
        from fastapi import FastAPI
        from httpx import ASGITransport, AsyncClient

        from api.routes.translate import router

        monkeypatch.setenv("AI_ADMIN_API_KEY", "secret")
        app = FastAPI()
        app.include_router(router, prefix="/api/v1/ai")

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/api/v1/ai/translate?word=run")

        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_groq_primary_path(self):
        """Happy path: Groq returns valid JSON → used as translation."""
        groq_payload = {
            "choices": [{"message": {"content": '{"translation":"điều hành","phonetic":"/rʌn/","part_of_speech":"verb"}'}}],
            "usage": {"total_tokens": 95},
        }

        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = groq_payload

        with patch("api.core.groq_key_pool.get_available_groq_key", new_callable=AsyncMock, return_value="gsk_test"), \
             patch("api.core.groq_key_pool.record_groq_key_usage", new_callable=AsyncMock), \
             patch("api.services.trace_cag.llm_client._throttled_post_json", new_callable=AsyncMock, return_value=mock_resp):

            from api.routes.translate import translate_word
            result = await translate_word(word="run", lang="vi", context="She wants to run a company")

        assert result["word"] == "run"
        assert result["translation"] == "điều hành"
        assert result["phonetic"] == "/rʌn/"
        assert result["part_of_speech"] == "verb"

    @pytest.mark.asyncio
    async def test_ollama_fallback_when_groq_unavailable(self):
        """Groq pool exhausted → Ollama fallback is used."""
        ollama_raw = '{"translation":"chạy","phonetic":"/rʌn/","part_of_speech":"verb"}'

        mock_ollama = AsyncMock()
        mock_ollama.health_check = AsyncMock(return_value=True)
        mock_ollama.chat = AsyncMock(return_value=ollama_raw)

        with patch("api.core.groq_key_pool.get_available_groq_key", new_callable=AsyncMock, return_value=None), \
             patch("api.services.ollama_service.get_ollama_service", return_value=mock_ollama):

            from api.routes.translate import translate_word
            result = await translate_word(word="run", lang="vi", context="")

        assert result["translation"] == "chạy"
        assert result["word"] == "run"

    @pytest.mark.asyncio
    async def test_empty_result_when_both_fail(self):
        """All backends fail → empty fields returned, no exception raised."""
        with patch("api.core.groq_key_pool.get_available_groq_key", new_callable=AsyncMock, return_value=None), \
             patch("api.services.ollama_service.get_ollama_service", side_effect=Exception("Ollama down")):

            from api.routes.translate import translate_word
            result = await translate_word(word="run", lang="vi", context="")

        assert result["word"] == "run"
        assert result["translation"] == ""
        assert result["phonetic"] == ""
        assert result["part_of_speech"] == ""

    @pytest.mark.asyncio
    async def test_word_lowercased(self):
        """Word is normalised to lowercase before lookup."""
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "choices": [{"message": {"content": '{"translation":"chạy","phonetic":"","part_of_speech":"verb"}'}}],
            "usage": {"total_tokens": 80},
        }

        with patch("api.core.groq_key_pool.get_available_groq_key", new_callable=AsyncMock, return_value="gsk_test"), \
             patch("api.core.groq_key_pool.record_groq_key_usage", new_callable=AsyncMock), \
             patch("api.services.trace_cag.llm_client._throttled_post_json", new_callable=AsyncMock, return_value=mock_resp):

            from api.routes.translate import translate_word
            result = await translate_word(word="RUN", lang="vi", context="")

        assert result["word"] == "run"

    @pytest.mark.asyncio
    async def test_ollama_skipped_when_unhealthy(self):
        """Ollama health_check returns False → graceful empty, no crash."""
        mock_ollama = AsyncMock()
        mock_ollama.health_check = AsyncMock(return_value=False)

        with patch("api.core.groq_key_pool.get_available_groq_key", new_callable=AsyncMock, return_value=None), \
             patch("api.services.ollama_service.get_ollama_service", return_value=mock_ollama):

            from api.routes.translate import translate_word
            result = await translate_word(word="bank", lang="vi", context="")

        assert result["translation"] == ""
        mock_ollama.chat.assert_not_called()
