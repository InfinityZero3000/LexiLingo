import asyncio
import logging
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from api.core import groq_key_pool


def test_strict_key_parser_requires_seven_unique_nonblank_keys():
    keys = [f"key-{i}" for i in range(7)]
    assert groq_key_pool.parse_groq_keys(" , ".join(keys), require_seven=True) == keys

    with pytest.raises(ValueError, match="exactly seven"):
        groq_key_pool.parse_groq_keys(",".join(keys[:6]), require_seven=True)
    with pytest.raises(ValueError, match="blank"):
        groq_key_pool.parse_groq_keys("key-1,,key-2", require_seven=True)
    with pytest.raises(ValueError, match="duplicate"):
        groq_key_pool.parse_groq_keys(",".join(keys[:6] + ["key-1"]), require_seven=True)


@pytest.mark.asyncio
async def test_concurrent_pool_acquisition_rotates_safely_and_logs_only_slots(caplog, monkeypatch):
    keys = [f"secret-{i}" for i in range(7)]
    pool = groq_key_pool.GroqKeyPool(keys, SimpleNamespace())
    pool._limiters = [SimpleNamespace(can_request=AsyncMock(return_value=True)) for _ in keys]
    monkeypatch.setenv("GROQ_SLOT_TELEMETRY", "true")

    with caplog.at_level(logging.INFO):
        acquired = await asyncio.gather(*(pool.get_available() for _ in keys))

    assert [item[0] for item in acquired] == keys
    messages = "\n".join(record.getMessage() for record in caplog.records)
    assert [int(line.rsplit("=", 1)[1]) for line in messages.splitlines()] == list(range(7))
    assert not any(key in messages for key in keys)


@pytest.mark.asyncio
async def test_all_limiters_exhausted_returns_immediately():
    pool = groq_key_pool.GroqKeyPool(["key-1"], SimpleNamespace())
    pool._limiters = [SimpleNamespace(can_request=AsyncMock(return_value=False))]

    assert await asyncio.wait_for(pool.get_available(), timeout=1) is None


@pytest.mark.asyncio
async def test_redis_voice_acquire_is_atomic_and_release_uses_lease_token():
    redis = SimpleNamespace(eval=AsyncMock(return_value=1))
    pool = groq_key_pool.GroqKeyPool(["key-1"], redis)
    pool._limiters = [
        SimpleNamespace(
            can_request=AsyncMock(return_value=True),
            redis=redis,
            prefix="groq:key0",
            rpm_limit=30,
            safety=0.9,
        )
    ]

    first = await pool.try_acquire_voice(96)
    second = await pool.try_acquire_voice(96)
    assert first == second == "key-1"
    assert first.lease_token != second.lease_token
    acquire = redis.eval.await_args_list[0]
    assert acquire.args[1:4] == (
        2,
        "groq:key0:voice:lease",
        "groq:key0:voice:rpm",
    )
    assert acquire.args[-1] == 45_000

    await pool.release_voice(first)
    await pool.release_voice(second)
    releases = redis.eval.await_args_list[2:]
    assert [call.args[-1] for call in releases] == [
        first.lease_token,
        second.lease_token,
    ]


@pytest.mark.asyncio
async def test_redis_voice_acquire_fails_closed_when_atomic_eval_fails():
    redis = SimpleNamespace(eval=AsyncMock(side_effect=RuntimeError("redis down")))
    pool = groq_key_pool.GroqKeyPool(["key-1"], redis)
    pool._limiters = [
        SimpleNamespace(
            can_request=AsyncMock(return_value=True),
            redis=redis,
            prefix="groq:key0",
            rpm_limit=30,
            safety=0.9,
        )
    ]

    assert await pool.try_acquire_voice(96) is None
    redis.eval.assert_awaited_once()


@pytest.mark.asyncio
async def test_redis_pool_exhaustion_does_not_bypass_with_raw_key(monkeypatch):
    pool = AsyncMock()
    pool.get_available.return_value = None
    monkeypatch.setattr(groq_key_pool, "_pool_instance", pool)
    monkeypatch.setenv("GROQ_API_KEY", "raw-key")

    assert await groq_key_pool.get_available_groq_key() is None


@pytest.mark.asyncio
async def test_standalone_legacy_lookup_rotates_without_reserving(monkeypatch):
    monkeypatch.setattr(groq_key_pool, "_pool_instance", None)
    monkeypatch.setattr(groq_key_pool, "_fallback_keys", None)
    monkeypatch.setattr(groq_key_pool, "_fallback_cursor", 0)
    monkeypatch.setattr(groq_key_pool, "_fallback_in_flight", set())
    monkeypatch.setenv("GROQ_API_KEYS", "key-1,key-2")

    assert [await groq_key_pool.get_available_groq_key() for _ in range(3)] == [
        "key-1",
        "key-2",
        "key-1",
    ]
    assert groq_key_pool._fallback_in_flight == set()


@pytest.mark.asyncio
async def test_voice_acquire_reserves_each_key_and_obeys_rpm(monkeypatch):
    clock = {"now": 100.0}
    monkeypatch.setattr(groq_key_pool, "_pool_instance", None)
    monkeypatch.setattr(groq_key_pool, "_fallback_keys", None)
    monkeypatch.setattr(groq_key_pool, "_fallback_cursor", 0)
    monkeypatch.setattr(groq_key_pool, "_fallback_in_flight", set())
    monkeypatch.setattr(groq_key_pool, "_fallback_next_at", [])
    monkeypatch.setattr(groq_key_pool, "_fallback_lock", asyncio.Lock())
    monkeypatch.setattr(groq_key_pool.time, "monotonic", lambda: clock["now"])
    monkeypatch.setenv("GROQ_API_KEYS", "key-1,key-2")
    monkeypatch.setenv("GROQ_FALLBACK_RPM", "60")

    assert [await groq_key_pool.try_acquire_groq_key() for _ in range(3)] == [
        "key-1",
        "key-2",
        None,
    ]
    await groq_key_pool.release_groq_key("key-1")
    assert await groq_key_pool.try_acquire_groq_key() is None
    clock["now"] = 101.0
    assert await groq_key_pool.try_acquire_groq_key() == "key-1"
