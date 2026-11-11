"""Mastery-weighted KG traversal: fail-open, isolation, weights, switches, usage ledger."""
from __future__ import annotations

import asyncio
import hashlib
import itertools
import json
import sys
import time
import types
from contextlib import ExitStack
from datetime import timedelta
from unittest import mock

import kuzu
import pytest

import api.services.trace_cag.retrieve as retrieve_mod
from api.clients.learner_state_client import LearnerStateClient, LearnerStateResult
from api.core import groq_key_pool
from api.core.config import Settings, settings
from api.core.redis_client import RedisClient
import api.services.trace_cag.cache_utils as cache_mod
from api.services.document_intelligence import DocumentIntelligenceService
from api.services.model_gateway import ModelGateway
from api.services.retrieval_service_v3 import RetrievalServiceV3
from api.services.trace_cag.state import TraceCAGState, create_initial_state
from api.services.trace_cag.graph import TraceCAGPipeline
from langgraph.graph import END, StateGraph
from api.models.v3_schemas import KGHits, RetrievalBundleV3, VectorHit
from api.services import kg_service_v3 as kg_module
from api.services.kg_service_v3 import KnowledgeGraphServiceV3
from api.services.trace_cag import nodes_v2
from api.services.trace_cag.benchmark.qa_generation import _USAGE_LEDGER, _ledger_add, usage_ledger
from api.services.trace_cag.dependencies import policy_version_token

BETA = kg_module._MASTERY_BETA
LOW = kg_module._LOW_VALUE_RELATION_WEIGHT


class FakeRedis:
    def __init__(self) -> None:
        self.store: dict[str, str] = {}
        self.gets: list[str] = []
        self.sets: list[str] = []

    async def get(self, key: str):
        self.gets.append(key)
        return self.store.get(key)

    async def setex(self, key: str, ttl: int, value: str) -> None:
        self.sets.append(key)
        self.store[key] = value

    def reset(self) -> None:
        self.store.clear()
        self.gets.clear()
        self.sets.clear()


@pytest.fixture()
def redis(monkeypatch):
    fake = FakeRedis()

    async def get_instance():
        return fake

    module = types.SimpleNamespace(RedisClient=types.SimpleNamespace(get_instance=get_instance))
    monkeypatch.setitem(sys.modules, "api.core.redis_client", module)
    return fake


def _stub(monkeypatch, owner, name, **kwargs):
    stub = mock.create_autospec(getattr(owner, name), **kwargs)
    monkeypatch.setattr(owner, name, stub)
    return stub


def _shared_key(seeds, level, hops, nodes) -> str:
    digest = hashlib.sha1(f"{sorted(seeds)}:{level}:{hops}:{nodes}".encode()).hexdigest()
    return "kg:subgraph:v2:" + digest


def _make_kg(monkeypatch, tmp_path, nodes, edges):
    db = kuzu.Database(str(tmp_path / "kg.db"))
    conn = kuzu.Connection(db)
    conn.execute(
        "CREATE NODE TABLE Concept(id STRING, title STRING, keywords STRING, level STRING DEFAULT 'B1', PRIMARY KEY(id))"
    )
    conn.execute("CREATE REL TABLE Edge(FROM Concept TO Concept, relation STRING)")
    for cid, level in nodes:
        conn.execute(
            "CREATE (:Concept {id: $id, title: $t, keywords: '', level: $lv})",
            {"id": cid, "t": cid, "lv": level},
        )
    for a, b, rel in edges:
        conn.execute(
            "MATCH (a:Concept), (b:Concept) WHERE a.id = $a AND b.id = $b "
            "CREATE (a)-[:Edge {relation: $r}]->(b)",
            {"a": a, "b": b, "r": rel},
        )
    service = KnowledgeGraphServiceV3.__new__(KnowledgeGraphServiceV3)
    service._conn = conn
    service._db = db
    service._lock = asyncio.Lock()
    service._recovery_attempted = True
    monkeypatch.setattr(KnowledgeGraphServiceV3, "_recover_and_retry", lambda *_a, **_k: False)
    return service


XY_NODES = [("concept:s", "B1"), ("concept:x", "B1"), ("concept:y", "B1")]
XY_EDGES = [("concept:s", "concept:x", "contrasts_with"), ("concept:s", "concept:y", "contrasts_with")]

# one seed, seven neighbours that exercise every row of the weight table
TABLE_NODES = [
    ("concept:s", "B1"),
    ("concept:w", "B1"),
    ("concept:u", "B2"),
    ("concept:n", "B1"),
    ("concept:q", "B2"),
    ("concept:p", "B1"),
    ("concept:z", "B2"),
    ("concept:lv", "B1"),
    ("concept:off0", "C2"),
    ("concept:off1", "C2"),
]
TABLE_EDGES = [
    ("concept:s", cid, "has_cefr_level" if cid == "concept:lv" else "contrasts_with")
    for cid, _ in TABLE_NODES[1:]
]
TABLE_MASTERY = {
    "concept:w": 0.0,
    "concept:u": 0.0,
    "concept:p": 1.0,
    "concept:z": 1.0,
    "concept:lv": 0.0,
    "concept:off0": 0.0,
    "concept:off1": 1.0,
}


