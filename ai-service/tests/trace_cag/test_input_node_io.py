"""input_node's I/O: history is read once, profile in one round trip, and a slow Redis cannot stall a turn."""

import asyncio
import json
import time
from unittest.mock import AsyncMock

import pytest

from api.core.config import settings
from api.core.redis_client import ConversationCache, LearnerProfileCache, RedisClient
from api.services.trace_cag import nodes_v2
from api.services.trace_cag.graph import TraceCAGPipeline

SUPPLIED = [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "hello"}]


@pytest.fixture
def redis_up(monkeypatch):
    monkeypatch.setattr(settings, "LEARNER_STATE_MODE", "off")
    monkeypatch.setattr(RedisClient, "_benchmark_redis_disabled", classmethod(lambda cls: False))
    monkeypatch.setattr(RedisClient, "get_instance", AsyncMock(return_value=object()))
    monkeypatch.setattr(LearnerProfileCache, "get_profile", AsyncMock(return_value={"level": "A2", "common_errors": ["articles"]}))
    history = AsyncMock(return_value=[{"user": "from redis", "ai": "from redis"}])
    monkeypatch.setattr(ConversationCache, "get_history", history)
    return history


def _state(**extra):
    return {"user_input": "hello there", "user_id": "u1", "session_id": "s1", **extra}


@pytest.mark.asyncio
async def test_supplied_history_is_used_and_redis_history_is_not_read(redis_up):
    result = await nodes_v2.input_node(_state(conversation_history=SUPPLIED, conversation_history_supplied=True))

    assert result["conversation_history"] == SUPPLIED
    redis_up.assert_not_awaited()
    assert result["learner_profile"]["common_errors"] == ["articles"]


@pytest.mark.asyncio
async def test_an_empty_supplied_history_is_still_authoritative(redis_up):
    result = await nodes_v2.input_node(_state(conversation_history=[], conversation_history_supplied=True))

    assert result["conversation_history"] == []
    redis_up.assert_not_awaited()


@pytest.mark.asyncio
async def test_history_is_read_from_redis_when_the_caller_supplied_none(redis_up):
    result = await nodes_v2.input_node(_state(conversation_history=[]))

    assert result["conversation_history"] == [{"user": "from redis", "ai": "from redis"}]
    redis_up.assert_awaited_once()


@pytest.mark.asyncio
async def test_supplied_history_survives_a_redis_outage(monkeypatch):
    monkeypatch.setattr(settings, "LEARNER_STATE_MODE", "off")
    monkeypatch.setattr(RedisClient, "_benchmark_redis_disabled", classmethod(lambda cls: False))
    monkeypatch.setattr(RedisClient, "get_instance", AsyncMock(side_effect=RuntimeError("redis down")))

    result = await nodes_v2.input_node(_state(conversation_history=SUPPLIED, conversation_history_supplied=True))

    assert result["conversation_history"] == SUPPLIED


@pytest.mark.asyncio
async def test_a_hung_redis_is_abandoned_after_the_budget_instead_of_stalling_the_turn(redis_up, monkeypatch):
    async def hang(*args, **kwargs):
        await asyncio.sleep(30)

    monkeypatch.setattr(LearnerProfileCache, "get_profile", hang)
    monkeypatch.setattr(ConversationCache, "get_history", hang)
    monkeypatch.setenv("TRACECAG_INPUT_REDIS_BUDGET_MS", "50")

    started = time.perf_counter()
    result = await nodes_v2.input_node(_state(learner_profile={"level": "C1"}))

    assert time.perf_counter() - started < 2.0
    assert result["learner_profile"]["level"] == "C1"
    assert result["conversation_history"] == []


@pytest.mark.asyncio
async def test_analyze_marks_a_caller_supplied_history(monkeypatch):
    seen = {}

    class Compiled:
        async def ainvoke(self, state):
            seen.update(state)
            return {**state, "tutor_response": "ok", "metadata": {}}

    pipeline = TraceCAGPipeline.__new__(TraceCAGPipeline)
    pipeline.compiled = Compiled()

    await pipeline.analyze("hi", "s1", user_id="u1", conversation_history=SUPPLIED)
    assert seen["conversation_history_supplied"] is True

    seen.clear()
    await pipeline.analyze("hi", "s1", user_id="u1")
    assert not seen.get("conversation_history_supplied")


class _FakePipeline:
    def __init__(self, redis):
        self.redis = redis
        self.commands = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    def get(self, key):
        self.commands.append(("get", key))

    def lrange(self, key, start, stop):
        self.commands.append(("lrange", key, start, stop))

    async def execute(self):
        self.redis.round_trips += 1
        return [self.redis.data[command[1]] for command in self.commands]


class _FakeRedis:
    """Counts network round trips: a pipeline is one, every direct command is one."""

    def __init__(self, data):
        self.data = data
        self.round_trips = 0

    def pipeline(self, transaction=True):
        return _FakePipeline(self)

    async def get(self, key):
        self.round_trips += 1
        return self.data[key]

    async def lrange(self, key, start, stop):
        self.round_trips += 1
        return self.data[key]


@pytest.mark.asyncio
async def test_profile_is_read_in_one_round_trip(monkeypatch):
    redis = _FakeRedis({
        "learner:u1:level": "B2",
        "learner:u1:errors": ["past_tense", "articles"],
        "learner:u1:sessions": [json.dumps({"topic": "travel"})],
    })

    async def run(operation):
        return await operation(redis)

    monkeypatch.setattr(RedisClient, "execute_with_reconnect", AsyncMock(side_effect=run))
    monkeypatch.setattr(RedisClient, "get_instance", AsyncMock(return_value=redis))

    profile = await LearnerProfileCache(redis).get_profile("u1")

    assert redis.round_trips == 1
    assert profile == {
        "user_id": "u1",
        "level": "B2",
        "common_errors": ["past_tense", "articles"],
        "recent_sessions": [{"topic": "travel"}],
    }


@pytest.mark.asyncio
async def test_profile_defaults_are_unchanged_for_an_unknown_learner(monkeypatch):
    redis = _FakeRedis({"learner:u2:level": None, "learner:u2:errors": [], "learner:u2:sessions": []})

    async def run(operation):
        return await operation(redis)

    monkeypatch.setattr(RedisClient, "execute_with_reconnect", AsyncMock(side_effect=run))
    monkeypatch.setattr(RedisClient, "get_instance", AsyncMock(return_value=redis))

    profile = await LearnerProfileCache(redis).get_profile("u2")

    assert profile == {"user_id": "u2", "level": "B1", "common_errors": [], "recent_sessions": []}
