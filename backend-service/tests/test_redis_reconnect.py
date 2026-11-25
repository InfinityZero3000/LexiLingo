"""A Redis that is down at boot must be picked up once it is back, not at the next restart."""

from unittest.mock import AsyncMock, patch

import pytest
import redis.asyncio as redis

from app.core.redis import RedisClient


@pytest.fixture(autouse=True)
def _reset_client():
    saved = (RedisClient._instance, RedisClient._connected, RedisClient._retry_at)
    RedisClient._instance, RedisClient._connected, RedisClient._retry_at = None, False, None
    yield
    RedisClient._instance, RedisClient._connected, RedisClient._retry_at = saved


@pytest.mark.asyncio
async def test_reconnects_after_boot_without_redis():
    fake = AsyncMock()
    fake.ping.side_effect = [redis.ConnectionError("down"), True]
    with patch("app.core.redis.settings") as cfg, patch("app.core.redis.redis.from_url", return_value=fake):
        cfg.REDIS_URL, cfg.REDIS_PASSWORD = "redis://redis:6379/0", None
        await RedisClient.connect()
        assert await RedisClient.get_instance() is None

        RedisClient._retry_at = 0.0
        assert await RedisClient.get_instance() is fake
        assert RedisClient._retry_at is None


@pytest.mark.asyncio
async def test_no_retry_inside_the_backoff_window_or_when_never_configured():
    with patch("app.core.redis.settings") as cfg:
        cfg.REDIS_URL = ""
        await RedisClient.connect()
        assert await RedisClient.get_instance() is None
        assert RedisClient._retry_at is None

    fake = AsyncMock()
    fake.ping.side_effect = redis.ConnectionError("down")
    with patch("app.core.redis.settings") as cfg, patch("app.core.redis.redis.from_url", return_value=fake) as mk:
        cfg.REDIS_URL, cfg.REDIS_PASSWORD = "redis://redis:6379/0", None
        await RedisClient.connect()
        calls = mk.call_count
        await RedisClient.get_instance()
        assert mk.call_count == calls