@pytest.fixture()
def xy(monkeypatch, tmp_path, redis):
    return _make_kg(monkeypatch, tmp_path, XY_NODES, XY_EDGES)


@pytest.fixture()
def table(monkeypatch, tmp_path, redis):
    return _make_kg(monkeypatch, tmp_path, TABLE_NODES, TABLE_EDGES)


async def _ids(kg, mastery=None, hops=1):
    hits = await kg.expand_best_first(["concept:s"], "B1", hops, 10, mastery=mastery)
    return [n.id for n in hits.expanded_nodes]


def _weight(level_weight: float, m: float | None = None, low: bool = False) -> float:
    w = level_weight * (LOW if low else 1.0)
    return w if m is None else w * (1 + BETA * (1 - 2 * m))


def test_constants_are_the_ones_the_table_below_assumes():
    assert (BETA, LOW) == (0.5, 0.15)


# (id, CEFR weight vs a B1 learner, mastery, low-value relation, hand-computed weight)
TABLE = [
    ("concept:w", 1.0, 0.0, False, 1.5),
    ("concept:u", 0.7, 0.0, False, 1.05),
    ("concept:n", 1.0, None, False, 1.0),
    ("concept:q", 0.7, None, False, 0.7),
    ("concept:p", 1.0, 1.0, False, 0.5),
    ("concept:off0", 0.3, 0.0, False, 0.45),
    ("concept:z", 0.7, 1.0, False, 0.35),
    ("concept:lv", 1.0, 0.0, True, 0.225),
    ("concept:off1", 0.3, 1.0, False, 0.15),
]


@pytest.mark.parametrize("cid, level_weight, m, low, expected", TABLE)
def test_hand_computed_weights_match_the_constants(cid, level_weight, m, low, expected):
    assert _weight(level_weight, m, low) == pytest.approx(expected)


@pytest.mark.asyncio
async def test_expansion_order_follows_the_weight_table(table):
    assert await _ids(table) == [
        "concept:n", "concept:p", "concept:w",
        "concept:q", "concept:u", "concept:z",
        "concept:off0", "concept:off1", "concept:lv",
    ]
    on = await _ids(table, TABLE_MASTERY)
    assert on == [
        "concept:w",     # on-level, m=0        1.5
        "concept:u",     # +1 level, m=0        1.05
        "concept:n",     # on-level, no state   1.0
        "concept:q",     # +1 level, no state   0.7
        "concept:p",     # on-level, m=1        0.5   (below unknown +1)
        "concept:off0",  # 3 levels off, m=0    0.45  (above +1 at m=1)
        "concept:z",     # +1 level, m=1        0.35
        "concept:lv",    # low-value, m=0       0.225 (below every typed on/+1 edge)
        "concept:off1",  # 3 levels off, m=1    0.15
    ]
    assert on == [cid for cid, *_ in sorted(TABLE, key=lambda row: -_weight(*row[1:4]))]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "mastery",
    [
        pytest.param({c: 0.5 for c, _ in TABLE_NODES}, id="all_prior"),
        pytest.param({"concept:p": 0.5}, id="partial_prior"),
        pytest.param(
            {"concept:n": float("nan"), "concept:u": float("inf"), "concept:w": float("-inf")},
            id="non_finite",
        ),
    ],
)
async def test_prior_keeps_flag_off_order(table, redis, mastery):
    off = await _ids(table)
    redis.reset()
    assert await _ids(table, mastery) == off


@pytest.mark.asyncio
async def test_mastery_is_clamped(table):
    assert await _ids(table, {"concept:p": 7.0, "concept:w": -3.0}) == await _ids(
        table, {"concept:p": 1.0, "concept:w": 0.0}
    )


@pytest.mark.asyncio
async def test_opposite_learners_get_different_order_and_no_shared_cache_traffic(xy, redis):
    a = await _ids(xy, {"concept:x": 0.0, "concept:y": 1.0})
    b = await _ids(xy, {"concept:x": 1.0, "concept:y": 0.0})
    assert a == ["concept:x", "concept:y"]
    assert b == ["concept:y", "concept:x"]
    assert redis.gets == [] and redis.sets == []


@pytest.mark.asyncio
async def test_empty_mastery_uses_the_shared_cache_like_none(xy, redis):
    key = _shared_key(["concept:s"], "B1", 1, 10)
    await _ids(xy, {})
    assert redis.gets == [key] and redis.sets == [key]


