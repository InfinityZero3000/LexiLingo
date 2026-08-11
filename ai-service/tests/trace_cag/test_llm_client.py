import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest

from api.services.trace_cag import llm_client


def test_provider_client_enables_http2():
    llm_client._HTTPX_CLIENTS.clear()
    with patch("httpx.AsyncClient") as client:
        llm_client._get_httpx_client("groq")
    assert client.call_args.kwargs["http2"] is True
    llm_client._HTTPX_CLIENTS.clear()


@pytest.mark.asyncio
async def test_lock_contention_does_not_consume_http_retry(monkeypatch):
    async def post(*args, **kwargs):
        await asyncio.sleep(0.01)
        return SimpleNamespace(status_code=200)

    provider = "contention-test"
    monkeypatch.setenv("TRACECAG_CONTENTION-TEST_RPM", "600000")
    monkeypatch.setattr(llm_client, "_get_httpx_client", lambda _: SimpleNamespace(post=AsyncMock(side_effect=post)))
    llm_client._PROVIDER_NEXT_REQUEST_AT.pop(provider, None)
    llm_client._PROVIDER_QUEUE_LOCKS.pop(provider, None)

    responses = await asyncio.gather(*[
        llm_client._throttled_post_json(
            provider=provider,
            url="https://provider.invalid",
            payload={},
            max_retries=1,
        )
        for _ in range(2)
    ])

    assert [response.status_code for response in responses] == [200, 200]


@pytest.mark.asyncio
async def test_groq_quota_cooldown_is_scoped_to_one_key(monkeypatch):
    quota = SimpleNamespace(
        status_code=429,
        headers={},
        text="tokens per day quota",
    )
    ok = SimpleNamespace(status_code=200)
    post = AsyncMock(side_effect=[quota, ok])
    monkeypatch.setattr(llm_client, "_get_httpx_client", lambda _: SimpleNamespace(post=post))

    first = await llm_client._throttled_post_json(
        provider="groq", url="https://provider.invalid", payload={},
        headers={"Authorization": "Bearer key-one"}, max_retries=1,
    )
    second = await llm_client._throttled_post_json(
        provider="groq", url="https://provider.invalid", payload={},
        headers={"Authorization": "Bearer key-two"}, max_retries=1,
    )

    assert first.status_code == 429
    assert second.status_code == 200
    assert post.await_count == 2
