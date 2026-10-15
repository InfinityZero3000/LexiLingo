"""Recommendation route behavior. Feature-derived signals (topic_affinity,
vocabulary_weakness, difficulty_preference) are covered in
test_feature_processor.py."""

import json

import pytest

from app.core.redis import RedisClient
from app.models.learner_state import LearnerConceptState
from app.services.feature_processor import INSIGHTS_CACHE_PREFIX
from app.services.recommendation_service import attach_mastery, build_profile

pytestmark = pytest.mark.asyncio


class _FakeRedis:
    def __init__(self):
        self.store: dict[str, str] = {}

    async def get(self, key):
        return self.store.get(key)

    async def setex(self, key, ttl, value):
        self.store[key] = value


async def test_build_profile_uses_cached_insights_without_recomputing(
    db_session, test_user, monkeypatch
):
    """A cache hit from the Event Worker must short-circuit compute_insights
    entirely — proven with a marker value no recompute could ever produce."""
    fake = _FakeRedis()
    marker = {
        "topic_affinity": {"__from_cache__": 1.0},
        "vocabulary_weakness": {},
        "difficulty_preference": 0.0,
    }
    fake.store[f"{INSIGHTS_CACHE_PREFIX}{test_user.id}"] = json.dumps(marker)

    async def fake_get_instance():
        return fake

    monkeypatch.setattr(RedisClient, "get_instance", fake_get_instance)

    async def _boom(*_args, **_kwargs):
        raise AssertionError("compute_insights must not run on a cache hit")

    import app.services.recommendation_service as recommendation_service

    monkeypatch.setattr(recommendation_service, "compute_insights", _boom)

    profile = await build_profile(db_session, test_user.id)

    assert profile["topic_affinity"] == {"__from_cache__": 1.0}


async def test_build_profile_writes_through_on_cache_miss(
    db_session, test_user, monkeypatch
):
    fake = _FakeRedis()

    async def fake_get_instance():
        return fake

    monkeypatch.setattr(RedisClient, "get_instance", fake_get_instance)

    profile = await build_profile(db_session, test_user.id)

    assert profile["topic_affinity"] == {}
    cached = json.loads(fake.store[f"{INSIGHTS_CACHE_PREFIX}{test_user.id}"])
    assert cached["topic_affinity"] == {}


async def test_attach_mastery_loads_only_concepts_the_candidates_reference(
    db_session, test_user
):
    """LearnerConceptState is never pruned, so a long-running learner has
    thousands of rows. Only the ones the ranker will actually look up may be
    loaded and shipped."""
    for index in range(5):
        db_session.add(
            LearnerConceptState(
                user_id=test_user.id,
                concept_id=f"vocab:word{index}",
                mastery_probability=0.1 * index,
            )
        )
    await db_session.flush()

    candidates = [
        {"item_id": "a", "concept_ids": ["vocab:word1"]},
        {"item_id": "b", "concept_ids": ["vocab:word3"]},
    ]
    profile = await attach_mastery(db_session, test_user.id, {"mastery": {}}, candidates)

    assert set(profile["mastery"]) == {"vocab:word1", "vocab:word3"}


async def test_attach_mastery_is_a_noop_without_concept_labels(db_session, test_user):
    db_session.add(
        LearnerConceptState(
            user_id=test_user.id, concept_id="vocab:x", mastery_probability=0.9
        )
    )
    await db_session.flush()

    candidates = [{"item_id": "a", "concept_ids": []}]
    profile = await attach_mastery(db_session, test_user.id, {"mastery": {}}, candidates)

    assert profile["mastery"] == {}


async def test_endpoint_degrades_instead_of_failing(
    async_client, auth_headers: dict, monkeypatch
):
    """ai-service being unreachable must not take Home's rail down with it."""
    monkeypatch.delenv("AI_ADMIN_API_KEY", raising=False)

    response = await async_client.get(
        "/api/v1/recommendations?surface=home&limit=5", headers=auth_headers
    )

    assert response.status_code == 200
    body = response.json()["data"]
    assert body["degraded"] is True
    assert body["surface"] == "home"
    assert isinstance(body["items"], list)