@pytest.mark.asyncio
async def test_cefr_weight_off_ignores_level_keeps_low_value_and_bypasses_redis(table, redis):
    default = await _ids(table)
    redis.reset()
    hits = await table.expand_best_first(["concept:s"], "B1", 1, 10, cefr_weight=False)
    # every level weighs 1, so ties break on id; the low-value edge still sinks to the end
    assert [n.id for n in hits.expanded_nodes] == [
        "concept:n", "concept:off0", "concept:off1", "concept:p",
        "concept:q", "concept:u", "concept:w", "concept:z", "concept:lv",
    ]
    assert default != [n.id for n in hits.expanded_nodes]
    assert redis.gets == [] and redis.sets == []
    assert await _ids(table) == default


@pytest.mark.asyncio
async def test_default_path_key_and_payload_match_the_old_formula(xy, redis):
    key = _shared_key(["concept:s"], "B1", 1, 10)
    assert key == "kg:subgraph:v2:" + hashlib.sha1(b"['concept:s']:B1:1:10").hexdigest()
    hits = await xy.expand_best_first(["concept:s"], "B1", 1, 10)
    assert redis.gets == [key] and redis.sets == [key]
    expected_nodes = [
        {
            "id": cid,
            "type": "contrasts_with",
            "properties": {"relation": "contrasts_with", "depth": 1, "title": cid, "keywords": ""},
        }
        for cid in ("concept:x", "concept:y")
    ]
    assert redis.store[key] == json.dumps({
        "seeds": ["concept:s"],
        "nodes": expected_nodes,
        "paths": [{"nodes": ["concept:s", cid], "edges": ["contrasts_with"]} for cid in ("concept:x", "concept:y")],
    })

    xy._conn = None
    cached = await xy.expand_best_first(["concept:s"], "B1", 1, 10)
    assert [n.id for n in cached.expanded_nodes] == ["concept:x", "concept:y"]
    assert [n.id for n in hits.expanded_nodes] == ["concept:x", "concept:y"]


MULTI_NODES = [("c:a", "B1"), ("c:z", "B1")] + [(f"c:{p}{i}", "B1") for p in "az" for i in range(1, 7)]
MULTI_EDGES = [(f"c:{p}", f"c:{p}{i}", "contrasts_with") for p in "az" for i in range(1, 7)]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "mastery, leading",
    [
        pytest.param({"c:a": 0.4, "c:z": 0.0}, "z", id="weak_seed_is_the_later_id"),
        pytest.param({"c:a": 0.0, "c:z": 0.4}, "a", id="weak_seed_is_the_earlier_id"),
    ],
)
async def test_every_seed_is_queried_before_any_neighbour_pops(monkeypatch, tmp_path, redis, mastery, leading):
    kg = _make_kg(monkeypatch, tmp_path, MULTI_NODES, MULTI_EDGES)
    real = kg._execute
    queried: list[str] = []

    async def spy(stmt, params=None):
        queried.append(params["cid"])
        return await real(stmt, params)

    monkeypatch.setattr(kg, "_execute", spy)
    hits = await kg.expand_best_first(["c:a", "c:z"], "B1", 1, 5, mastery=mastery)

    assert sorted(queried) == ["c:a", "c:z"]
    assert [n.id for n in hits.expanded_nodes] == [f"c:{leading}{i}" for i in range(1, 6)]


@pytest.mark.asyncio
async def test_recover_and_retry_preserves_mastery(xy, monkeypatch):
    real = xy._execute
    calls = {"n": 0}

    async def flaky(stmt, params=None):
        calls["n"] += 1
        if calls["n"] == 1:
            raise RuntimeError("boom")
        return await real(stmt, params)

    recoveries = []

    def recover(self, *_a, **_k):
        recoveries.append(1)
        return len(recoveries) == 1

    monkeypatch.setattr(xy, "_execute", flaky)
    monkeypatch.setattr(KnowledgeGraphServiceV3, "_recover_and_retry", recover)
    assert await _ids(xy, {"concept:x": 1.0, "concept:y": 0.0}) == ["concept:y", "concept:x"]
    assert len(recoveries) == 1


def test_defaults_keep_behaviour():
    fields = Settings.model_fields
    assert fields["KG_ENABLED"].default is True
    assert fields["KG_EXPANSION_ENABLED"].default is True
    assert fields["KG_MASTERY_TRAVERSAL"].default is False


def _flags(monkeypatch, mastery=False, kg=True, expansion=True):
    monkeypatch.setattr(settings, "KG_MASTERY_TRAVERSAL", mastery)
    monkeypatch.setattr(settings, "KG_ENABLED", kg)
    monkeypatch.setattr(settings, "KG_EXPANSION_ENABLED", expansion)


def test_policy_token_defaults_are_exactly_policy_v3(monkeypatch):
    _flags(monkeypatch)
    assert policy_version_token() == "policy_v3"


