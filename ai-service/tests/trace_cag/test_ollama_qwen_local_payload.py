from unittest.mock import AsyncMock, MagicMock

import pytest

from api.services.handlers.ollama_qwen_handler import (
    OllamaQwenConfig,
    OllamaQwenHandler,
)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("model", "expected_count"),
    [
        ("lexilingo-qwen3-1.7b", 1),
        ("llama3.2:3b", 0),
    ],
)
async def test_local_chat_applies_no_think_only_to_qwen3(
    monkeypatch, model, expected_count
):
    monkeypatch.setenv("TRACECAG_PREFER_CLOUD_LLM", "false")
    handler = OllamaQwenHandler(OllamaQwenConfig(model=model))
    handler.load = AsyncMock(return_value=True)
    response = MagicMock()
    response.raise_for_status.return_value = None
    response.json.return_value = {"message": {"content": "local response"}}
    handler.client = MagicMock()
    handler.client.post = AsyncMock(return_value=response)

    result = await handler.chat(
        messages=[
            {"role": "user", "content": "Explain this"},
            {"role": "assistant", "content": "Certainly"},
            {"role": "user", "content": "Give one example"},
        ],
        system_prompt="You are a tutor",
    )

    assert result == "local response"
    handler.client.post.assert_awaited_once()
    path = handler.client.post.await_args.args[0]
    payload = handler.client.post.await_args.kwargs["json"]
    assert path == "/api/chat"
    assert payload["model"] == model
    contents = [message["content"] for message in payload["messages"]]
    assert sum(content.count("/no_think") for content in contents) == expected_count
    if expected_count:
        assert contents[1].startswith("/no_think\n")
        assert "/no_think" not in contents[2]
        assert "/no_think" not in contents[3]
