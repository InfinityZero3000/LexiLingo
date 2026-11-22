from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import redis.asyncio as redis

from app.core.redis import RedisClient
from app.core.token_blacklist import InactiveUserFlag


def _client():
    return MagicMock(spec=redis.Redis, setex=AsyncMock(), delete=AsyncMock())


@pytest.mark.asyncio
async def test_deactivation_publishes_key_with_ttl_beyond_access_token():
    client = _client()
    with patch.object(RedisClient, "get_instance", autospec=True, return_value=client):
        assert await InactiveUserFlag.sync("u1", False) is True
    key, ttl, _ = client.setex.call_args.args
    assert key == "user:inactive:u1"
    assert ttl > 30 * 60


@pytest.mark.asyncio
async def test_reactivation_clears_key():
    client = _client()
    with patch.object(RedisClient, "get_instance", autospec=True, return_value=client):
        assert await InactiveUserFlag.sync("u1", True) is True
    client.delete.assert_awaited_once_with("user:inactive:u1")


@pytest.mark.asyncio
async def test_redis_unavailable_or_failing_does_not_raise():
    with patch.object(RedisClient, "get_instance", autospec=True, return_value=None):
        assert await InactiveUserFlag.sync("u1", False) is False
    client = _client()
    client.setex.side_effect = redis.ConnectionError("down")
    with patch.object(RedisClient, "get_instance", autospec=True, return_value=client):
        assert await InactiveUserFlag.sync("u1", False) is False