def test_policy_token_is_distinct_for_every_flag_combination(monkeypatch):
    seen = {}
    for mastery, kg, expansion in itertools.product([False, True], repeat=3):
        _flags(monkeypatch, mastery, kg, expansion)
        expected = "policy_v3" + ("+kg_mastery" if mastery else "") + ("" if kg else "+kg_off") + ("" if expansion else "+kg_noexp")
        assert policy_version_token() == expected
        seen[(mastery, kg, expansion)] = expected
    assert len(set(seen.values())) == 8


def test_default_certificate_and_request_carry_policy_v3(monkeypatch):
    _flags(monkeypatch)
    certificate = cache_mod._build_admissibility_certificate(
        state={"user_input": "Who founded ExampleCo?"},
        fingerprint={"query_norm": "who founded exampleco?", "intent": "ask", "level": "B1"},
        profile_epoch=1,
        state_hints={},
        now=time.time(),
        user_scope="u",
    )
    assert certificate["policy_version"] == "policy_v3"
    override = cache_mod._build_admissibility_certificate(
        state={"user_input": "Who founded ExampleCo?"},
        fingerprint={"query_norm": "who founded exampleco?", "intent": "ask", "level": "B1"},
        profile_epoch=1,
        state_hints={"policy_version": "pinned"},
        now=time.time(),
        user_scope="u",
    )
    assert override["policy_version"] == "pinned"


class _DictRedis:
    def __init__(self) -> None:
        self.store: dict[str, str] = {}

    async def get(self, key):
        return self.store.get(key)

    async def set(self, key, value, ex=None):
        self.store[key] = value


def _cache_user(monkeypatch):
    monkeypatch.setattr(settings, "SECRET_KEY", "test-secret")
    monkeypatch.setattr(settings, "LEARNER_STATE_MODE", "off")


GATE_STATE = {
    "user_id": "gate-user",
    "user_input": "Who founded ExampleCo?",
    "session_id": "s-gate",
    "learner_profile": {"level": "B1"},
    "conversation_history": [],
    "cache_policy": "on",
    "retrieval_trace": [{"item_id": "exampleco", "title": "ExampleCo"}],
}


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "field, flipped",
    [("KG_MASTERY_TRAVERSAL", True), ("KG_ENABLED", False), ("KG_EXPANSION_ENABLED", False)],
)
async def test_l0_entry_written_under_one_flag_value_is_rejected_after_the_flip(monkeypatch, field, flipped):
    _flags(monkeypatch)
    _cache_user(monkeypatch)
    fake = _DictRedis()

    async def get_instance():
        return fake

    monkeypatch.setattr(RedisClient, "get_instance", get_instance)
    cache_mod._MEM_RESPONSE_CACHE.clear()

    await cache_mod._write_cache_entry(
        dict(GATE_STATE), "Ada Example founded ExampleCo.", "qa", [], 1.0, "", model_used="groq/x"
    )
    assert fake.store, "nothing was written"

    same = await cache_mod.cache_gate_node(dict(GATE_STATE))
    assert (same["cache_decision"], same.get("cache_layer")) == ("reuse", "L0")

    monkeypatch.setattr(settings, field, flipped)
    after = await cache_mod.cache_gate_node(dict(GATE_STATE))
    assert after["cache_decision"] == "full" and not after["cache_hit"]
    assert "mismatch:policy_version" in after["cache_gate_meta"]["reasons"]


# ── kg_expand_node ──────────────────────────────────────────────────────────

STATES = {
    "concept:x": {"mastery_probability": 1.0},
    "concept:y": {"mastery_probability": 0.0},
}


@pytest.fixture()
def node_env(monkeypatch, xy):
    client = mock.create_autospec(LearnerStateClient, instance=True)
    client.batch_get.return_value = LearnerStateResult(states=STATES)
    with ExitStack() as stack:
        stack.enter_context(mock.patch.object(
            KnowledgeGraphServiceV3, "semantic_seed_concepts", autospec=True, return_value=["concept:s"]))
        stack.enter_context(mock.patch.object(
            KnowledgeGraphServiceV3, "get_seed_concepts_fast", autospec=True, return_value=[]))
        stack.enter_context(mock.patch.object(
            KnowledgeGraphServiceV3, "get_kg_content_version", autospec=True, return_value="v1"))
        stack.enter_context(mock.patch(
            "api.services.kg_service_v3.get_kg_service", autospec=True, return_value=xy))
        stack.enter_context(mock.patch(
            "api.clients.learner_state_client.get_learner_state_client", autospec=True, return_value=client))
        yield types.SimpleNamespace(kg=xy, client=client)


def _state(user_id="u1"):
    state = {"user_input": "zzz", "learner_profile": {"level": "B1"}}
    if user_id:
        state["user_id"] = user_id
    return state


def _on(monkeypatch, mode="read"):
    monkeypatch.setattr(settings, "KG_MASTERY_TRAVERSAL", True)
    monkeypatch.setattr(settings, "LEARNER_STATE_MODE", mode)


