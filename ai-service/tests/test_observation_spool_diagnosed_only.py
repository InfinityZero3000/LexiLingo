import asyncio
import copy
import hashlib
from contextlib import ExitStack
from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, create_autospec, patch

import pytest

from api.core.config import Settings, settings
from api.services import learner_observation_spool as spool_module
from api.services.learner_observation_spool import (
    _ALLOWED_PAYLOAD_KEYS,
    LearnerObservation,
    LearnerObservationSpool,
    SpoolPersistResult,
    _sanitized_payload,
    deterministic_event_id,
    persist_trace_observations,
)
from api.services.trace_cag.graph import TraceCAGPipeline

FIXED = datetime(2026, 11, 6, 12, 0, 0, tzinfo=UTC)
USER, SESSION, TURN = "user-1", "session-1", "turn-1"
ANCHOR_EVENT_TURN_1 = "571cef7fafdc16dcb68daebe2ab14e3a55a685c3291a7ac1316ee6bb11e03b50"
ANCHOR_EVENT_TURN_2 = "e385bee0e4b26ca5d4b891bc77f13e4a82e499b34225aebcc37dcf70b32220c5"
ANCHOR_EVENT_TURN_3 = "e8a29806c594831ca5017ad12b0178e16701b772ef6d52d0d114b355700af363"
G01_EVENT_TURN_1 = "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"


class _Frozen(datetime):
    @classmethod
    def now(cls, tz=None):
        return FIXED


def _state(seeds=(), root=(), errors=0, linked=None):
    state = {
        "user_input": "w0 w1 w2 w3 w4 w5",
        "kg_seed_concepts": list(seeds),
        "diagnosis_root_causes": list(root),
        "diagnosis_errors": [
            {"span": f"w{i}", "correction": f"c{i}", "type": "grammar", "explanation": f"e{i}"}
            for i in range(errors)
        ],
    }
    if linked is not None:
        state["linked_concepts"] = list(linked)
    return state


def _shaped(state: dict, shape: str) -> dict:
    state = copy.deepcopy(state)
    if shape == "formatted":
        return TraceCAGPipeline._format_response(SimpleNamespace(), state)
    return state


def _fake(durable: bool = True):
    stored: dict[str, LearnerObservation] = {}
    fake = create_autospec(LearnerObservationSpool, instance=True)

    async def persist_many(observations):
        results = []
        for item in observations:
            event_id = deterministic_event_id(item)
            results.append(
                SpoolPersistResult(
                    event_id=event_id, durable=durable, duplicate=event_id in stored
                )
            )
            stored.setdefault(event_id, item)
        return results

    fake.persist_many.side_effect = persist_many
    return fake, stored


def _run(
    trace_result,
    *,
    skill="writing",
    difficulty="B1",
    mode="read",
    flag=True,
    user=USER,
    turn=TURN,
    fake=None,
    manager=None,
):
    fake = fake or _fake()[0]
    manager = manager or MagicMock()
    with ExitStack() as stack:
        stack.enter_context(patch.object(settings, "LEARNER_STATE_MODE", mode))
        stack.enter_context(patch.object(settings, "LEARNER_OBSERVATION_DIAGNOSED_ONLY", flag))
        stack.enter_context(patch.object(spool_module, "datetime", _Frozen))
        stack.enter_context(
            patch.object(
                spool_module, "get_learner_observation_spool", autospec=True, return_value=fake
            )
        )
        stack.enter_context(patch("api.core.database.mongodb_manager", manager))
        returned = asyncio.run(
            persist_trace_observations(
                user_id=user,
                session_id=SESSION,
                turn_id=turn,
                trace_result=trace_result,
                skill=skill,
                difficulty_level=difficulty,
            )
        )
    sent = [c.args[0] for c in fake.persist_many.call_args_list]
    return returned, (sent[0] if sent else None), fake


def _rows(observations):
    return [[o.concept_id, o.outcome, o.confidence, o.payload] for o in observations]


def _anchor(skill, outcome, confidence, error_count, score, difficulty=None):
    payload = {"error_count": error_count, "skill": skill, "score": score}
    if difficulty:
        payload["difficulty_level"] = difficulty
    return [f"skill:{skill}", outcome, confidence, payload]


