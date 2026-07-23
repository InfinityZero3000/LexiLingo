import asyncio
from unittest.mock import AsyncMock

import pytest

from api.core import groq_key_pool


@pytest.mark.asyncio
async def test_redis_pool_exhaustion_does_not_bypass_with_raw_key(monkeypatch):
    pool = AsyncMock()
    pool.get_available.return_value = None
    monkeypatch.setattr(groq_key_pool, "_pool_instance", pool)
    monkeypatch.setenv("GROQ_API_KEY", "raw-key")

    assert await groq_key_pool.get_available_groq_key() is None


@pytest.mark.asyncio
async def test_standalone_fallback_paces_each_key_without_real_sleep(monkeypatch):
    sleep = AsyncMock()
    monkeypatch.setattr(groq_key_pool, "_pool_instance", None)
    monkeypatch.setattr(groq_key_pool, "_fallback_keys", None)
    monkeypatch.setattr(groq_key_pool, "_fallback_cursor", 0)
    monkeypatch.setattr(groq_key_pool, "_fallback_next_at", [])
    monkeypatch.setattr(groq_key_pool, "_fallback_lock", asyncio.Lock())
    monkeypatch.setattr(groq_key_pool.time, "monotonic", lambda: 100.0)
    monkeypatch.setattr(groq_key_pool.asyncio, "sleep", sleep)
    monkeypatch.setenv("GROQ_API_KEYS", "key-1,key-2")
    monkeypatch.setenv("GROQ_FALLBACK_RPM", "60")

    keys = [await groq_key_pool.get_available_groq_key() for _ in range(3)]

    assert keys == ["key-1", "key-2", "key-1"]
    sleep.assert_awaited_once_with(1.0)