@pytest.mark.asyncio
async def test_personalised_turn_is_recorded_and_reorders(node_env, monkeypatch):
    base = await nodes_v2.kg_expand_node(_state())
    assert [n["id"] for n in base["kg_expanded_nodes"]] == ["concept:x", "concept:y"]
    assert "personalised" not in base["graph_update"]

    _on(monkeypatch)
    out = await nodes_v2.kg_expand_node(_state())
    assert [n["id"] for n in out["kg_expanded_nodes"]] == ["concept:y", "concept:x"]
    update = out["graph_update"]
    assert (update["personalised"], update["n_states"], update["reason"]) == (True, 2, "ok")
    requested = node_env.client.batch_get.await_args.args[1]
    assert requested[0] == "concept:s" and set(requested) == {"concept:s", "concept:x", "concept:y"}


FAIL_OPEN = {
    "flag_off": ({"flag": False}, "flag_off"),
    "mode_off": ({"mode": "off"}, "mode_off"),
    "mode_shadow": ({"mode": "shadow"}, "mode_off"),
    "no_user_id": ({"user": None}, "no_user"),
    "degraded": ({"result": LearnerStateResult(degraded=True, reason="timeout")}, "no_states"),
    "client_raises": ({"error": RuntimeError("down")}, "no_states"),
    "empty_states": ({"result": LearnerStateResult(states={})}, "no_states"),
    "no_mastery_field": ({"result": LearnerStateResult(states={"concept:y": {"mastery_probability": None}})}, "no_states"),
}


@pytest.mark.asyncio
@pytest.mark.parametrize("case", FAIL_OPEN)
async def test_fail_open_equals_flag_off(node_env, redis, monkeypatch, case):
    cfg, reason = FAIL_OPEN[case]
    baseline = await nodes_v2.kg_expand_node(_state())
    redis.reset()

    if cfg.get("flag", True):
        _on(monkeypatch, cfg.get("mode", "read"))
    if "result" in cfg:
        node_env.client.batch_get.return_value = cfg["result"]
    if "error" in cfg:
        node_env.client.batch_get.side_effect = cfg["error"]
    out = await nodes_v2.kg_expand_node(_state(cfg.get("user", "u1")))

    for key in ("kg_seed_concepts", "kg_expanded_nodes", "kg_paths"):
        assert out[key] == baseline[key]
    assert [n["id"] for n in out["kg_expanded_nodes"]] == ["concept:x", "concept:y"]
    if cfg.get("flag", True):
        assert out["graph_update"]["personalised"] is False
        assert out["graph_update"]["reason"] == reason
    if reason in {"flag_off", "mode_off", "no_user"}:
        node_env.client.batch_get.assert_not_awaited()


@pytest.mark.asyncio
async def test_personalised_result_never_touches_the_shared_subgraph_key(node_env, redis, monkeypatch):
    shared = _shared_key(["concept:s"], "B1", 2, 10)
    candidate = _shared_key(["concept:s"], "B1", 2, 40)
    _on(monkeypatch)

    node_env.client.batch_get.return_value = LearnerStateResult(
        states={"concept:x": {"mastery_probability": 0.0}, "concept:y": {"mastery_probability": 1.0}}
    )
    learner_a = await nodes_v2.kg_expand_node(_state("a"))
    node_env.client.batch_get.return_value = LearnerStateResult(states=STATES)
    learner_b = await nodes_v2.kg_expand_node(_state("b"))
    assert [n["id"] for n in learner_a["kg_expanded_nodes"]] == ["concept:x", "concept:y"]
    assert [n["id"] for n in learner_b["kg_expanded_nodes"]] == ["concept:y", "concept:x"]

    assert shared not in redis.gets and shared not in redis.sets
    assert set(redis.gets) | set(redis.sets) == {candidate}

    anonymous = await nodes_v2.kg_expand_node(_state(None))
    assert [n["id"] for n in anonymous["kg_expanded_nodes"]] == ["concept:x", "concept:y"]
    assert [n["id"] for n in json.loads(redis.store[shared])["nodes"]] == ["concept:x", "concept:y"]


# ── seeds ───────────────────────────────────────────────────────────────────

def test_grammar_seed_patterns_are_pinned():
    items = list(nodes_v2.GRAMMAR_SEED_PATTERNS.items())
    assert len(items) == 42
    digest = hashlib.sha256(json.dumps(items, ensure_ascii=False).encode()).hexdigest()
    assert digest == "e54406da24657754e804b9fb02f2fdea09de351597411945b0806e78f9581b98"


SEED_HEAD = ["concept:grammar.third_person_s", "concept:topic.a", "concept:vocab.word.b"]
SENTENCES = [
    ("He go to school yesterday and I very like it", ["concept:error.article_omission", "concept:error.word_order_svo"]),
    ("Have you been working on social media posts?", ["concept:vocab.social_media"]),
    (
        "I wish I had gone; if I had known, I would have come.",
        ["concept:grammar.conditionals_third", "concept:grammar.wish_regret"],
    ),
    (
        "What do you want? This book is Anna's book",
        ["concept:grammar.question_words", "concept:grammar.demonstratives", "concept:grammar.possessive_s"],
    ),
    ("hello world", []),
]