def _root(concept_id, error_count):
    return [concept_id, "incorrect", 0.8, {"error_count": error_count}]


T17 = [f"concept:t{i:02d}" for i in range(1, 18)]

CASES = {
    "err17_rc": (
        _state(T17, ["concept:g01", "concept:t03"], 2),
        "writing",
        "B1",
        [_anchor("writing", "incorrect", 0.8, 2, 50.0, "B1"), _root("concept:g01", 2), _root("concept:t03", 2)],
    ),
    "err17_norc": (
        _state(T17, [], 2),
        "writing",
        "B1",
        [_anchor("writing", "incorrect", 0.8, 2, 50.0, "B1")],
    ),
    "err17_rc_noskill": (
        _state(T17, ["concept:g01"], 2),
        None,
        None,
        [_root("concept:g01", 2)],
    ),
    "err17_norc_noskill": (_state(T17, [], 2), None, None, []),
    "clean": (
        _state(T17[:5], [], 0),
        "writing",
        "B1",
        [_anchor("writing", "correct", 0.6, 0, 100.0, "B1")],
    ),
    "clean_noskill": (_state(T17[:5], [], 0), None, None, []),
    "clean_with_root_causes_ignored": (
        _state(T17[:5], ["concept:g01"], 0),
        "writing",
        "B1",
        [_anchor("writing", "correct", 0.6, 0, 100.0, "B1")],
    ),
    "noconcept_skill": (
        _state([], [], 0),
        "speaking",
        "A2",
        [_anchor("speaking", "correct", 0.6, 0, 100.0, "A2")],
    ),
    "noconcept_skill_err3": (
        _state([], [], 3),
        "speaking",
        "A2",
        [_anchor("speaking", "incorrect", 0.8, 3, 25.0, "A2")],
    ),
    "skill_no_difficulty": (
        _state(T17[:3], ["concept:g01"], 1),
        "writing",
        None,
        [_anchor("writing", "incorrect", 0.8, 1, 75.0), _root("concept:g01", 1)],
    ),
    "score_floor_err4": (
        _state([], [], 4),
        "writing",
        "C1",
        [_anchor("writing", "incorrect", 0.8, 4, 0.0, "C1")],
    ),
    "score_cap_err6": (
        _state([], [], 6),
        "writing",
        "C1",
        [_anchor("writing", "incorrect", 0.8, 6, 0.0, "C1")],
    ),
    "dedupe_order": (
        _state(
            ["concept:a", "concept:z"],
            ["concept:c", "concept:a", "concept:c", None, "", "concept:b"],
            1,
            linked=["concept:z"],
        ),
        "writing",
        "B1",
        [
            _anchor("writing", "incorrect", 0.8, 1, 75.0, "B1"),
            _root("concept:c", 1),
            _root("concept:a", 1),
            _root("concept:b", 1),
        ],
    ),
}

SHAPES = ("raw", "formatted")
GRID = [(case, shape) for case in CASES for shape in SHAPES]
GRID_IDS = [f"{c}|{s}" for c, s in GRID]


@pytest.mark.parametrize(("case", "shape"), GRID, ids=GRID_IDS)
def test_flag_on_matches_literal_for_both_shapes(case, shape):
    state, skill, difficulty, expected = CASES[case]
    returned, sent, fake = _run(_shaped(state, shape), skill=skill, difficulty=difficulty)
    assert returned == {
        "observation_count": len(expected),
        "observation_durability_degraded": False,
    }
    if expected:
        assert _rows(sent) == expected
        assert {o.observed_at for o in sent} == {FIXED}
        assert {o.observation_kind for o in sent} == {"tracecag_turn"}
        assert {(o.user_id, o.session_id, o.turn_id) for o in sent} == {(USER, SESSION, TURN)}
    else:
        fake.persist_many.assert_not_called()


