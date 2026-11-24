"""A cached answer depends on what of the learner reached its prompt, not on every learner-state write.

On prod every chat turn applied an observation, the backend bumped the learner epoch,
and the next turn invalidated the answer just cached: a signed-in learner never hit.
"""

import hashlib
from unittest.mock import AsyncMock, MagicMock

import pytest

import api.services.trace_cag.cache_utils as cache_mod
import api.services.trace_cag.invalidation as invalidation
import api.services.trace_cag.nodes_v2 as nodes_mod
from api.clients.learner_state_client import LearnerStateResult
from api.core import redis_client
from api.core.redis_client import RedisClient

from .test_kg_mastery_traversal import _DictRedis

QUESTION = "what is the difference between make and do?"
PROFILE = {
    "level": "B1",
    "native_language": "Vietnamese",
    "goal": "travel",
    "interest": "food",
    "profile_brief": "First name: An\nWeakest skill so far: listening",
    "common_errors": ["article", "tense", "article"],
}
ROOT = "concept:grammar.past_simple"
ERROR = {"span": "go", "correction": "went", "type": "grammar", "explanation": "past"}


@pytest.fixture(autouse=True)
def _env(monkeypatch):
    monkeypatch.setattr(cache_mod.settings, "SECRET_KEY", "test-secret")
    monkeypatch.setattr(cache_mod.settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(cache_mod.settings, "LEARNER_STATE_DEADLINE_MS", 40)
    fake = _DictRedis()

    async def get_instance():
        return fake

    monkeypatch.setattr(RedisClient, "get_instance", get_instance)
    monkeypatch.setattr(RedisClient, "_benchmark_redis_disabled", lambda: False)
    monkeypatch.setattr(redis_client.LearnerProfileCache, "get_profile", AsyncMock(return_value=None))
    for store in (cache_mod._MEM_RESPONSE_CACHE, cache_mod._MEM_GRAPH_BUCKETS, cache_mod._MEM_BUCKET_VERSIONS):
        store.clear()
    invalidation.clear_reverse_index()


@pytest.fixture
def learner(monkeypatch):
    """The backend as input_node and the gate see it: an epoch and per-concept states."""
    client = MagicMock()
    client.result = LearnerStateResult(state_epoch=22)
    client.concepts = {}

    async def batch_get(user_id, concept_ids, *, deadline):
        if concept_ids:
            return LearnerStateResult(state_epoch=client.result.state_epoch, states=dict(client.concepts))
        return client.result

    client.batch_get = AsyncMock(side_effect=batch_get)
    monkeypatch.setattr("api.clients.learner_state_client.get_learner_state_client", lambda: client)
    return client


async def _turn(profile=PROFILE, *, text=QUESTION, user="alice"):
    """input_node exactly as the stream runs it, history supplied and empty."""
    return await nodes_mod.input_node({
        "user_input": text, "user_id": user, "session_id": "s1",
        "learner_profile": dict(profile), "conversation_history": [], "conversation_history_supplied": True,
        "cache_policy": "on",
    })


def _gate_state(turn, *, text=QUESTION, user="alice", errors=()):
    return {
        "user_input": text, "user_id": user, "session_id": "s1", "cache_policy": "on",
        "learner_profile": turn["learner_profile"], "conversation_history": [],
        "dependency_events": list(turn["dependency_events"]),
        "diagnosis_confidence": 0.9, "diagnosis_intent": "explain" if not errors else "correct",
        "diagnosis_errors": list(errors), "diagnosis_root_causes": [ROOT] if errors else [],
        "kg_seed_concepts": ["concept:vocab.make_do"],
        "retrieval_trace": [{"item_id": "c1", "title": "t"}],
    }


async def _write(state, text="cached answer", concept_states=None):
    if concept_states is not None:
        state = {**state, "learner_concept_states": concept_states}
    await cache_mod._write_cache_entry(state, text, "praise", state["diagnosis_errors"], 0.8, "", model_used="groq/x")


def test_epoch_and_unrelated_counters_do_not_move_the_profile_version():
    version = cache_mod.prompt_profile_version(PROFILE)
    noisy = {**PROFILE, "_learner_state_epoch": 23, "sessions_completed": 9, "vocabulary_count": 400,
             "common_errors": ["article", "tense", "article", "tense", "article"]}

    assert cache_mod.prompt_profile_version(noisy) == version


@pytest.mark.parametrize("change", [
    {"level": "B2"}, {"native_language": "Japanese"}, {"goal": "career"}, {"interest": "music"},
    {"profile_brief": "First name: An\nWeakest skill so far: writing"},
    {"common_errors": ["tense", "tense", "article"]},
])
def test_anything_the_prompt_reads_moves_the_profile_version(change):
    assert cache_mod.prompt_profile_version({**PROFILE, **change}) != cache_mod.prompt_profile_version(PROFILE)


def test_profile_epoch_follows_the_prompt_profile_and_benchmark_profiles_are_unchanged():
    known = {**PROFILE, "_profile_version": "profile:v1"}
    assert cache_mod._profile_epoch({**known, "_learner_state_epoch": 23, "sessions_completed": 9}) == cache_mod._profile_epoch(known)
    assert cache_mod._profile_epoch({**known, "_profile_version": "profile:v2"}) != cache_mod._profile_epoch(known)

    legacy = {"level": "B1", "sessions_completed": 4, "vocabulary_count": 250, "common_errors": ["a", "b"], "_learner_state_epoch": 3}
    expected = int(hashlib.md5(b"B1|1|1|1|3").hexdigest()[:8], 16)
    assert cache_mod._profile_epoch(legacy) == expected


def test_the_previous_session_recap_is_part_of_the_first_turn_context():
    assert cache_mod._context_digest([]) == "" and cache_mod._context_digest([], "") == ""
    assert cache_mod._context_digest([], "make vs do") not in ("", cache_mod._context_digest([], "pizza"))


@pytest.mark.asyncio
async def test_an_epoch_bump_alone_keeps_the_cached_answer(learner):
    first = await _turn()
    await _write(_gate_state(first))

    learner.result = LearnerStateResult(state_epoch=23)
    again = await _turn()
    served = await cache_mod.cache_gate_node(_gate_state(again))

    assert (served["cache_decision"], served["cache_layer"]) == ("reuse", "L0")
    assert served["tutor_response"] == "cached answer"


@pytest.mark.asyncio
async def test_a_goal_change_still_invalidates(learner):
    first = await _turn()
    await _write(_gate_state(first))

    learner.result = LearnerStateResult(state_epoch=23, goal="career")
    changed = await _turn()

    assert (await cache_mod.cache_gate_node(_gate_state(changed)))["cache_hit"] is False


@pytest.mark.asyncio
async def test_a_different_recap_is_a_different_first_turn(learner):
    first = await _turn({**PROFILE, "session_recap": "make vs do"})
    await _write(_gate_state(first))

    same = await _turn({**PROFILE, "session_recap": "make vs do"})
    other = await _turn({**PROFILE, "session_recap": "pizza toppings"})

    assert (await cache_mod.cache_gate_node(_gate_state(same)))["cache_decision"] == "reuse"
    assert (await cache_mod.cache_gate_node(_gate_state(other)))["cache_hit"] is False


@pytest.mark.asyncio
async def test_a_degraded_learner_state_read_publishes_no_version(learner):
    first = await _turn()
    await _write(_gate_state(first))
    key = "learner:alice:profile"
    before = invalidation._MEM_DEPENDENCY_TOKENS[key]

    learner.result = LearnerStateResult(state_epoch=0, degraded=True, reason="timeout")
    await _turn({**PROFILE, "goal": ""})

    assert invalidation._MEM_DEPENDENCY_TOKENS[key] == before
    learner.result = LearnerStateResult(state_epoch=24)
    assert (await cache_mod.cache_gate_node(_gate_state(await _turn())))["cache_decision"] == "reuse"


@pytest.mark.asyncio
@pytest.mark.parametrize("now, served", [
    ({"error_count": 1, "mastery_probability": 0.7}, True),
    ({"error_count": 2, "mastery_probability": 0.4}, False),
])
async def test_a_correction_is_reused_only_while_its_concept_hint_is_unchanged(learner, now, served):
    first = await _turn(text="yesterday I go to school")
    await _write(_gate_state(first, text="yesterday I go to school", errors=[ERROR]),
                 concept_states={ROOT: {"error_count": 1, "mastery_probability": 0.7}})

    learner.concepts = {ROOT: now}
    result = await cache_mod.cache_gate_node(_gate_state(await _turn(text="yesterday I go to school"), text="yesterday I go to school"))

    assert result["cache_hit"] is served
    if not served:
        assert "learner_concept_state_changed" in result["cache_gate_meta"]["reasons"]


@pytest.mark.asyncio
async def test_a_correction_is_not_reused_when_its_concept_state_cannot_be_read(learner):
    first = await _turn(text="yesterday I go to school")
    await _write(_gate_state(first, text="yesterday I go to school", errors=[ERROR]), concept_states={})

    async def broken(user_id, concept_ids, *, deadline):
        if concept_ids:
            raise TimeoutError("learner state")
        return learner.result

    learner.batch_get.side_effect = broken
    result = await cache_mod.cache_gate_node(_gate_state(await _turn(text="yesterday I go to school"), text="yesterday I go to school"))

    assert result["cache_hit"] is False