@pytest.mark.asyncio
@pytest.mark.parametrize("sentence, regex_hits", SENTENCES)
async def test_collect_seed_concepts_matches_what_kg_expand_node_emits(monkeypatch, sentence, regex_hits):
    kg = mock.create_autospec(KnowledgeGraphServiceV3, instance=True)
    kg.semantic_seed_concepts.return_value = ["concept:grammar.third_person_s", "concept:topic.a"]
    kg.get_seed_concepts_fast.return_value = ["concept:topic.a", "concept:vocab.word.b"]
    kg.get_kg_content_version.return_value = "v1"
    kg.expand_best_first.return_value = KGHits(seed_nodes=[], expanded_nodes=[], paths=[])
    monkeypatch.setattr("api.services.kg_service_v3.get_kg_service", lambda: kg)

    out = await nodes_v2.kg_expand_node({"user_input": sentence, "learner_profile": {"level": "B1"}})
    seeds = nodes_v2.collect_seed_concepts(kg, sentence, "B1")

    assert seeds == SEED_HEAD + regex_hits
    assert out["kg_seed_concepts"] == SEED_HEAD + regex_hits


def test_collect_seed_concepts_sources_and_regex_order():
    kg = mock.create_autospec(KnowledgeGraphServiceV3, instance=True)
    kg.semantic_seed_concepts.return_value = ["concept:sem"]
    kg.get_seed_concepts_fast.return_value = ["concept:kw"]
    text = "He go to school. I very like it"
    regex_only = nodes_v2.collect_seed_concepts(kg, text, "B1", sources=("regex",))
    assert regex_only[:2] == ["concept:grammar.third_person_s", "concept:error.article_omission"]
    assert "concept:error.word_order_svo" in regex_only
    assert nodes_v2.collect_seed_concepts(kg, text, "B1", sources=("semantic",)) == ["concept:sem"]
    assert nodes_v2.collect_seed_concepts(kg, text, "B1", sources=("keyword",)) == ["concept:kw"]
    assert nodes_v2.collect_seed_concepts(kg, text, "B1")[:2] == ["concept:sem", "concept:kw"]


# ── switches ────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_kg_disabled_returns_the_empty_shape_without_touching_kuzu(monkeypatch):
    monkeypatch.setattr(settings, "KG_ENABLED", False)
    getter = mock.patch("api.services.kg_service_v3.get_kg_service", autospec=True)
    with getter as get_kg:
        out = await nodes_v2.kg_expand_node({"user_input": "He go to school", "learner_profile": {"level": "B1"}})
    get_kg.assert_not_called()
    assert out["kg_seed_concepts"] == [] and out["kg_expanded_nodes"] == [] and out["kg_paths"] == []
    assert out["graph_update"]["nodes_added"] == 0 and out["graph_update"]["edges_added"] == 0
    assert "dependency_events" not in out and "models_used" not in out


@pytest.mark.asyncio
async def test_expansion_disabled_keeps_seeds_and_skips_the_walk(monkeypatch):
    monkeypatch.setattr(settings, "KG_EXPANSION_ENABLED", False)
    kg = mock.create_autospec(KnowledgeGraphServiceV3, instance=True)
    kg.semantic_seed_concepts.return_value = ["concept:sem"]
    kg.get_seed_concepts_fast.return_value = []
    kg.get_kg_content_version.return_value = "v1"
    monkeypatch.setattr("api.services.kg_service_v3.get_kg_service", lambda: kg)
    out = await nodes_v2.kg_expand_node({"user_input": "He go to school", "learner_profile": {"level": "B1"}})
    kg.expand_best_first.assert_not_awaited()
    assert "concept:sem" in out["kg_seed_concepts"] and "concept:grammar.third_person_s" in out["kg_seed_concepts"]
    assert out["kg_expanded_nodes"] == [] and out["kg_paths"] == []
    assert out["dependency_events"]


