"""record_learner_errors: best-effort write of diagnosed error types into
LearnerProfileCache, feeding the cross-session personalization hint."""

import pytest

from api.core.redis_client import LearnerProfileCache, record_learner_errors


@pytest.mark.asyncio
async def test_records_each_error_type(monkeypatch):
    recorded = []

    async def fake_add_error(self, user_id, error_type):
        recorded.append((user_id, error_type))

    async def fake_get_instance():
        return object()

    monkeypatch.setattr(LearnerProfileCache, "add_error", fake_add_error)
    monkeypatch.setattr(
        "api.core.redis_client.RedisClient.get_instance", fake_get_instance
    )

    await record_learner_errors(
        "user-1",
        [
            {"span": "go", "type": "tense_error", "correction": "went"},
            {"span": "a apple", "type": "article_error", "correction": "an apple"},
        ],
    )

    assert recorded == [
        ("user-1", "tense_error"),
        ("user-1", "article_error"),
    ]


@pytest.mark.asyncio
async def test_noop_without_user_id_or_errors(monkeypatch):
    calls = []

    async def fake_get_instance():
        calls.append(1)
        return object()

    monkeypatch.setattr(
        "api.core.redis_client.RedisClient.get_instance", fake_get_instance
    )

    await record_learner_errors(None, [{"type": "tense_error"}])
    await record_learner_errors("user-1", [])
    await record_learner_errors("user-1", None)

    assert calls == []  # never even touches Redis when there's nothing to record


@pytest.mark.asyncio
async def test_redis_failure_does_not_raise(monkeypatch):
    async def fake_get_instance():
        raise ConnectionError("redis down")

    monkeypatch.setattr(
        "api.core.redis_client.RedisClient.get_instance", fake_get_instance
    )

    # Must not raise — this is a personalization signal, not critical path.
    await record_learner_errors("user-1", [{"type": "tense_error"}])