@pytest.mark.parametrize(("case", "shape"), GRID, ids=GRID_IDS)
def test_seeds_and_linked_concepts_never_appear(case, shape):
    state, skill, difficulty, _ = CASES[case]
    _, sent, _ = _run(_shaped(state, shape), skill=skill, difficulty=difficulty)
    recorded = {o.concept_id for o in sent or []}
    topic = set(state["kg_seed_concepts"]) | set(state.get("linked_concepts", []))
    assert recorded.isdisjoint(topic - set(state["diagnosis_root_causes"]))
    for item in sent or []:
        if not item.concept_id.startswith("skill:"):
            assert item.concept_id in state["diagnosis_root_causes"]
            assert (item.outcome, item.confidence) == ("incorrect", 0.8)


@pytest.mark.parametrize("case", sorted(CASES))
def test_both_shapes_give_identical_lists(case):
    state, skill, difficulty, expected = CASES[case]
    raw_sent = _run(_shaped(state, "raw"), skill=skill, difficulty=difficulty)[1]
    formatted_sent = _run(_shaped(state, "formatted"), skill=skill, difficulty=difficulty)[1]
    assert _rows(formatted_sent or []) == _rows(raw_sent or []) == expected


@pytest.mark.parametrize(
    "trace_result",
    [{"tutor_response": "", "error": "boom", "metadata": {"path": "error"}}, {}],
    ids=["pipeline_error", "empty"],
)
def test_neither_shape_sends_nothing_not_even_the_anchor(trace_result):
    returned, sent, fake = _run(trace_result)
    assert returned == {"observation_count": 0, "observation_durability_degraded": False}
    assert sent is None
    fake.persist_many.assert_not_called()


def test_shape_detection_prefers_raw_keys_when_both_are_present():
    state = _state(T17[:2], ["concept:raw"], 1)
    state["corrections"] = [{"error": "x"}, {"error": "y"}, {"error": "z"}]
    state["weak_concepts"] = ["concept:formatted"]
    _, sent, _ = _run(state)
    assert _rows(sent) == [
        _anchor("writing", "incorrect", 0.8, 1, 75.0, "B1"),
        _root("concept:raw", 1),
    ]


def test_formatted_shape_reads_corrections_and_weak_concepts():
    state = {
        "tutor_response": "t",
        "corrections": [{"error": "x"}, {"error": "y"}],
        "linked_concepts": ["concept:topic"],
        "weak_concepts": ["concept:weak"],
    }
    _, sent, _ = _run(state)
    assert _rows(sent) == [
        _anchor("writing", "incorrect", 0.8, 2, 50.0, "B1"),
        _root("concept:weak", 2),
    ]


def test_formatted_without_corrections_is_clean():
    state = {"tutor_response": "t", "corrections": [], "linked_concepts": ["concept:topic"], "weak_concepts": []}
    _, sent, _ = _run(state)
    assert _rows(sent) == [_anchor("writing", "correct", 0.6, 0, 100.0, "B1")]


@pytest.mark.parametrize("shape", SHAPES)
def test_cap_60_keeps_the_anchor_first(shape):
    roots = [f"concept:g{i:02d}" for i in range(1, 71)]
    state = _state(T17, roots, 1)
    _, sent, _ = _run(_shaped(state, shape))
    assert len(sent) == 60
    assert sent[0].concept_id == "skill:writing"
    assert sent[1].concept_id == "concept:g01"
    assert sent[-1].concept_id == "concept:g59"
    _, sent, _ = _run(_shaped(state, shape), skill=None, difficulty=None)
    assert len(sent) == 60
    assert sent[0].concept_id == "concept:g01"
    assert sent[-1].concept_id == "concept:g60"


@pytest.mark.parametrize("shape", SHAPES)
@pytest.mark.parametrize(
    ("kwargs", "label"),
    [
        ({"mode": "off"}, "mode_off"),
        ({"user": ""}, "empty_user"),
        ({"user": None}, "none_user"),
        ({"turn": ""}, "empty_turn"),
        ({"turn": None}, "none_turn"),
    ],
)
@pytest.mark.parametrize("flag", [False, True])
def test_off_mode_and_missing_ids_send_nothing(shape, kwargs, label, flag):
    state = _state(T17, ["concept:g01"], 2)
    returned, sent, fake = _run(_shaped(state, shape), flag=flag, **kwargs)
    assert returned == {"observation_count": 0, "observation_durability_degraded": False}
    assert sent is None
    fake.persist_many.assert_not_called()