async def _retrieve(monkeypatch, tag):
    kg = mock.create_autospec(KnowledgeGraphServiceV3, instance=True)
    kg.query_concepts.return_value = [{"id": "kg:concept.1", "title": "KG Concept", "keywords": "kg", "score": 0.5}]
    stage2 = mock.create_autospec(RetrievalServiceV3, instance=True)
    stage2.retrieve.return_value = RetrievalBundleV3(
        query="q", vector_hits=[VectorHit(id="vec:1", score=0.8, snippet="vector evidence")]
    )
    doc = mock.create_autospec(DocumentIntelligenceService, instance=True)
    doc.query_l2.return_value = []
    monkeypatch.setattr("api.services.kg_service_v3.get_kg_service", lambda: kg)
    _stub(monkeypatch, retrieve_mod, "_get_retrieval_v3", return_value=stage2)
    _stub(monkeypatch, retrieve_mod, "get_doc_intel_service", return_value=doc)
    monkeypatch.setattr(retrieve_mod, "_kg_cache_get", lambda key: None)
    monkeypatch.setattr(retrieve_mod, "_kg_cache_set", lambda key, data: None)
    result = await retrieve_mod.retrieve_node({
        "user_input": f"I would like to practise booking a hotel room. {tag}",
        "session_id": f"session-{tag}",
        "user_id": "user-1",
        "retrieval_policy": "rapid",
        "learner_profile": {"level": "B1"},
        "conversation_history": [],
        "diagnosis_root_causes": ["concept:present_perfect"],
        "diagnosis_errors": [{"span": "go", "correction": "went", "explanation": "past tense"}],
        "diagnosis_confidence": 0.9,
        "kg_seed_concepts": ["concept:present_perfect"],
        "kg_expanded_nodes": [],
    })
    text = " ".join(item.get("text", "") for item in result["retrieval_trace"])
    return kg, stage2, doc, text


@pytest.mark.asyncio
async def test_kg_disabled_skips_query_concepts_and_stage2_but_keeps_diagnosis(monkeypatch):
    monkeypatch.setattr(settings, "KG_ENABLED", False)
    kg, stage2, doc, text = await _retrieve(monkeypatch, "kg-off")
    kg.query_concepts.assert_not_called()
    stage2.retrieve.assert_not_awaited()
    doc.query_l2.assert_awaited_once()
    assert "Grammar concept: concept:present_perfect" in text
    assert "Error: 'go'" in text
    assert "vector evidence" not in text


@pytest.mark.asyncio
@pytest.mark.parametrize("expansion", [True, False])
async def test_expansion_switch_leaves_query_concepts_and_stage2_alone(monkeypatch, expansion):
    monkeypatch.setattr(settings, "KG_EXPANSION_ENABLED", expansion)
    kg, stage2, doc, text = await _retrieve(monkeypatch, f"exp-{expansion}")
    kg.query_concepts.assert_called_once()
    stage2.retrieve.assert_awaited_once()
    doc.query_l2.assert_not_awaited()
    assert "vector evidence" in text and "Error: 'go'" in text


# ── usage ledger ────────────────────────────────────────────────────────────

def test_ledger_is_a_no_op_without_an_active_ledger():
    assert _USAGE_LEDGER.get() is None
    assert _ledger_add("tutor", {"usage": {"total_tokens": 9}}, wall_started=time.monotonic()) is None
    assert _USAGE_LEDGER.get() is None
    with usage_ledger() as entries:
        _ledger_add("tutor", {"usage": {"prompt_tokens": 4, "completion_tokens": 5}}, wall_started=time.monotonic())
    assert [(e["role"], e["total_tokens"]) for e in entries] == [("tutor", 9)]


@pytest.mark.asyncio
async def test_diagnose_groq_call_is_recorded_under_its_role(monkeypatch):
    response = types.SimpleNamespace(
        status_code=200,
        elapsed=timedelta(milliseconds=120),
        text="",
        json=lambda: {
            "choices": [{"message": {"content": '{"errors": [], "intent": "ask"}'}}],
            "usage": {"prompt_tokens": 30, "completion_tokens": 12, "total_tokens": 42},
        },
    )
    gateway = mock.create_autospec(ModelGateway, instance=True)
    gateway.execute_task.side_effect = RuntimeError("no local model")
    _stub(monkeypatch, nodes_v2, "get_gateway", return_value=gateway)
    _stub(monkeypatch, groq_key_pool, "get_available_groq_key", return_value="k")
    _stub(monkeypatch, groq_key_pool, "record_groq_key_usage")
    _stub(monkeypatch, nodes_v2, "_throttled_post_json", return_value=response)

    with usage_ledger() as entries:
        await nodes_v2.diagnose_node({"user_input": "I like cats", "learner_profile": {"level": "B1"}})
    assert [(e["role"], e["total_tokens"], e["http_ms"]) for e in entries] == [("diagnose", 42, 120)]

    entries.clear()
    await nodes_v2.diagnose_node({"user_input": "I like cats", "learner_profile": {"level": "B1"}})
    assert entries == []


TUTOR_STATE = {
    "user_input": "I need check in.",
    "session_id": "sess-ledger",
    "learner_profile": {"level": "A2"},
    "conversation_history": [],
    "diagnosis_errors": [],
    "diagnosis_intent": "correct",
    "fluency_score": 0.9,
    "grammar_score": 0.9,
    "vocabulary_level": "A2",
    "retrieved_context": "",
    "cache_policy": "off",
}


