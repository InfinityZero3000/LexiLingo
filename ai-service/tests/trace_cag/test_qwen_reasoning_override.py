"""qwen writes <think> prose into `content` unless reasoning is switched off,
which breaks every JSON parser downstream. The override must reach the wire."""
import pytest

from api.services.trace_cag.llm_client import (
    _qwen_reasoning_overrides,
    _throttled_post_json,
)


def test_override_applies_to_qwen_only():
    assert _qwen_reasoning_overrides("qwen/qwen3.6-27b") == {"reasoning_effort": "none"}
    assert _qwen_reasoning_overrides("openai/gpt-oss-120b") == {}
    assert _qwen_reasoning_overrides("") == {}


@pytest.mark.asyncio
async def test_throttled_post_injects_override_for_groq(monkeypatch):
    sent = {}

    class _Resp:
        status_code = 200

    class _Client:
        async def post(self, url, headers=None, json=None, timeout=None):
            sent.update(json)
            return _Resp()

    monkeypatch.setattr(
        "api.services.trace_cag.llm_client._get_httpx_client", lambda p: _Client()
    )
    payload = {"model": "qwen/qwen3.6-27b", "messages": [], "max_tokens": 80}
    await _throttled_post_json(
        provider="groq", url="https://api.groq.com/x", payload=payload
    )
    assert sent["reasoning_effort"] == "none"
    # caller's dict must not be mutated in place
    assert "reasoning_effort" not in payload