def test_anchor_event_id_ignores_the_diagnosis():
    ids = []
    for root in ([], ["concept:g01"], ["concept:g01", "concept:t03"]):
        _, sent, _ = _run(_state(T17, root, 2))
        ids.append(deterministic_event_id(sent[0]))
    assert ids == [ANCHOR_EVENT_TURN_1] * 3
    _, sent, _ = _run(_state(T17, ["concept:g01"], 0))
    assert deterministic_event_id(sent[0]) == ANCHOR_EVENT_TURN_1
    _, sent, _ = _run(_state(T17, ["concept:g01"], 2))
    assert deterministic_event_id(sent[1]) == G01_EVENT_TURN_1


def test_replaying_a_turn_is_deduplicated_by_event_id():
    fake, stored = _fake()
    state = _state(T17, ["concept:g01", "concept:t03"], 2)
    _run(state, fake=fake)
    _run(state, fake=fake)
    assert len(stored) == 3
    assert set(stored) >= {ANCHOR_EVENT_TURN_1, G01_EVENT_TURN_1}
    results = asyncio.run(fake.persist_many(list(stored.values())))
    assert [r.duplicate for r in results] == [True, True, True]


def test_three_turns_give_three_anchor_events_and_no_topic_rows():
    fake, stored = _fake()
    for turn in ("turn-1", "turn-2", "turn-3"):
        _run(_state(T17, ["concept:g01"], 1), fake=fake, turn=turn)
    anchors = [e for e, o in stored.items() if o.concept_id == "skill:writing"]
    assert sorted(anchors) == sorted([ANCHOR_EVENT_TURN_1, ANCHOR_EVENT_TURN_2, ANCHOR_EVENT_TURN_3])
    rows = {o.concept_id for o in stored.values()}
    assert rows == {"skill:writing", "concept:g01"}
    assert rows.isdisjoint(T17)


@pytest.mark.parametrize(("case", "shape"), GRID, ids=GRID_IDS)
def test_payloads_satisfy_the_backend_contract(case, shape):
    state, skill, difficulty, _ = CASES[case]
    _, sent, _ = _run(_shaped(state, shape), skill=skill, difficulty=difficulty)
    for item in sent or []:
        assert set(item.payload) <= _ALLOWED_PAYLOAD_KEYS
        assert _sanitized_payload(item.payload) == item.payload
        assert 0 < len(item.concept_id) <= 255
        assert item.outcome in {"correct", "incorrect"}
        assert 0.0 <= item.confidence <= 1.0
        assert item.observation_kind == "tracecag_turn"


def test_degraded_delivery_writes_the_marker_with_the_new_list():
    collection = MagicMock(update_one=AsyncMock())
    manager = MagicMock()
    manager.db.__getitem__.side_effect = lambda name: collection
    state = _state(T17, ["concept:g01"], 2)
    returned, sent, _ = _run(state, fake=_fake(durable=False)[0], manager=manager)
    assert returned == {"observation_count": 2, "observation_durability_degraded": True}
    args, kwargs = collection.update_one.await_args
    assert args[0] == {"observation_reconcile.turn_id": TURN}
    marker = args[1]["$setOnInsert"]["observation_reconcile"]
    assert [o["concept_id"] for o in marker["observations"]] == ["skill:writing", "concept:g01"]
    assert [o["event_id"] for o in marker["observations"]] == [ANCHOR_EVENT_TURN_1, G01_EVENT_TURN_1]
    assert kwargs == {"upsert": True}


def test_flag_defaults_off_and_does_not_enter_the_cache_policy_token():
    from api.services.trace_cag.dependencies import policy_version_token

    assert Settings.model_fields["LEARNER_OBSERVATION_DIAGNOSED_ONLY"].default is False
    with patch.object(settings, "LEARNER_OBSERVATION_DIAGNOSED_ONLY", False):
        off = policy_version_token()
    with patch.object(settings, "LEARNER_OBSERVATION_DIAGNOSED_ONLY", True):
        assert policy_version_token() == off