def _tutor_env(monkeypatch, env):
    import api.services.trace_cag.generate as generate

    response = types.SimpleNamespace(
        status_code=200,
        json=lambda: {
            "choices": [{"message": {"content": "May I see your passport?"}}],
            "usage": {"prompt_tokens": 40, "completion_tokens": 10, "total_tokens": 50},
        },
    )
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setenv("TRACECAG_ENABLE_LOCAL_LLAMA_KV", "false")
    if env is None:
        monkeypatch.delenv("TRACECAG_TUTOR_TEMPERATURE", raising=False)
    else:
        monkeypatch.setenv("TRACECAG_TUTOR_TEMPERATURE", env)
    _stub(monkeypatch, groq_key_pool, "get_available_groq_key", return_value="groq-key")
    _stub(monkeypatch, groq_key_pool, "record_groq_key_usage")
    post = _stub(monkeypatch, generate, "_throttled_post_json", return_value=response)
    return generate, post


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "env, expected",
    [(None, 0.7), ("0.0", 0.0), ("abc", 0.7), ("", 0.7)],
)
async def test_tutor_call_is_recorded_and_temperature_is_overridable(monkeypatch, env, expected):
    generate, post = _tutor_env(monkeypatch, env)

    with usage_ledger() as entries:
        result = await generate.generate_node(dict(TUTOR_STATE))

    post.assert_awaited_once()
    assert post.await_args.kwargs["payload"]["temperature"] == expected
    assert result["tutor_response"] == "May I see your passport?"
    assert [(e["role"], e["total_tokens"]) for e in entries] == [("tutor", 50)]

    await generate.generate_node(dict(TUTOR_STATE))
    assert _USAGE_LEDGER.get() is None


# ── fail-closed on cancellation, gather, state ──────────────────────────────

@pytest.mark.asyncio
async def test_cancellation_is_not_swallowed_by_the_mastery_lookup(node_env, monkeypatch):
    _on(monkeypatch)
    node_env.client.batch_get.side_effect = asyncio.CancelledError()
    with pytest.raises(asyncio.CancelledError):
        await nodes_v2._traversal_mastery(_state(), node_env.kg, ["concept:s"], "B1")


@pytest.mark.asyncio
async def test_a_failing_gate_still_returns_empty(node_env, monkeypatch):
    _on(monkeypatch)
    monkeypatch.setattr(nodes_v2, "_traversal_off_reason", mock.create_autospec(nodes_v2._traversal_off_reason, side_effect=RuntimeError("x")))
    assert await nodes_v2._traversal_mastery(_state(), node_env.kg, ["concept:s"], "B1") == {}


@pytest.mark.asyncio
async def test_flag_on_with_expansion_off_never_reads_learner_state_for_the_walk(node_env, monkeypatch):
    _on(monkeypatch)
    monkeypatch.setattr(settings, "KG_EXPANSION_ENABLED", False)
    out = await nodes_v2.kg_expand_node(_state())
    node_env.client.batch_get.assert_not_awaited()
    assert out["kg_seed_concepts"] == ["concept:s"] and out["kg_expanded_nodes"] == []
    assert out["graph_update"]["personalised"] is False
    assert out["graph_update"]["reason"] == "expansion_off"


@pytest.fixture()
def gathered(node_env, monkeypatch):
    _stub(monkeypatch, nodes_v2, "diagnose_node", return_value={"diagnosis_root_causes": [], "models_used": ["d"]})
    _stub(monkeypatch, nodes_v2, "_jit_graph_extract_node", return_value={"jit_soft_graph": None, "jit_graph_meta": {}})
    return node_env


@pytest.mark.asyncio
async def test_kg_diagnose_node_carries_the_personalised_walk_and_the_overlay(gathered, monkeypatch):
    _on(monkeypatch)
    merged = await nodes_v2.kg_diagnose_node(_state())
    assert [n["id"] for n in merged["kg_expanded_nodes"]] == ["concept:y", "concept:x"]
    assert merged["graph_update"]["personalised"] is True
    assert merged["learner_concept_states"] == STATES
    assert gathered.client.batch_get.await_count == 2
    assert merged["models_used"] == ["kuzu_kg_bestfirst", "d"]


@pytest.mark.asyncio
async def test_graph_update_survives_the_compiled_graph_and_the_response_format(gathered, monkeypatch):
    _on(monkeypatch)
    graph = StateGraph(TraceCAGState)
    graph.add_node("kg_diagnose_node", nodes_v2.kg_diagnose_node)
    graph.set_entry_point("kg_diagnose_node")
    graph.add_edge("kg_diagnose_node", END)
    initial = create_initial_state(user_input="zzz", session_id="s", user_id="u1")
    final = await graph.compile().ainvoke(initial)
    update = final["graph_update"]
    assert (update["personalised"], update["n_states"], update["reason"]) == (True, 2, "ok")

    pipeline = TraceCAGPipeline.__new__(TraceCAGPipeline)
    metadata = pipeline._format_response(final)["metadata"]
    assert metadata["graph_update"]["personalised"] is True
    assert metadata["graph_update"]["n_states"] == 2