@pytest.mark.parametrize("shape", SHAPES)
def test_flag_off_still_records_seeds(shape):
    _, sent, _ = _run(_shaped(_state(T17, ["concept:g01"], 2), shape), flag=False)
    assert len(sent) == (18 if shape == "raw" else 17)
    assert sent[0].concept_id == T17[0]


@pytest.mark.parametrize("skill", ["", None])
@pytest.mark.parametrize("shape", SHAPES)
def test_blank_skill_means_no_anchor(skill, shape):
    _, sent, _ = _run(_shaped(_state(T17, ["concept:g01"], 2), shape), skill=skill, difficulty="B1")
    assert _rows(sent) == [_root("concept:g01", 2)]


@pytest.mark.parametrize("skill", ["", None])
def test_blank_skill_on_a_clean_turn_sends_nothing(skill):
    returned, sent, fake = _run(_state(T17, [], 0), skill=skill)
    assert returned == {"observation_count": 0, "observation_durability_degraded": False}
    fake.persist_many.assert_not_called()


def test_formatted_with_weak_concepts_none_has_only_the_anchor():
    state = {"corrections": [{"error": "x"}], "linked_concepts": ["concept:t01"], "weak_concepts": None}
    _, sent, _ = _run(state)
    assert _rows(sent) == [_anchor("writing", "incorrect", 0.8, 1, 75.0, "B1")]


def test_formatted_with_corrections_none_is_a_clean_turn():
    state = {"corrections": None, "linked_concepts": ["concept:t01"], "weak_concepts": ["concept:g01"]}
    _, sent, _ = _run(state)
    assert _rows(sent) == [_anchor("writing", "correct", 0.6, 0, 100.0, "B1")]


def test_raw_with_diagnosis_fields_none():
    state = {"diagnosis_errors": None, "diagnosis_root_causes": None, "kg_seed_concepts": None}
    _, sent, _ = _run(state)
    assert _rows(sent) == [_anchor("writing", "correct", 0.6, 0, 100.0, "B1")]


def test_non_string_root_cause_ids_are_stringified_and_falsy_ones_dropped():
    state = _state([], [7, "7", 0, 3.5, ("a", 1)], 1)
    _, sent, _ = _run(state)
    assert [o.concept_id for o in sent] == ["skill:writing", "7", "3.5", "('a', 1)"]


@pytest.mark.parametrize("shape", SHAPES)
def test_root_cause_equal_to_the_anchor_id_is_sent_once_and_the_anchor_wins(shape):
    state = _state(T17, ["skill:writing", "concept:g01", "skill:writing"], 2)
    _, sent, _ = _run(_shaped(state, shape))
    assert _rows(sent) == [
        _anchor("writing", "incorrect", 0.8, 2, 50.0, "B1"),
        _root("concept:g01", 2),
    ]
    assert len({deterministic_event_id(o) for o in sent}) == len(sent)


def test_root_cause_equal_to_the_anchor_id_without_a_skill_is_a_normal_root_cause():
    _, sent, _ = _run(_state([], ["skill:writing"], 1), skill=None)
    assert _rows(sent) == [_root("skill:writing", 1)]


def test_anchor_duplicate_does_not_use_up_the_cap():
    roots = ["skill:writing"] + [f"concept:g{i:02d}" for i in range(1, 70)]
    _, sent, _ = _run(_state([], roots, 1))
    assert len(sent) == 60
    assert sent[-1].concept_id == "concept:g59"


@pytest.mark.parametrize("flag", [False, True])
def test_a_raising_spool_propagates_the_same_way_with_either_flag(flag):
    fake = create_autospec(LearnerObservationSpool, instance=True)
    fake.persist_many.side_effect = RuntimeError("mongo down")
    with pytest.raises(RuntimeError, match="mongo down"):
        _run(_state(T17, ["concept:g01"], 2), fake=fake, flag=flag)
    fake.persist_many.assert_awaited_once()
